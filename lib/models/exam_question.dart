import 'package:cloud_firestore/cloud_firestore.dart';

class ExamQuestion {
  final String id;
  final String year;
  final String subject;
  final String content;
  final List<String> options;
  final List<int> correctAnswers;
  
  // Backward compatibility getter
  int get correctAnswer => correctAnswers.isNotEmpty ? correctAnswers.first : 0;
  String userNote;
  int errorCount;
  int correctCount;
  int attemptCount;
  DateTime? lastAttemptDate;
  bool isMastered;
  bool isFavorite;
  List<String> categoryIds;
  List<String> tags;
  DateTime? nextReviewDate;

  /// 解析 ID 中的數字部分 (例如 "2020下-50" -> 50)
  static int parseQuestionNumber(String id) {
    try {
      if (id.contains('-')) {
        final part = id.split('-').last;
        return int.parse(part);
      }
      return int.parse(id);
    } catch (e) {
      return 0;
    }
  }

  /// 方便排序使用的題號 getter
  int get questionNumber => parseQuestionNumber(id);

  ExamQuestion({
    required this.id,
    required this.year,
    required this.subject,
    required this.content,
    required this.options,
    required this.correctAnswers,
    this.userNote = '',
    this.errorCount = 0,
    this.correctCount = 0,
    this.attemptCount = 0,
    this.lastAttemptDate,
    this.isMastered = false,
    this.isFavorite = false,
    this.categoryIds = const [],
    this.tags = const [],
    this.nextReviewDate,
  });

  factory ExamQuestion.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    if (rawData == null || rawData is! Map) {
      throw FormatException("Document ${doc.id} contains invalid or null data");
    }
    final Map<dynamic, dynamic> data = rawData;
    
    // 安全地轉換 List<String> 類型，防止欄位為 null 或內含非 String 元素時崩潰
    List<String> parseStringList(dynamic field) {
      if (field is List) {
        return field.map((e) => e.toString()).toList();
      }
      return [];
    }

    // 安全地轉換 DateTime 類型，防禦 Timestamp、String 或是整數 timestamp 等各種型態
    DateTime? parseDateTime(dynamic field) {
      if (field is Timestamp) return field.toDate();
      if (field is String) return DateTime.tryParse(field);
      if (field is int) return DateTime.fromMillisecondsSinceEpoch(field);
      return null;
    }

    return ExamQuestion(
      id: doc.id,
      year: data['year']?.toString() ?? '',
      subject: data['subject']?.toString() ?? '',
      content: data['content']?.toString() ?? '',
      options: parseStringList(data['options']),
      correctAnswers: _parseAnswers(data['correctAnswers'] ?? data['correctAnswer']),
      userNote: data['userNote']?.toString() ?? '',
      errorCount: int.tryParse(data['errorCount']?.toString() ?? '0') ?? 0,
      correctCount: int.tryParse(data['correctCount']?.toString() ?? '0') ?? 0,
      attemptCount: int.tryParse(data['attemptCount']?.toString() ?? '0') ?? 0,
      lastAttemptDate: parseDateTime(data['lastAttemptDate']),
      isMastered: data['isMastered'] == true,
      isFavorite: data['isFavorite'] == true,
      categoryIds: parseStringList(data['categoryIds']),
      tags: parseStringList(data['tags']),
      nextReviewDate: parseDateTime(data['nextReviewDate']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'year': year,
      'subject': subject,
      'content': content,
      'options': options,
      'correctAnswers': correctAnswers,
      'userNote': userNote,
      'errorCount': errorCount,
      'correctCount': correctCount,
      'attemptCount': attemptCount,
      'lastAttemptDate': lastAttemptDate != null ? Timestamp.fromDate(lastAttemptDate!) : null,
      'isMastered': isMastered,
      'isFavorite': isFavorite,
      'categoryIds': categoryIds,
      'tags': tags,
      'nextReviewDate': nextReviewDate != null ? Timestamp.fromDate(nextReviewDate!) : null,
    };
  }

  static List<int> _parseAnswers(dynamic data) {
    if (data == null) return [0];
    if (data is List) {
      return List<int>.from(data);
    }
    if (data is int) {
      return [data];
    }
    return [0];
  }
}
