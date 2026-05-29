import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/exam_question.dart';
import '../models/quiz_session.dart';
import '../models/user_stats.dart';
import '../services/firestore_service.dart';

class QuizProvider with ChangeNotifier {
  final FirestoreService _service;
  final List<ExamQuestion> questions;
  final bool isSpecialTraining;

  int _currentIndex = 0;
  final List<ExamQuestion> _wrongQuestions = [];
  final Map<String, int> _userAnswers = {};
  bool _hasAnsweredCurrent = false;
  int? _selectedOption;
  bool _isFinished = false;
  final Set<String> _modifiedQuestionIds = {};

  QuizProvider({
    required FirestoreService service,
    required this.questions,
    required this.isSpecialTraining,
  }) : _service = service;

  int get currentIndex => _currentIndex;
  List<ExamQuestion> get wrongQuestions => _wrongQuestions;
  Map<String, int> get userAnswers => _userAnswers;
  bool get hasAnsweredCurrent => _hasAnsweredCurrent;
  int? get selectedOption => _selectedOption;
  bool get isFinished => _isFinished;
  Set<String> get modifiedQuestionIds => _modifiedQuestionIds;

  ExamQuestion get currentQuestion => questions[_currentIndex];

  void submitAnswer(int index) {
    if (_hasAnsweredCurrent) return;

    _selectedOption = index;
    _hasAnsweredCurrent = true;
    final q = currentQuestion;
    _userAnswers[q.id] = index;
    _modifiedQuestionIds.add(q.id);

    q.attemptCount += 1;
    q.lastAttemptDate = DateTime.now();

    if (q.correctAnswers.contains(index)) {
      q.correctCount += 1;
      if (q.correctCount >= 2) {
        q.isMastered = true;
      }
      // Spaced Repetition logic
      int days = (q.correctCount * 3).clamp(1, 30);
      q.nextReviewDate = DateTime.now().add(Duration(days: days));
    } else {
      q.errorCount += 1;
      q.correctCount = 0; // Reset streak
      q.nextReviewDate = DateTime.now().add(const Duration(days: 1));
      if (!_wrongQuestions.contains(q)) {
        _wrongQuestions.add(q);
      }
    }
    notifyListeners();
  }

  void nextQuestion(VoidCallback onFinished) {
    if (_currentIndex < questions.length - 1) {
      _currentIndex += 1;
      _hasAnsweredCurrent = false;
      _selectedOption = null;
      notifyListeners();
    } else {
      finishQuiz(onFinished);
    }
  }

  Future<void> finishQuiz(VoidCallback onFinished) async {
    final session = QuizSession(
      sessionId: const Uuid().v4(),
      timestamp: DateTime.now(),
      totalQuestions: questions.length,
      wrongCount: _wrongQuestions.length,
      wrongQuestionIds: _wrongQuestions.map((q) => q.id).toList(),
      userAnswers: _userAnswers,
    );

    final updatedQuestions = questions
        .where((q) => _modifiedQuestionIds.contains(q.id))
        .toList();

    // Calculate cleared errors and updated user statistics
    int clearedErrors = 0;
    for (var q in updatedQuestions) {
      final bool wasCorrect = !session.wrongQuestionIds.contains(q.id);
      if (wasCorrect && q.errorCount >= 2) {
        clearedErrors++;
      }
    }

    final stats = await _service.getUserStats();
    final newStats = UserStats(
      loginStreak: stats.loginStreak,
      lastLoginDate: stats.lastLoginDate,
      dailyQuestionsDone: stats.dailyQuestionsDone + session.totalQuestions,
      dailyErrorsCleared: stats.dailyErrorsCleared + clearedErrors,
      totalPoints: stats.totalPoints + (session.totalQuestions * 10) + (clearedErrors * 50),
    ).resetDailyIfNeeded();

    await _service.saveQuizResult(session, updatedQuestions, newStats);

    if (isSpecialTraining) {
      onFinished();
    } else {
      _isFinished = true;
      notifyListeners();
    }
  }

  void toggleFavorite() {
    final q = currentQuestion;
    q.isFavorite = !q.isFavorite;
    _modifiedQuestionIds.add(q.id);
    notifyListeners();
  }
}
