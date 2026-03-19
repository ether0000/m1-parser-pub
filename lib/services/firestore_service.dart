import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/exam_question.dart';
import '../models/quiz_session.dart';
import '../models/question_category.dart';

class FirestoreService {
  final CollectionReference _questionsCollection =
      FirebaseFirestore.instance.collection('ExamQuestions');
  final CollectionReference _sessionsCollection =
      FirebaseFirestore.instance.collection('QuizSessions');
  final CollectionReference _categoriesCollection =
      FirebaseFirestore.instance.collection('QuestionCategories');
  final CollectionReference _settingsCollection =
      FirebaseFirestore.instance.collection('UserSettings');

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

  // Question Category CRUD
  Future<void> saveCategory(QuestionCategory category) async {
    await _categoriesCollection.doc(category.categoryId).set(category.toFirestore());
  }

  Future<List<QuestionCategory>> getCategories() async {
    final snapshot = await _categoriesCollection.get();
    return snapshot.docs.map((doc) => QuestionCategory.fromFirestore(doc)).toList();
  }

  // Notes and Categories updates
  Future<void> updateQuestionNote(String questionId, String newNote) async {
    await _questionsCollection.doc(questionId).update({'userNote': newNote});
  }

  Future<void> updateQuestionTags(String questionId, List<String> tags) async {
    await _questionsCollection.doc(questionId).update({'tags': tags});
  }

  Future<void> addQuestionToCategory(String questionId, String categoryId) async {
    await _questionsCollection.doc(questionId).update({
      'categoryIds': FieldValue.arrayUnion([categoryId])
    });
  }

  Future<void> removeQuestionFromCategory(String questionId, String categoryId) async {
    await _questionsCollection.doc(questionId).update({
      'categoryIds': FieldValue.arrayRemove([categoryId])
    });
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
  Future<void> saveQuizResult(QuizSession session, List<ExamQuestion> updatedQuestions) async {
    WriteBatch batch = FirebaseFirestore.instance.batch();
    
    // 1. Save Session
    DocumentReference sessionRef = _sessionsCollection.doc(session.sessionId);
    batch.set(sessionRef, session.toFirestore());

    // 2. Save Updated Questions
    for (var q in updatedQuestions) {
      DocumentReference qRef = _questionsCollection.doc(q.id);
      batch.update(qRef, q.toFirestore());
    }

    await batch.commit().timeout(const Duration(seconds: 15));
  }

  // Delete a specific quiz session

  Future<void> deleteQuizSession(String sessionId) async {
    await _sessionsCollection.doc(sessionId).delete();
  }
}
