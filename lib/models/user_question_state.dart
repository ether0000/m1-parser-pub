import 'package:cloud_firestore/cloud_firestore.dart';

/// 個人做題狀態數據模型
/// 
/// 專門用來存放特定用戶與特定題目之間的綁定狀態（如答題紀錄、個人筆記、收藏狀態等）。
/// 用於將全域唯讀題庫與個人隱私數據進行物理隔離。
class UserQuestionState {
  final String questionId;
  final String userNote;
  final int errorCount;
  final int correctCount;
  final int attemptCount;
  final DateTime? lastAttemptDate;
  final bool isMastered;
  final bool isFavorite;
  final DateTime? nextReviewDate;

  UserQuestionState({
    required this.questionId,
    this.userNote = '',
    this.errorCount = 0,
    this.correctCount = 0,
    this.attemptCount = 0,
    this.lastAttemptDate,
    this.isMastered = false,
    this.isFavorite = false,
    this.nextReviewDate,
  });

  /// 從 Firestore 的 document 解析個人狀態
  factory UserQuestionState.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    final Map<String, dynamic> data = rawData is Map<String, dynamic> ? rawData : {};
    
    // 安全地轉換 DateTime 類型，相容 Timestamp 與 String 格式
    DateTime? parseDateTime(dynamic field) {
      if (field is Timestamp) return field.toDate();
      if (field is String) return DateTime.tryParse(field);
      if (field is int) return DateTime.fromMillisecondsSinceEpoch(field);
      return null;
    }

    return UserQuestionState(
      questionId: doc.id,
      userNote: data['userNote']?.toString() ?? '',
      errorCount: int.tryParse(data['errorCount']?.toString() ?? '0') ?? 0,
      correctCount: int.tryParse(data['correctCount']?.toString() ?? '0') ?? 0,
      attemptCount: int.tryParse(data['attemptCount']?.toString() ?? '0') ?? 0,
      lastAttemptDate: parseDateTime(data['lastAttemptDate']),
      isMastered: data['isMastered'] == true,
      isFavorite: data['isFavorite'] == true,
      nextReviewDate: parseDateTime(data['nextReviewDate']),
    );
  }

  /// 轉換為 Firestore 文件對應 Map，便於 WriteBatch 批次寫入
  Map<String, dynamic> toFirestore() {
    return {
      'userNote': userNote,
      'errorCount': errorCount,
      'correctCount': correctCount,
      'attemptCount': attemptCount,
      'lastAttemptDate': lastAttemptDate != null ? Timestamp.fromDate(lastAttemptDate!) : null,
      'isMastered': isMastered,
      'isFavorite': isFavorite,
      'nextReviewDate': nextReviewDate != null ? Timestamp.fromDate(nextReviewDate!) : null,
    };
  }
}
