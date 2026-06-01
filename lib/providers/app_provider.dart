import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/exam_question.dart';
import '../models/quiz_session.dart';
import '../models/user_stats.dart';
import '../models/user_question_state.dart';
import '../services/firestore_service.dart';

class AppProvider with ChangeNotifier {
  final FirestoreService _service;
  
  List<ExamQuestion> _questions = [];
  List<ExamQuestion> _rawQuestions = [];
  Map<String, UserQuestionState> _userStatesMap = {};
  List<QuizSession> _sessions = [];
  UserStats _userStats = UserStats();
  bool _isLoading = true;
  
  StreamSubscription? _questionsSub;
  StreamSubscription? _userStatesSub;
  StreamSubscription? _sessionsSub;
  StreamSubscription? _userStatsSub;
  DateTime? _examDate;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  AppProvider(this._service) {
    _init();
  }

  void _init() {
    debugPrint('【AppProvider 初始化開始】監聽 Firestore 資料流');
    _questionsSub = _service.getQuestionsStream().listen(
      (qs) {
        debugPrint('【流載入】成功獲取全域 ExamQuestions 共 ${qs.length} 題');
        _rawQuestions = qs;
        _mergeQuestionsAndStates();
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
      },
      onError: (error, stackTrace) {
        debugPrint('【流載入失敗】全域題庫載入錯誤: $error \n 堆疊追蹤: $stackTrace');
        _isLoading = false;
        _errorMessage = "載入題目發生錯誤，請檢查網路連線。";
        notifyListeners();
      },
    );

    // 監聽該登入用戶個人的題目作答與筆記狀態，並隨時與全域題庫進行合併
    _userStatesSub = _service.getUserQuestionStatesStream().listen(
      (states) {
        debugPrint('【流載入】成功獲取個人 QuestionStates 共 ${states.length} 筆資料');
        if (states.isEmpty) {
          debugPrint('【提示】個人狀態為空（新用戶或尚未做過任何題目）');
        }
        _userStatesMap = {for (var s in states) s.questionId: s};
        _mergeQuestionsAndStates();
        notifyListeners();
      },
      onError: (error, stackTrace) {
        debugPrint('【流載入失敗】個人狀態載入錯誤: $error \n 堆疊追蹤: $stackTrace');
      },
    );

    _sessionsSub = _service.getQuizSessionsStream().listen(
      (ss) {
        debugPrint('【流載入】成功獲取個人歷史 QuizSessions 共 ${ss.length} 筆資料');
        _sessions = ss;
        notifyListeners();
      },
      onError: (error, stackTrace) {
        debugPrint('【流載入失敗】個人歷史載入錯誤: $error \n 堆疊追蹤: $stackTrace');
      },
    );

    _userStatsSub = _service.getUserStatsStream().listen(
      (stats) {
        debugPrint('【流載入】成功獲取個人統計 UserStats (積分: ${stats.totalPoints})');
        _userStats = stats;
        notifyListeners();
      },
      onError: (error, stackTrace) {
        debugPrint('【流載入失敗】個人統計載入錯誤: $error \n 堆疊追蹤: $stackTrace');
      },
    );

    _loadInitialData();
  }

  /// 合併全域唯讀題庫與個人狀態
  /// 
  /// 藉由 questionId 作為 Key，將個人在 QuestionStates 集合中擁有的
  /// errorCount、userNote、isMastered、isFavorite 等資料覆蓋到全域題目的欄位中，
  /// 組合成一個帶有個人狀態的 ExamQuestion 實體，維持前端 UI 在呼叫時無痛相容。
  void _mergeQuestionsAndStates() {
    debugPrint('【合併邏輯】開始進行資料組合與洗牌。RawQuestions: ${_rawQuestions.length}, StatesMap: ${_userStatesMap.length}');
    try {
      _questions = _rawQuestions.map((q) {
        final state = _userStatesMap[q.id];
        if (state == null) {
          // 新用戶，個人狀態為空
          return ExamQuestion(
            id: q.id,
            year: q.year,
            subject: q.subject,
            content: q.content,
            options: q.options,
            correctAnswers: q.correctAnswers,
            categoryIds: q.categoryIds,
            tags: q.tags,
            // 新用戶預設值（錯誤次數 0，不精通，未收藏）
            userNote: '',
            errorCount: 0,
            correctCount: 0,
            attemptCount: 0,
            lastAttemptDate: null,
            isMastered: false,
            isFavorite: false,
            nextReviewDate: null,
          );
        }
        return ExamQuestion(
          id: q.id,
          year: q.year,
          subject: q.subject,
          content: q.content,
          options: q.options,
          correctAnswers: q.correctAnswers,
          categoryIds: q.categoryIds,
          tags: q.tags,
          // 個人隔離狀態欄位
          userNote: state.userNote,
          errorCount: state.errorCount,
          correctCount: state.correctCount,
          attemptCount: state.attemptCount,
          lastAttemptDate: state.lastAttemptDate,
          isMastered: state.isMastered,
          isFavorite: state.isFavorite,
          nextReviewDate: state.nextReviewDate,
        );
      }).toList();
      debugPrint('【合併邏輯】資料組合與洗牌完成。合併後 Questions: ${_questions.length}');
    } catch (e, stackTrace) {
      debugPrint('【合併邏輯錯誤】發生欄位轉型或其他錯誤: $e \n 堆疊追蹤: $stackTrace');
    }
  }

  Future<void> _loadInitialData() async {
    debugPrint('【載入初始設定】開始撈取個人統計與考試時間');
    try {
      _userStats = await _service.getUserStats();
      debugPrint('成功撈取個人統計，當前積分為: ${_userStats.totalPoints}');
      _examDate = await _service.fetchExamDate();
      debugPrint('成功撈取考試日期: $_examDate');
      
      // Check-in / Login Streak logic
      final updatedStats = _userStats.resetDailyIfNeeded();
      if (updatedStats != _userStats) {
        _userStats = updatedStats;
        await _service.updateUserStats(_userStats);
        debugPrint('更新每日連續登入天數與歸零每日做題數');
      }
    } catch (e, stackTrace) {
      debugPrint('【載入初始設定失敗】: $e \n 堆疊追蹤: $stackTrace');
      _errorMessage = "無法從雲端同步個人進度與設定";
    } finally {
      notifyListeners();
    }
  }

  void resetExamDate() {
    _examDate = null;
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
    _userStatesSub?.cancel();
    _sessionsSub?.cancel();
    _userStatsSub?.cancel();
    super.dispose();
  }
}
