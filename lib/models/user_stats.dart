import 'package:cloud_firestore/cloud_firestore.dart';

class UserStats {
  final int loginStreak;
  final DateTime? lastLoginDate;
  final int dailyQuestionsDone;
  final int dailyErrorsCleared;
  final int totalPoints;

  UserStats({
    this.loginStreak = 0,
    this.lastLoginDate,
    this.dailyQuestionsDone = 0,
    this.dailyErrorsCleared = 0,
    this.totalPoints = 0,
  });

  factory UserStats.fromFirestore(DocumentSnapshot doc) {
    if (!doc.exists) return UserStats();
    Map data = doc.data() as Map<String, dynamic>;
    return UserStats(
      loginStreak: data['loginStreak'] ?? 0,
      lastLoginDate: (data['lastLoginDate'] as Timestamp?)?.toDate(),
      dailyQuestionsDone: data['dailyQuestionsDone'] ?? 0,
      dailyErrorsCleared: data['dailyErrorsCleared'] ?? 0,
      totalPoints: data['totalPoints'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'loginStreak': loginStreak,
      'lastLoginDate': lastLoginDate != null ? Timestamp.fromDate(lastLoginDate!) : null,
      'dailyQuestionsDone': dailyQuestionsDone,
      'dailyErrorsCleared': dailyErrorsCleared,
      'totalPoints': totalPoints,
    };
  }

  // Helper to check if it's a new day and reset daily stats
  UserStats resetDailyIfNeeded() {
    final now = DateTime.now();

    if (lastLoginDate == null) {
      // 第一次記錄，視為新的一天開始，初始化 lastLoginDate 為今天，並將每日數據重設為 0
      return UserStats(
        loginStreak: loginStreak == 0 ? 1 : loginStreak,
        lastLoginDate: now,
        dailyQuestionsDone: 0,
        dailyErrorsCleared: 0,
        totalPoints: totalPoints,
      );
    }
    
    final last = lastLoginDate!;
    
    if (now.year != last.year || now.month != last.month || now.day != last.day) {
      // It's a new day
      int newStreak = loginStreak;
      
      // Check if streak is broken (more than 1 day gap)
      final difference = now.difference(DateTime(last.year, last.month, last.day)).inDays;
      if (difference > 1) {
        newStreak = 1;
      } else if (difference == 1) {
        newStreak += 1;
      }

      return UserStats(
        loginStreak: newStreak,
        lastLoginDate: now,
        dailyQuestionsDone: 0,
        dailyErrorsCleared: 0,
        totalPoints: totalPoints,
      );
    }

    // 防呆清理：如果 lastLoginDate 雖然是今天，但每日做題數大於 100 題（明顯是之前累加的歷史髒數據），也自動重置
    if (dailyQuestionsDone > 100) {
      return UserStats(
        loginStreak: loginStreak,
        lastLoginDate: now,
        dailyQuestionsDone: 0,
        dailyErrorsCleared: 0,
        totalPoints: totalPoints,
      );
    }

    return this;
  }
}
