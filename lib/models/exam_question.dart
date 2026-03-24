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
    Map data = doc.data() as Map<String, dynamic>;
    return ExamQuestion(
      id: doc.id,
      year: data['year'] ?? '',
      subject: data['subject'] ?? '',
      content: data['content'] ?? '',
      options: List<String>.from(data['options'] ?? []),
      correctAnswers: _parseAnswers(data['correctAnswers'] ?? data['correctAnswer']),
      userNote: data['userNote'] ?? '',
      errorCount: data['errorCount'] ?? 0,
      correctCount: data['correctCount'] ?? 0,
      attemptCount: data['attemptCount'] ?? 0,
      lastAttemptDate: (data['lastAttemptDate'] as Timestamp?)?.toDate(),
      isMastered: data['isMastered'] ?? false,
      isFavorite: data['isFavorite'] ?? false,
      categoryIds: List<String>.from(data['categoryIds'] ?? []),
      tags: List<String>.from(data['tags'] ?? []),
      nextReviewDate: (data['nextReviewDate'] as Timestamp?)?.toDate(),
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
