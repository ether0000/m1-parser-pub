import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../models/exam_question.dart';
import '../quiz_screen.dart';

class PracticeTab extends StatefulWidget {
  final List<ExamQuestion> questions;
  
  const PracticeTab({Key? key, required this.questions}) : super(key: key);

  @override
  State<PracticeTab> createState() => _PracticeTabState();
}

class _PracticeTabState extends State<PracticeTab> {
  bool _includeMastered = false;

  void _showQuizConfig(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('選擇測驗題數'),
        message: const Text('系統將隨機挑選符合條件的題目'),
        actions: [
          CupertinoActionSheetAction(
            child: const Text('20 題'),
            onPressed: () => _startQuiz(context, 20),
          ),
          CupertinoActionSheetAction(
            child: const Text('30 題'),
            onPressed: () => _startQuiz(context, 30),
          ),
          CupertinoActionSheetAction(
            child: const Text('50 題'),
            onPressed: () => _startQuiz(context, 50),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          child: const Text('取消'),
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _startQuiz(BuildContext context, int count) {
    Navigator.pop(context); // Close action sheet
    
    var pool = List<ExamQuestion>.from(widget.questions);
    if (!_includeMastered) {
      pool.removeWhere((q) => q.isMastered);
    }

    pool.shuffle();
    // Prioritize questions with higher error count or never attempted
    pool.sort((a, b) {
      int aPriority = (a.errorCount > 0 || a.lastAttemptDate == null) ? 1 : 0;
      int bPriority = (b.errorCount > 0 || b.lastAttemptDate == null) ? 1 : 0;
      return bPriority.compareTo(aPriority);
    });

    final currentQuiz = pool.take(count).toList();
    
    if (currentQuiz.isNotEmpty) {
      Navigator.push(
        context,
        CupertinoPageRoute(
          builder: (context) => QuizScreen(questions: currentQuiz),
        ),
      );
    } else {
      _showAlert(context, '錯誤', '目前沒有符合條件的題目可以作答。');
    }
  }

  void _showAlert(BuildContext context, String title, String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('確定'),
            onPressed: () => Navigator.pop(context),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text('測驗練習'),
            backgroundColor: Color(0xFFF2F2F7),
            border: null,
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(CupertinoIcons.rocket_fill, size: 80, color: Color(0xFF007AFF)),
                  const SizedBox(height: 32),
                  const Text(
                    '準備好開始練習了嗎？',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '系統將為您智慧挑選弱點標籤題目。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Color(0xFF8E8E93)),
                  ),
                  const SizedBox(height: 48),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CupertinoListTile(
                      title: const Text('包含已精通題目'),
                      subtitle: const Text('全真模擬模式'),
                      trailing: CupertinoSwitch(
                        value: _includeMastered,
                        onChanged: (val) => setState(() => _includeMastered = val),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      onPressed: () => _showQuizConfig(context),
                      child: const Text('開始測驗', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
