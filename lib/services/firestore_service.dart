import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/exam_question.dart';
import '../models/quiz_session.dart';
import '../models/user_stats.dart';

class FirestoreService {
  final CollectionReference _questionsCollection =
      FirebaseFirestore.instance.collection('ExamQuestions');

  String get _currentUserId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("User must be authenticated to access personal statistics");
    }
    return user.uid;
  }

  DocumentReference get _userDoc =>
      FirebaseFirestore.instance.collection('users').doc(_currentUserId);

  CollectionReference get _sessionsCollection =>
      _userDoc.collection('QuizSessions');

  CollectionReference get _settingsCollection =>
      _userDoc.collection('UserSettings');

  // Stream all questions (Optimized with local cache priority)
  Stream<List<ExamQuestion>> getQuestionsStream() {
    return _questionsCollection
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      return snapshot.docs.map((doc) => ExamQuestion.fromFirestore(doc)).toList();
    });
  }

  // Single fetch with cache-first strategy to minimize read costs
  Future<List<ExamQuestion>> getAllQuestionsCached() async {
    try {
      // Try local cache first
      final snapshot = await _questionsCollection.get(const GetOptions(source: Source.cache));
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((doc) => ExamQuestion.fromFirestore(doc)).toList();
      }
    } catch (e) {
      // Cache fail or empty, fallback to server
    }
    
    final snapshot = await _questionsCollection.get(const GetOptions(source: Source.server));
    return snapshot.docs.map((doc) => ExamQuestion.fromFirestore(doc)).toList();
  }



  // Update a single question
  Future<void> updateQuestion(ExamQuestion question) async {
    await _questionsCollection.doc(question.id).update(question.toFirestore());
  }

  // Get questions paginated
  Future<Map<String, dynamic>> getQuestionsPaginated({int limit = 20, DocumentSnapshot? lastDoc}) async {
    Query query = _questionsCollection.limit(limit);
    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }
    final snapshot = await query.get();
    final questions = snapshot.docs.map((doc) => ExamQuestion.fromFirestore(doc)).toList();
    final newLastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
    return {
      'questions': questions,
      'lastDoc': newLastDoc,
    };
  }

  // Quiz Session CRUD
  Future<void> saveQuizSession(QuizSession session) async {
    await _sessionsCollection.doc(session.sessionId).set(session.toFirestore());
  }

  Future<List<QuizSession>> getQuizSessions() async {
    final snapshot = await _sessionsCollection.orderBy('timestamp', descending: true).get();
    return snapshot.docs.map((doc) => QuizSession.fromFirestore(doc)).toList();
  }

  Stream<List<QuizSession>> getQuizSessionsStream() {
    return _sessionsCollection
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => QuizSession.fromFirestore(doc)).toList();
    });
  }

  Future<void> updateQuestionNote(String questionId, String newNote) async {
    await _questionsCollection.doc(questionId).update({'userNote': newNote});
  }

  // Batch insert/update questions (used for initialization)
  Future<void> batchLoadQuestions(List<ExamQuestion> questions) async {
    final Map<String, Map<String, dynamic>> updates = {};
    for (var q in questions) {
      updates[q.id] = q.toFirestore();
    }
    await batchUpdateQuestionsFields(updates, isSet: true);
  }

  // Generic batch update method for bulk field changes (O(1) network overhead)
  Future<void> batchUpdateQuestionsFields(Map<String, Map<String, dynamic>> updates, {bool isSet = false}) async {
    int count = 0;
    WriteBatch batch = FirebaseFirestore.instance.batch();

    for (var entry in updates.entries) {
      final docId = entry.key;
      final updateData = entry.value;
      
      DocumentReference docRef = _questionsCollection.doc(docId);
      if (isSet) {
        batch.set(docRef, updateData, SetOptions(merge: true));
      } else {
        batch.update(docRef, updateData);
      }
      count++;
      
      if (count >= 450) {
        await batch.commit().timeout(const Duration(seconds: 15));
        batch = FirebaseFirestore.instance.batch();
        count = 0;
      }
    }
    
    if (count > 0) {
      await batch.commit().timeout(const Duration(seconds: 15));
    }
  }

  
  // Reset all questions progress
  Future<void> resetAllProgress(List<ExamQuestion> allQuestions) async {
    final int chunkSize = 450;
    
    // 1. Reset question stats
    for (var i = 0; i < allQuestions.length; i += chunkSize) {
      final batch = FirebaseFirestore.instance.batch();
      final end = (i + chunkSize < allQuestions.length) ? i + chunkSize : allQuestions.length;
      final chunk = allQuestions.sublist(i, end);
      
      for (var q in chunk) {
        DocumentReference docRef = _questionsCollection.doc(q.id);
        batch.update(docRef, {
          'errorCount': 0,
          'correctCount': 0,
          'attemptCount': 0,
          'lastAttemptDate': FieldValue.delete(),
          'isMastered': false,
          'isFavorite': false,
        });
      }
      await batch.commit().timeout(const Duration(seconds: 15));
    }

    // 2. Delete all quiz sessions
    bool hasMore = true;
    while (hasMore) {
      final snapshot = await _sessionsCollection.limit(chunkSize).get();
      if (snapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit().timeout(const Duration(seconds: 15));
      
      if (snapshot.docs.length < chunkSize) {
        hasMore = false;
      } else {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    // 3. Reset User Stats
    await updateUserStats(UserStats());
  }

  // Exam Date Management
  Future<void> saveExamDate(DateTime date) async {
    await _settingsCollection.doc('global').set({
      'examDate': Timestamp.fromDate(date),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<DateTime?> fetchExamDate() async {
    final doc = await _settingsCollection.doc('global').get();
    if (doc.exists && doc.data() != null) {
      final data = doc.data() as Map<String, dynamic>;
      final timestamp = data['examDate'] as Timestamp?;
      return timestamp?.toDate();
    }
    return null;
  }

  // User Stats Methods
  Future<UserStats> getUserStats() async {
    final doc = await _settingsCollection.doc('stats').get();
    final stats = UserStats.fromFirestore(doc);
    final resetStats = stats.resetDailyIfNeeded();
    print("DEBUG [getUserStats]: original lastLoginDate=${stats.lastLoginDate}, dailyDone=${stats.dailyQuestionsDone}");
    print("DEBUG [getUserStats]: now=${DateTime.now()}, reset lastLoginDate=${resetStats.lastLoginDate}, dailyDone=${resetStats.dailyQuestionsDone}");
    if (resetStats != stats) {
      print("DEBUG [getUserStats]: WRITING reset stats to Firestore");
      await updateUserStats(resetStats);
    }
    return resetStats;
  }

  Stream<UserStats> getUserStatsStream() {
    return _settingsCollection
        .doc('stats')
        .snapshots()
        .asyncMap((doc) async {
          final stats = UserStats.fromFirestore(doc);
          final resetStats = stats.resetDailyIfNeeded();
          print("DEBUG [getUserStatsStream]: original lastLoginDate=${stats.lastLoginDate}, dailyDone=${stats.dailyQuestionsDone}");
          print("DEBUG [getUserStatsStream]: now=${DateTime.now()}, reset lastLoginDate=${resetStats.lastLoginDate}, dailyDone=${resetStats.dailyQuestionsDone}");
          if (resetStats != stats) {
            print("DEBUG [getUserStatsStream]: WRITING reset stats to Firestore");
            await updateUserStats(resetStats);
          }
          return resetStats;
        });
  }

  Future<void> updateUserStats(UserStats stats) async {
    await _settingsCollection.doc('stats').set(stats.toFirestore(), SetOptions(merge: true));
  }

  // Delete all questions in smaller chunks to avoid memory/timeout issues
  Future<void> deleteAllQuestions() async {
    bool hasMore = true;
    while (hasMore) {
      final snapshot = await _questionsCollection.limit(450).get();
      if (snapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit().timeout(const Duration(seconds: 15));
      
      // If we got fewer than requested, we're done
      if (snapshot.docs.length < 450) {
        hasMore = false;
      } else {
        // Add a small delay between batches to prevent UI/Network lock
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  // Delete questions by year
  Future<void> deleteQuestionsByYear(String year) async {
    bool hasMore = true;
    while (hasMore) {
      final snapshot = await _questionsCollection
          .where('year', isEqualTo: year)
          .limit(450)
          .get();
          
      if (snapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit().timeout(const Duration(seconds: 15));
      
      if (snapshot.docs.length < 450) {
        hasMore = false;
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  // Update questions year (Performance-first: Field update only)
  Future<void> updateQuestionsYear(String oldYear, String newYear) async {
    bool hasMore = true;
    while (hasMore) {
      final snapshot = await _questionsCollection
          .where('year', isEqualTo: oldYear)
          .limit(450)
          .get();
          
      if (snapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }

      final Map<String, Map<String, dynamic>> updates = {};
      for (var doc in snapshot.docs) {
        updates[doc.id] = {'year': newYear};
      }
      
      await batchUpdateQuestionsFields(updates);

      if (snapshot.docs.length < 450) {
        hasMore = false;
      } else {
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  // Sync QuizSessions references to match new question IDs (Kept for compatibility, but not used in current year update)
  Future<void> migrateQuizSessionReferences(Map<String, String> idMap) async {

    final snapshot = await _sessionsCollection.get();
    if (snapshot.docs.isEmpty) return;

    final batchLimit = 450;
    WriteBatch batch = FirebaseFirestore.instance.batch();
    int count = 0;

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final List<dynamic> oldIds = data['wrongQuestionIds'] ?? [];
      bool needsUpdate = false;
      
      final List<String> updatedIds = [];
      for (var id in oldIds) {
        if (idMap.containsKey(id)) {
          updatedIds.add(idMap[id]!);
          needsUpdate = true;
        } else {
          updatedIds.add(id as String);
        }
      }

      if (needsUpdate) {
        batch.update(doc.reference, {'wrongQuestionIds': updatedIds});
        count++;
        
        if (count >= batchLimit) {
          await batch.commit().timeout(const Duration(seconds: 15));
          batch = FirebaseFirestore.instance.batch();
          count = 0;
          await Future.delayed(const Duration(milliseconds: 200));
        }
      }
    }

    if (count > 0) {
      await batch.commit().timeout(const Duration(seconds: 15));
    }
  }


  // Atomically save QuizSession and all updated Question states in one Batch
  Future<void> saveQuizResult(
    QuizSession session, 
    List<ExamQuestion> updatedQuestions, 
    UserStats updatedStats,
  ) async {
    WriteBatch batch = FirebaseFirestore.instance.batch();
    
    // 1. Save Session
    DocumentReference sessionRef = _sessionsCollection.doc(session.sessionId);
    batch.set(sessionRef, session.toFirestore());

    // 2. Save Updated Questions
    for (var q in updatedQuestions) {
      DocumentReference qRef = _questionsCollection.doc(q.id);
      batch.update(qRef, q.toFirestore());
    }

    // 3. Save User Stats
    DocumentReference statsRef = _settingsCollection.doc('stats');
    batch.set(statsRef, updatedStats.toFirestore(), SetOptions(merge: true));

    await batch.commit().timeout(const Duration(seconds: 15));
  }

  Future<void> deleteQuizSession(String sessionId) async {
    final sessionDoc = await _sessionsCollection.doc(sessionId).get();
    if (!sessionDoc.exists) return;
    final session = QuizSession.fromFirestore(sessionDoc);
    
    // Decrease User Stats
    final stats = await getUserStats();
    final newStats = UserStats(
      loginStreak: stats.loginStreak,
      lastLoginDate: stats.lastLoginDate,
      dailyQuestionsDone: (stats.dailyQuestionsDone - session.totalQuestions).clamp(0, 9999),
      dailyErrorsCleared: (stats.dailyErrorsCleared - (session.totalQuestions - session.wrongCount)).clamp(0, 9999),
      totalPoints: (stats.totalPoints - (session.totalQuestions * 10)).clamp(0, 999999),
    );
    
    WriteBatch batch = FirebaseFirestore.instance.batch();
    batch.delete(_sessionsCollection.doc(sessionId));
    batch.set(_settingsCollection.doc('stats'), newStats.toFirestore(), SetOptions(merge: true));
    await batch.commit();
  }
}
