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
    if (lastLoginDate == null) return this;
    
    final now = DateTime.now();
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
    return this;
  }
}
