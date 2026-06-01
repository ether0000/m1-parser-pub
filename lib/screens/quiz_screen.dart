import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../models/exam_question.dart';
import '../providers/quiz_provider.dart';
import '../services/firestore_service.dart';
import '../utils/animated_background.dart';
import '../utils/glassmorphism.dart';
import 'review_screen.dart';

/// 測驗練習畫面
/// 
/// 展示題目與選項，並使用 [QuizProvider] (結合 [ChangeNotifier]) 來管理當前答題進度、答案判定與星星標記。
/// 測驗結束後將會載入 [ReviewScreen] 以便總結與檢討。
class QuizScreen extends StatelessWidget {
  final List<ExamQuestion> questions;
  final bool isSpecialTraining;

  const QuizScreen({
    super.key, 
    required this.questions, 
    this.isSpecialTraining = false,
  });

  /// 顯示本次測驗或特訓總結的對話框
  void _showSummaryDialog(BuildContext context, QuizProvider quiz) {
    int answeredCount = quiz.userAnswers.length;
    int correctCount = 0;
    quiz.userAnswers.forEach((qId, ansIdx) {
      final q = questions.firstWhere((element) => element.id == qId);
      if (q.correctAnswers.contains(ansIdx)) {
        correctCount++;
      }
    });
    double accuracy = answeredCount > 0 ? (correctCount / answeredCount) * 100 : 0;

    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('特訓結束'),
        content: Text('本次特訓共複習了 $answeredCount 題\n正確率：${accuracy.toStringAsFixed(1)}%'),
        actions: [
          CupertinoDialogAction(
            child: const Text('確定'),
            onPressed: () {
              Navigator.pop(context); // 關閉對話框
              Navigator.pop(context); // 退出 QuizScreen 畫面
            },
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => QuizProvider(
        service: Provider.of<FirestoreService>(context, listen: false),
        questions: questions,
        isSpecialTraining: isSpecialTraining,
      ),
      child: Consumer<QuizProvider>(
        builder: (context, quiz, _) {
          if (quiz.isFinished) {
            return ReviewScreen(wrongQuestions: quiz.wrongQuestions);
          }

          final currentQ = quiz.currentQuestion;
          final qNum = currentQ.questionNumber;
          final currentIndex = quiz.currentIndex;

          return Scaffold(
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              title: Column(
                children: [
                  Text(
                    '第 ${currentIndex + 1} 題 / 共 ${questions.length} 題',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  if (qNum > 0)
                    Text(
                      '${currentQ.year} 年 第 $qNum 題',
                      style: const TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                ],
              ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              actions: [
                if (isSpecialTraining)
                  TextButton(
                    onPressed: () => quiz.finishQuiz(() => _showSummaryDialog(context, quiz)),
                    child: const Text('結束特訓', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ),
                IconButton(
                  icon: Icon(
                    currentQ.isFavorite ? Icons.star_rounded : Icons.star_border_rounded, 
                    color: Colors.amber,
                  ),
                  onPressed: quiz.toggleFavorite,
                )
              ],
            ),
            body: AnimatedGradientBackground(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GlassContainer(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  currentQ.content,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                                ),
                              ),
                              const SizedBox(height: 20),
                              ...List.generate(currentQ.options.length, (index) {
                                Color bgColor = Colors.black.withValues(alpha: 0.05);
                                Icon? trailingIcon;
                                Color textColor = Colors.black87;

                                if (quiz.hasAnsweredCurrent) {
                                  if (currentQ.correctAnswers.contains(index)) {
                                    bgColor = Colors.green.withValues(alpha: 0.2);
                                    textColor = Colors.green.shade900;
                                    if (index == quiz.selectedOption) {
                                      trailingIcon = const Icon(Icons.check_circle_rounded, color: Colors.green);
                                    }
                                  } else if (index == quiz.selectedOption) {
                                    bgColor = Colors.redAccent.withValues(alpha: 0.2);
                                    textColor = Colors.redAccent.shade700;
                                    trailingIcon = const Icon(Icons.cancel_rounded, color: Colors.redAccent);
                                  }
                                }

                                final List<String> labels = ['A', 'B', 'C', 'D'];
                                final String label = index < labels.length ? labels[index] : '';

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: InkWell(
                                    onTap: quiz.hasAnsweredCurrent ? null : () => quiz.submitAnswer(index),
                                    borderRadius: BorderRadius.circular(16),
                                    child: GlassContainer(
                                      padding: const EdgeInsets.all(16),
                                      color: bgColor,
                                      borderRadius: BorderRadius.circular(16),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 30,
                                            height: 30,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.black.withValues(alpha: 0.05),
                                            ),
                                            child: Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(currentQ.options[index], style: TextStyle(fontSize: 16, color: textColor)),
                                          ),
                                          // ignore: use_null_aware_elements
                                          if (trailingIcon != null) trailingIcon,
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }), // 移除多餘的 toList()
                            ],
                          ),
                        ),
                      ),
                      if (quiz.hasAnsweredCurrent)
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: ElevatedButton(
                            onPressed: () => quiz.nextQuestion(() => _showSummaryDialog(context, quiz)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text('下一題', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
