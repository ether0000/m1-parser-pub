import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/exam_question.dart';
import '../models/quiz_session.dart';
import '../models/user_stats.dart';
import '../services/firestore_service.dart';

class AppProvider with ChangeNotifier {
  final FirestoreService _service;
  
  List<ExamQuestion> _questions = [];
  List<QuizSession> _sessions = [];
  UserStats _userStats = UserStats();
  bool _isLoading = true;
  
  StreamSubscription? _questionsSub;
  StreamSubscription? _sessionsSub;
  StreamSubscription? _userStatsSub;
  DateTime? _examDate;

  AppProvider(this._service) {
    _init();
  }

  void _init() {
    _questionsSub = _service.getQuestionsStream().listen((qs) {
      _questions = qs;
      _isLoading = false;
      notifyListeners();
    });

    _sessionsSub = _service.getQuizSessionsStream().listen((ss) {
      _sessions = ss;
      notifyListeners();
    });

    _userStatsSub = _service.getUserStatsStream().listen((stats) {
      _userStats = stats;
      notifyListeners();
    });

    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    _userStats = await _service.getUserStats();
    _examDate = await _service.fetchExamDate();
    
    // Check-in / Login Streak logic
    final updatedStats = _userStats.resetDailyIfNeeded();
    if (updatedStats != _userStats) {
      _userStats = updatedStats;
      await _service.updateUserStats(_userStats);
    }
    
    notifyListeners();
  }

  List<ExamQuestion> get questions => _questions;
  List<QuizSession> get sessions => _sessions;
  UserStats get userStats => _userStats;
  bool get isLoading => _isLoading;

  // Filtered Getters (Optimized for Dashboard/Tabs)
  List<ExamQuestion> get scheduledReviews => 
      _questions.where((q) => q.nextReviewDate != null && 
          q.nextReviewDate!.isBefore(DateTime.now().add(const Duration(hours: 4)))).toList();

  List<ExamQuestion> get frequentErrors => 
      _questions.where((q) => q.errorCount >= 2 && !q.isMastered).toList();

  int get totalMastered => _questions.where((q) => q.isMastered).length;
  
  int get totalAttempted => _questions.where((q) => q.attemptCount > 0).length;

  double get overallAccuracy {
    int total = 0;
    int correct = 0;
    for (var q in _questions) {
      total += q.attemptCount;
      correct += q.correctCount;
    }
    return total > 0 ? (correct / total) * 100 : 0;
  }

  int get dailyQuota {
    if (_examDate == null || _questions.isEmpty) return 20;
    final now = DateTime.now();
    final diff = _examDate!.difference(now).inDays;
    if (diff <= 0) return 0;
    
    int unattempted = _questions.where((q) => q.attemptCount == 0 && !q.isMastered).length;
    return (unattempted / diff).ceil().clamp(5, 100);
  }

  double get quest1Progress => (_userStats.dailyQuestionsDone / 20).clamp(0.0, 1.0);
  double get quest2Progress => (_userStats.dailyErrorsCleared / 5).clamp(0.0, 1.0);

  @override
  void dispose() {
    _questionsSub?.cancel();
    _sessionsSub?.cancel();
    _userStatsSub?.cancel();
    super.dispose();
  }
}
