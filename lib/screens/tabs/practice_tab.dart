import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/exam_question.dart';
import '../../providers/app_provider.dart';
import '../quiz_screen.dart';

class PracticeTab extends StatefulWidget {
  const PracticeTab({super.key});

  @override
  State<PracticeTab> createState() => _PracticeTabState();
}

class _PracticeTabState extends State<PracticeTab> {
  bool _includeMastered = false;
  bool _isSpecialTraining = false;

  void _showQuizConfig(BuildContext outerContext, AppProvider appProvider) {
    showCupertinoModalPopup(
      context: outerContext,
      builder: (actionSheetContext) => CupertinoActionSheet(
        title: const Text('選擇測驗題數'),
        message: const Text('系統將隨機挑選符合條件的題目'),
        actions: [
          CupertinoActionSheetAction(
            child: const Text('20 題'),
            onPressed: () => _startQuiz(outerContext, appProvider, 20, actionSheetContext: actionSheetContext),
          ),
          CupertinoActionSheetAction(
            child: const Text('30 題'),
            onPressed: () => _startQuiz(outerContext, appProvider, 30, actionSheetContext: actionSheetContext),
          ),
          CupertinoActionSheetAction(
            child: const Text('50 題'),
            onPressed: () => _startQuiz(outerContext, appProvider, 50, actionSheetContext: actionSheetContext),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          child: const Text('取消'),
          onPressed: () => Navigator.pop(actionSheetContext),
        ),
      ),
    );
  }

  void _startQuiz(BuildContext outerContext, AppProvider appProvider, int? count, {bool isSpecial = false, BuildContext? actionSheetContext}) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    debugPrint('【1. 點擊確認數量】選擇題數: $count, 是否特訓: $isSpecial, 當前登入用戶 userId: $userId');

    if (actionSheetContext != null && actionSheetContext.mounted) {
      debugPrint('關閉 actionSheet');
      Navigator.pop(actionSheetContext);
    }

    try {
      debugPrint('【2. 準備使用傳入的 AppProvider 題庫資料】');
      debugPrint('全域題目 rawQuestions 數量: ${appProvider.questions.length}');
      
      var pool = List<ExamQuestion>.from(appProvider.questions);
      debugPrint('【3. 資料篩選與洗牌】進入組合邏輯，當前初始題庫池大小: ${pool.length}');

      if (isSpecial) {
        pool = pool.where((q) => q.errorCount >= 2).toList();
        debugPrint('篩選常錯題(錯誤次數>=2)後，題庫池大小: ${pool.length}');
      }

      if (!_includeMastered) {
        pool.removeWhere((q) => q.isMastered);
        debugPrint('排除已精通題後，題庫池大小: ${pool.length}');
      }

      pool.shuffle();
      debugPrint('已完成隨機洗牌');
      
      if (!isSpecial) {
        // Prioritize questions with higher error count or never attempted for normal mode
        pool.sort((a, b) {
          int aPriority = (a.errorCount > 0 || a.lastAttemptDate == null) ? 1 : 0;
          int bPriority = (b.errorCount > 0 || b.lastAttemptDate == null) ? 1 : 0;
          return bPriority.compareTo(aPriority);
        });
        if (count != null) {
          pool = pool.take(count).toList();
          debugPrint('限制取前 $count 題後，題庫池大小: ${pool.length}');
        }
      }

      if (pool.isNotEmpty) {
        debugPrint('【4. 頁面跳轉】準備跳轉至測驗進行頁 QuizScreen，題目數: ${pool.length}');
        if (!outerContext.mounted) {
          debugPrint('【警告】outerContext 已失效，無法跳轉！');
          return;
        }
        Navigator.push(
          outerContext,
          CupertinoPageRoute(
            builder: (context) => QuizScreen(
              questions: pool,
              isSpecialTraining: isSpecial,
            ),
          ),
        );
      } else {
        debugPrint('沒有符合條件的題目，顯示警告');
        if (!outerContext.mounted) return;
        _showAlert(outerContext, '目前無題目', isSpecial ? '尚未累積常錯題目，或已全部精通。' : '目前沒有符合條件的題目可以作答。');
      }
    } catch (e, stackTrace) {
      debugPrint('【測驗初始化失敗】: $e \n 堆疊追蹤: $stackTrace');
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
    final appProvider = context.watch<AppProvider>();
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
                    '系統將優先為您挑選尚未精通或常錯的題目。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Color(0xFF8E8E93)),
                  ),
                  const SizedBox(height: 48),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        CupertinoListTile(
                          title: const Text('包含已精通題目'),
                          subtitle: const Text('全真模擬模式'),
                          trailing: CupertinoSwitch(
                            value: _includeMastered,
                            onChanged: (val) => setState(() => _includeMastered = val),
                          ),
                        ),
                        const Divider(height: 1, indent: 16),
                        CupertinoListTile(
                          title: const Text('常錯題目特訓'),
                          subtitle: const Text('針對錯誤 2 次以上題目'),
                          trailing: CupertinoSwitch(
                            value: _isSpecialTraining,
                            onChanged: (val) => setState(() => _isSpecialTraining = val),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      onPressed: () {
                        if (_isSpecialTraining) {
                          _startQuiz(context, appProvider, null, isSpecial: true);
                        } else {
                          _showQuizConfig(context, appProvider);
                        }
                      },
                      child: Text(_isSpecialTraining ? '開始特訓' : '開始測驗', style: const TextStyle(fontWeight: FontWeight.bold)),
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
