import 'package:cloud_firestore/cloud_firestore.dart';

class QuizSession {
  final String sessionId;
  final DateTime timestamp;
  final int totalQuestions;
  final int wrongCount;
  final List<String> wrongQuestionIds;
  final Map<String, int> userAnswers;

  QuizSession({
    required this.sessionId,
    required this.timestamp,
    required this.totalQuestions,
    required this.wrongCount,
    required this.wrongQuestionIds,
    required this.userAnswers,
  });

  factory QuizSession.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return QuizSession(
      sessionId: doc.id,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalQuestions: data['totalQuestions'] ?? 0,
      wrongCount: data['wrongCount'] ?? 0,
      wrongQuestionIds: List<String>.from(data['wrongQuestionIds'] ?? []),
      userAnswers: Map<String, int>.from(data['userAnswers'] ?? {}),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'timestamp': Timestamp.fromDate(timestamp),
      'totalQuestions': totalQuestions,
      'wrongCount': wrongCount,
      'wrongQuestionIds': wrongQuestionIds,
      'userAnswers': userAnswers,
    };
  }
}
