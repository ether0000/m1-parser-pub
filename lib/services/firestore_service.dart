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

  // Stream all questions (e.g. for the Dashboard)
  Stream<List<ExamQuestion>> getQuestionsStream() {
    return _questionsCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => ExamQuestion.fromFirestore(doc)).toList();
    });
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
    // Firestore allows maximum 500 writes per batch. We chunk every 450 to be safe.
    final int chunkSize = 450;
    for (var i = 0; i < questions.length; i += chunkSize) {
      final batch = FirebaseFirestore.instance.batch();
      final end = (i + chunkSize < questions.length) ? i + chunkSize : questions.length;
      final chunk = questions.sublist(i, end);
      
      for (var q in chunk) {
        DocumentReference docRef = _questionsCollection.doc(q.id);
        batch.set(docRef, q.toFirestore(), SetOptions(merge: true));
      }
      
      // Setting a 15-second timeout, if Firebase is disconnected or security rules block it, it won't spin forever.
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
      }
    }
  }
}
