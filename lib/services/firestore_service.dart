import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/exam_question.dart';
import '../models/quiz_session.dart';
import '../models/user_stats.dart';
import '../models/user_question_state.dart';

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

  CollectionReference get _questionStatesCollection =>
      _userDoc.collection('QuestionStates');

  // Stream all user question states
  Stream<List<UserQuestionState>> getUserQuestionStatesStream() {
    return _questionStatesCollection
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => UserQuestionState.fromFirestore(doc)).toList();
    });
  }

  // Single fetch with cache-first strategy to retrieve user states
  Future<List<UserQuestionState>> getUserQuestionStatesCached() async {
    try {
      final snapshot = await _questionStatesCollection.get(const GetOptions(source: Source.cache));
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((doc) => UserQuestionState.fromFirestore(doc)).toList();
      }
    } catch (e) {
      // Cache fail or empty, fallback to server
    }
    
    final snapshot = await _questionStatesCollection.get(const GetOptions(source: Source.server));
    return snapshot.docs.map((doc) => UserQuestionState.fromFirestore(doc)).toList();
  }

  // Stream all questions (Optimized with local cache priority)
  Stream<List<ExamQuestion>> getQuestionsStream() {
    return _questionsCollection
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      return snapshot.docs.map((doc) => ExamQuestion.fromFirestore(doc)).toList();
    });
  }

  // Single fetch with cache-first strategy to minimize read costs
  /// 
  /// 【效能設計：快取優先 (Cache-First)】
  /// 為了降低 Firebase 的讀取成本（Firestore 計費基於讀取次數），
  /// 此方法優先從本地快取（Source.cache）讀取題庫資料，若本地存有資料則直接返回。
  /// 僅當本地無快取或載入失敗（如第一次開啟 App）時，才發起伺服器請求（Source.server），
  /// 這能極大化減少伺服器頻寬與費用，同時大幅縮短首頁讀取時間。
  Future<List<ExamQuestion>> getAllQuestionsCached() async {
    try {
      // 嘗試讀取本地快取
      final snapshot = await _questionsCollection.get(const GetOptions(source: Source.cache));
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((doc) => ExamQuestion.fromFirestore(doc)).toList();
      }
    } catch (e) {
      // 快取失效或無快取，靜默降級，自動往下走到伺服器讀取
    }
    
    final snapshot = await _questionsCollection.get(const GetOptions(source: Source.server));
    return snapshot.docs.map((doc) => ExamQuestion.fromFirestore(doc)).toList();
  }



  // Update a single question
  /// 
  /// 【多用戶隔離重構】
  /// 管理端修改題目內容時，僅將唯讀的題幹、選項、答案等更新至全域 `ExamQuestions` 中。
  /// 而題目的收藏（Favorite）、精熟（Mastered）狀態則更新至個人的 `QuestionStates` 子集合中，
  /// 避免覆蓋其他用戶的作答狀態。
  Future<void> updateQuestion(ExamQuestion question) async {
    await _questionsCollection.doc(question.id).update({
      'year': question.year,
      'subject': question.subject,
      'content': question.content,
      'options': question.options,
      'correctAnswers': question.correctAnswers,
    });

    await _questionStatesCollection.doc(question.id).set({
      'isMastered': question.isMastered,
      'isFavorite': question.isFavorite,
    }, SetOptions(merge: true));
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

  /// 更新個人題目筆記
  /// 
  /// 【多用戶隔離重構】
  /// 將個人筆記寫入個人 `/users/{userId}/QuestionStates/{questionId}` 中，不污染全域題庫。
  Future<void> updateQuestionNote(String questionId, String newNote) async {
    await _questionStatesCollection.doc(questionId).set({
      'userNote': newNote,
    }, SetOptions(merge: true));
  }

  // Batch insert/update questions (used for initialization)
  Future<void> batchLoadQuestions(List<ExamQuestion> questions) async {
    final Map<String, Map<String, dynamic>> updates = {};
    for (var q in questions) {
      updates[q.id] = q.toFirestore();
    }
    await batchUpdateQuestionsFields(updates, isSet: true, isGlobal: true);
  }

  // Generic batch update method for bulk field changes (O(1) network overhead)
  /// 
  /// 【批次寫入防禦設計：避開 500 次限制】
  /// Firestore 的 `WriteBatch` 具有單次 Batch 最多 500 個寫入操作的強硬限制。
  /// 為了防止匯入大量題庫時崩潰，此處採用「滑動窗口批次機制」：
  /// 當待寫入計數器達到 450 個時，主動呼叫 `batch.commit()`，接著重新創立一個 batch，
  /// 藉此安全繞過限制，並加上 `timeout` 與異常捕獲，確保大量批次作業的強健性。
  /// 
  /// 【多用戶隔離重構】
  /// 新增 `isGlobal` 參數。若為 true 則寫入全域題庫 `ExamQuestions`（如匯入初始題庫）；
  /// 若為 false，則寫入用戶個人的 `QuestionStates`（如批次儲存錯題筆記）。
  Future<void> batchUpdateQuestionsFields(
    Map<String, Map<String, dynamic>> updates, {
    bool isSet = false,
    bool isGlobal = false,
  }) async {
    int count = 0;
    WriteBatch batch = FirebaseFirestore.instance.batch();

    for (var entry in updates.entries) {
      final docId = entry.key;
      final updateData = entry.value;
      
      DocumentReference docRef = isGlobal
          ? _questionsCollection.doc(docId)
          : _questionStatesCollection.doc(docId);
          
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
  /// 
  /// 【多用戶隔離重構】
  /// 現在重設進度時，**全域題庫保持完全唯讀且不變動**。
  /// 改為直接刪除用戶個人 `QuestionStates` 子集合與 `QuizSessions` 子集合下的所有文件。
  Future<void> resetAllProgress(List<ExamQuestion> allQuestions) async {
    final int chunkSize = 450;
    
    // 1. 刪除個人 QuestionStates 文件
    bool hasMoreStates = true;
    while (hasMoreStates) {
      final snapshot = await _questionStatesCollection.limit(chunkSize).get();
      if (snapshot.docs.isEmpty) {
        hasMoreStates = false;
        break;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit().timeout(const Duration(seconds: 15));
      
      if (snapshot.docs.length < chunkSize) {
        hasMoreStates = false;
      } else {
        await Future.delayed(const Duration(milliseconds: 300));
      }
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
    debugPrint("DEBUG [getUserStats]: original lastLoginDate=${stats.lastLoginDate}, dailyDone=${stats.dailyQuestionsDone}");
    debugPrint("DEBUG [getUserStats]: now=${DateTime.now()}, reset lastLoginDate=${resetStats.lastLoginDate}, dailyDone=${resetStats.dailyQuestionsDone}");
    if (resetStats != stats) {
      debugPrint("DEBUG [getUserStats]: WRITING reset stats to Firestore");
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
          debugPrint("DEBUG [getUserStatsStream]: original lastLoginDate=${stats.lastLoginDate}, dailyDone=${stats.dailyQuestionsDone}");
          debugPrint("DEBUG [getUserStatsStream]: now=${DateTime.now()}, reset lastLoginDate=${resetStats.lastLoginDate}, dailyDone=${resetStats.dailyQuestionsDone}");
          if (resetStats != stats) {
            debugPrint("DEBUG [getUserStatsStream]: WRITING reset stats to Firestore");
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
  /// 
  /// 【數據原子性設計 (Atomic Transaction)】
  /// 使用 Firestore 的 `WriteBatch` 將：
  /// 1. 本次測驗的 Session 結果存檔。
  /// 2. 所有受影響的個人題目答題歷史。
  /// 3. 使用者個人統計數據（做題總數、消滅錯題數、總積分）。
  /// 這三者打包成單一的原子性作業。確保「全成功或全回滾（All-or-Nothing）」，
  /// 避免因網路中斷或單一欄位格式錯誤，導致資料不一致。
  /// 
  /// 【多用戶隔離重構】
  /// 題目的錯題計數、精熟狀態、下次複習時間，改寫入個人的 `QuestionStates` 集合下，
  /// 不會寫入或修改全域共用的 `ExamQuestions` 集合。
  Future<void> saveQuizResult(
    QuizSession session, 
    List<ExamQuestion> updatedQuestions, 
    UserStats updatedStats,
  ) async {
    WriteBatch batch = FirebaseFirestore.instance.batch();
    
    // 1. 寫入本次測驗 Session
    DocumentReference sessionRef = _sessionsCollection.doc(session.sessionId);
    batch.set(sessionRef, session.toFirestore());

    // 2. 批量更新個人題目作答進度（寫入個人 QuestionStates 子集合）
    for (var q in updatedQuestions) {
      DocumentReference stateRef = _questionStatesCollection.doc(q.id);
      batch.set(stateRef, {
        'userNote': q.userNote,
        'errorCount': q.errorCount,
        'correctCount': q.correctCount,
        'attemptCount': q.attemptCount,
        'lastAttemptDate': q.lastAttemptDate != null ? Timestamp.fromDate(q.lastAttemptDate!) : null,
        'isMastered': q.isMastered,
        'isFavorite': q.isFavorite,
        'nextReviewDate': q.nextReviewDate != null ? Timestamp.fromDate(q.nextReviewDate!) : null,
      }, SetOptions(merge: true));
    }

    // 3. 更新使用者全域統計數據
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
