import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../services/firestore_service.dart';
import '../../models/exam_question.dart';

import '../../providers/app_provider.dart';
import '../quiz_screen.dart';

/// 學習看板 Tab
/// 
/// 採用 [StatefulWidget] 維護本地的倒數日期的快取加載、常錯隨機抽測題目狀態。
/// 透過 [context.watch<AppProvider>] 響應全域的學習進度數據。
class DashboardTab extends StatefulWidget {
  final Function(int, {int initialSubTabIndex})? onNavigate;
  
  const DashboardTab({
    super.key, 
    this.onNavigate,
  });

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  DateTime? _examDate;
  bool _isLoadingDate = true;
  ExamQuestion? _randomFrequentError;
  bool _showAnswer = false;

  @override
  void initState() {
    super.initState();
    _loadExamDate();
  }

  /// 透過 didChangeDependencies 響應全域 AppProvider 數據變化
  /// 
  /// 當 AppProvider 資料更新時（例如使用者剛完成測驗、錯題數變動），此方法會被觸發。
  /// 我們在此更新局部狀態（如常錯隨機抽測題目），因為這是在 build 之前執行的生命週期，
  /// 直接修改變數後續會直接套用到 build 中，故不需也不應在此呼叫 `setState()`，可避免多餘的重繪。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    final appProvider = Provider.of<AppProvider>(context);
    final freqErrors = appProvider.frequentErrors;
    
    if (freqErrors.isEmpty) {
      if (_randomFrequentError != null) {
        _randomFrequentError = null;
        _showAnswer = false;
      }
    } else {
      // 若當前無隨機題，或目前的隨機題已經不在常錯清單內，則重新抽取一題
      if (_randomFrequentError == null || !freqErrors.any((q) => q.id == _randomFrequentError!.id)) {
        _randomFrequentError = (List<ExamQuestion>.from(freqErrors)..shuffle()).first;
        _showAnswer = false;
      }
    }
  }

  /// 隨機抽取一道常錯題目以供碎型學習
  /// 
  /// 用於看板的「常錯隨機抽測」小卡片。使用者在掌握一題後，可點選「換一題」按鈕，
  /// 這會觸發 `setState()`，讓 UI 重新綁定並渲染新的題目與未顯示答案狀態。
  void _pickRandomFrequentError() {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final freqErrors = appProvider.frequentErrors;
    if (freqErrors.isNotEmpty) {
      setState(() {
        _randomFrequentError = (List<ExamQuestion>.from(freqErrors)..shuffle()).first;
        _showAnswer = false;
      });
    } else {
      if (_randomFrequentError != null) {
        setState(() {
          _randomFrequentError = null;
          _showAnswer = false;
        });
      }
    }
  }

  /// 載入考試日期，實作「快取優先 (SharedPreferences)」並從 Firestore 同步的複合策略
  /// 
  /// 為了提供無縫的體驗，此處先載入本地的快取數據（如果有），讓 UI 瞬間渲染出來，
  /// 隨後發起雲端非同步請求取得最新日期。同時在更新 UI 時加入「內容變更檢查」，
  /// 避免在資料無變動的情況下觸發多餘的 `setState()`，減少 Flutter widget tree 的重構次數。
  Future<void> _loadExamDate() async {
    final service = Provider.of<FirestoreService>(context, listen: false);
    final prefs = await SharedPreferences.getInstance();
    final localDateStr = prefs.getString('examDate');
    
    DateTime? localDate;
    if (localDateStr != null) {
      localDate = DateTime.tryParse(localDateStr);
    }

    if (mounted && localDate != null) {
      setState(() {
        _examDate = localDate;
        _isLoadingDate = false;
      });
    }

    try {
      final remoteDate = await service.fetchExamDate();
      
      if (remoteDate != null && mounted) {
        // 唯有當前為 null、或與雲端日期不同，或尚未載入完成時，才進行 setState
        if (_examDate == null || !_examDate!.isAtSameMomentAs(remoteDate) || _isLoadingDate) {
          setState(() {
            _examDate = remoteDate;
            _isLoadingDate = false;
          });
        }
        await prefs.setString('examDate', remoteDate.toIso8601String());
      } else if (mounted) {
        if (_isLoadingDate) {
          setState(() => _isLoadingDate = false);
        }
      }
    } catch (e) {
      // 發生異常（如離線）時，若仍處於讀取狀態則更新讀取旗標
      if (mounted && _isLoadingDate) {
        setState(() => _isLoadingDate = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final questions = appProvider.questions;
    int doneCount = appProvider.totalAttempted;
    int totalCount = questions.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text('學習看板'),
            backgroundColor: Color(0xFFF2F2F7),
            border: null,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildCountdownCard(appProvider),
                const SizedBox(height: 16),
                _buildDailyQuestsCard(appProvider),
                const SizedBox(height: 16),
                if (appProvider.scheduledReviews.isNotEmpty) ...[
                  _buildScheduledReviewSection(appProvider),
                  const SizedBox(height: 16),
                ],
                if (_randomFrequentError != null) ...[
                  _buildRandomFrequentErrorCard(),
                  const SizedBox(height: 16),
                ],
                _buildFrequentErrorStatsCard(appProvider.frequentErrors.length),
                const SizedBox(height: 16),
                _buildProgressCard(doneCount, totalCount),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// 倒數計時與學習天數卡片
  Widget _buildCountdownCard(AppProvider appProvider) {
    if (_isLoadingDate) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: CupertinoActivityIndicator(),
        ),
      );
    }

    int? daysLeft;
    if (_examDate != null) {
      daysLeft = _examDate!.difference(DateTime.now()).inDays;
    }

    final streak = appProvider.userStats.loginStreak;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF007AFF), Color(0xFF5AC8FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF007AFF).withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.calendar, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('網管/醫管證照考試', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 2),
                    _examDate == null
                        ? const Text('尚未設定日期', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
                        : Text(
                            daysLeft! >= 0 ? '倒數 $daysLeft 天' : '考試已結束',
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                  ],
                ),
              ),
              if (streak > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.local_fire_department, color: Colors.orange, size: 18),
                      const SizedBox(width: 4),
                      Text('$streak', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _showDatePicker,
                child: const Icon(CupertinoIcons.settings, color: Colors.white, size: 20),
              )
            ],
          ),
          if (_examDate != null && daysLeft! >= 0) ...[
            const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(color: Colors.white24, height: 1)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('每日建議進度', style: TextStyle(color: Colors.white70, fontSize: 14)),
                Text('${appProvider.dailyQuota} 題 / 天', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ]
        ],
      ),
    );
  }

  /// 彈出 iOS 風格之考期日期選擇器
  /// 
  /// 在對話框中調用 `CupertinoDatePicker` 的 `onDateTimeChanged` 時，會觸發局部 `setState()` 讓看板上的倒數文字即時刷新。
  /// 點選「儲存日期」按鈕時，會發起非同步網路寫入，同步更新 Firestore 設定以及 SharedPreferences 本地快取，
  /// 更新完成後呼叫 `Navigator.pop` 關閉彈出視窗，流程清晰且無洩漏風險。
  void _showDatePicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => Container(
        height: 300,
        color: Colors.white,
        child: Column(
          children: [
            SizedBox(
              height: 200,
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: _examDate ?? DateTime.now().add(const Duration(days: 30)),
                onDateTimeChanged: (DateTime newDate) {
                  setState(() => _examDate = newDate);
                },
              ),
            ),
            CupertinoButton(
              child: const Text('儲存日期'),
              onPressed: () async {
                if (_examDate == null) return;
                
                final service = Provider.of<FirestoreService>(context, listen: false);
                await service.saveExamDate(_examDate!);
                
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('examDate', _examDate!.toIso8601String());
                
                if (context.mounted) Navigator.pop(context);
              },
            )
          ],
        ),
      ),
    );
  }

  /// 學習進度條卡片
  Widget _buildProgressCard(int doneCount, int totalCount) {
    double progress = totalCount > 0 ? doneCount / totalCount : 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(CupertinoIcons.graph_circle, color: Color(0xFF007AFF)),
              SizedBox(width: 8),
              Text('作答進度', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black)),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: const Color(0xFFF2F2F7),
              color: const Color(0xFF34C759),
            ),
          ),
          const SizedBox(height: 8),
          Text('目前進度：${(progress * 100).toStringAsFixed(1)}% ($doneCount / $totalCount 題)',
              style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
          const Text('包含已作答或已標記精通之題目', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 11)),
        ],
      ),
    );
  }

  /// 碎型複習卡片：展示一個常錯的題目
  Widget _buildRandomFrequentErrorCard() {
    final q = _randomFrequentError!;
    return GestureDetector(
      onTap: () => setState(() => _showAnswer = !_showAnswer),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(CupertinoIcons.lightbulb_fill, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                const Text('碎型複習：常錯隨機抽測', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                const Spacer(),
                Text('已錯 ${q.errorCount} 次', style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              q.content,
              style: const TextStyle(fontSize: 16, color: Colors.black87, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...List.generate(q.options.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${index + 1}. ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    Expanded(child: Text(q.options[index], style: const TextStyle(fontSize: 14))),
                  ],
                ),
              );
            }),
            if (_showAnswer) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              const Text('正確答案：', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(height: 4),
              Text(
                q.correctAnswers.map((idx) => q.options[idx]).join(' / '),
                style: const TextStyle(fontSize: 15, color: Colors.black87),
              ),
              if (q.userNote.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('我的筆記：', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                const SizedBox(height: 4),
                Text(q.userNote, style: const TextStyle(fontSize: 14, color: Colors.black54)),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _pickRandomFrequentError,
                  child: const Text('換一題'),
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              const Center(
                child: Text('點擊卡片顯示解析', style: TextStyle(fontSize: 13, color: Colors.grey)),
              ),
            ]
          ],
        ),
      ),
    );
  }

  /// 常錯題目特訓引導按鈕
  Widget _buildFrequentErrorStatsCard(int freqErrorCount) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('精確打擊', style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 4),
                Text('目前累積 $freqErrorCount 題常錯題', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => widget.onNavigate?.call(1),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B30),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
            child: const Text('展開特訓'),
          ),
        ],
      ),
    );
  }

  /// 每日進度委託任務
  Widget _buildDailyQuestsCard(AppProvider appProvider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(CupertinoIcons.star_fill, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text('每日委託', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          _buildQuestItem('今日完成 20 題測驗', appProvider.quest1Progress, '${appProvider.userStats.dailyQuestionsDone}/20'),
          const SizedBox(height: 12),
          _buildQuestItem('消滅 5 道常錯題', appProvider.quest2Progress, '${appProvider.userStats.dailyErrorsCleared}/5'),
        ],
      ),
    );
  }

  Widget _buildQuestItem(String title, double progress, String label) {
    bool isDone = progress >= 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: TextStyle(fontSize: 14, color: isDone ? Colors.green : Colors.black87, fontWeight: isDone ? FontWeight.bold : FontWeight.normal)),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: const Color(0xFFF2F2F7),
            color: isDone ? const Color(0xFF34C759) : const Color(0xFF007AFF),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  /// 今日排程複習（基於間隔重複演算法計算出的推薦複習清單）
  Widget _buildScheduledReviewSection(AppProvider appProvider) {
    final reviews = appProvider.scheduledReviews;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(CupertinoIcons.timer, color: Colors.orange),
              const SizedBox(width: 8),
              const Text('今日待複習', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.brown)),
              const Spacer(),
              Text('${reviews.length} 題', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
            ],
          ),
          const SizedBox(height: 8),
          const Text('根據記憶遺忘曲線，系統已為您排程今日需強化的題目。', style: TextStyle(fontSize: 13, color: Colors.brown)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              color: Colors.orange,
              padding: const EdgeInsets.symmetric(vertical: 8),
              borderRadius: BorderRadius.circular(12),
              onPressed: () {
                Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (context) => QuizScreen(
                      questions: reviews,
                      isSpecialTraining: true,
                    ),
                  ),
                );
              },
              child: const Text('立即複習', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
}
