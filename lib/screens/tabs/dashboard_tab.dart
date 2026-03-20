import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../services/firestore_service.dart';
import '../../models/exam_question.dart';
import 'package:intl/intl.dart';

import '../../providers/app_provider.dart';
import '../quiz_screen.dart';

class DashboardTab extends StatefulWidget {
  final Function(int, {int initialSubTabIndex})? onNavigate;
  
  const DashboardTab({
    Key? key, 
    this.onNavigate,
  }) : super(key: key);

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickRandomFrequentError());
  }

  void _pickRandomFrequentError() {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    final freqErrors = appProvider.frequentErrors;
    if (freqErrors.isNotEmpty) {
      setState(() {
        // Only pick new if current is null or no longer a frequent error
        if (_randomFrequentError == null || !freqErrors.any((q) => q.id == _randomFrequentError!.id)) {
          _randomFrequentError = (freqErrors..shuffle()).first;
          _showAnswer = false;
        }
      });
    } else {
      if (_randomFrequentError != null) {
        setState(() => _randomFrequentError = null);
      }
    }
  }

  Future<void> _loadExamDate() async {
    // 1. Try local cache first for immediate UI
    final prefs = await SharedPreferences.getInstance();
    final localDateStr = prefs.getString('examDate');
    
    if (mounted && localDateStr != null) {
      setState(() {
        _examDate = DateTime.tryParse(localDateStr);
        _isLoadingDate = false;
      });
    }

    // 2. Fetch from Firestore for cloud sync
    try {
      final service = Provider.of<FirestoreService>(context, listen: false);
      final remoteDate = await service.fetchExamDate();
      
      if (remoteDate != null && mounted) {
        setState(() {
          _examDate = remoteDate;
          _isLoadingDate = false;
        });
        // Sync back to local
        await prefs.setString('examDate', remoteDate.toIso8601String());
      } else if (mounted) {
        setState(() => _isLoadingDate = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingDate = false);
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
      body: Builder(builder: (context) {
        // Check and update random error if needed on every build
        final freqErrors = appProvider.frequentErrors;
        if (freqErrors.isEmpty && _randomFrequentError != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _randomFrequentError = null);
          });
        } else if (freqErrors.isNotEmpty && (_randomFrequentError == null || !freqErrors.any((q) => q.id == _randomFrequentError!.id))) {
           WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _pickRandomFrequentError();
          });
        }

        return CustomScrollView(
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
        );
      }),
    );
  }

  Widget _buildCountdownCard(AppProvider appProvider) {
    if (_isLoadingDate) return const CupertinoActivityIndicator();

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
          BoxShadow(color: Colors.blueAccent.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
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
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
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
                child: const Icon(CupertinoIcons.settings, color: Colors.white, size: 20),
                onPressed: _showDatePicker,
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
                
                // Save to Firestore
                final service = Provider.of<FirestoreService>(context, listen: false);
                await service.saveExamDate(_examDate!);
                
                // Save to Local
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

  Widget _buildChartCard(List<MapEntry<String, double>> topWeaknesses) {
    final displayList = topWeaknesses.take(5).toList();
    
    return Container(
      height: 300,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('弱點分析 (TOP 5 錯誤標籤)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 100,
                barGroups: displayList.asMap().entries.map((e) {
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.value,
                        color: const Color(0xFFFF3B30),
                        width: 16,
                        borderRadius: BorderRadius.circular(4),
                      )
                    ],
                  );
                }).toList(),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= displayList.length) return const Text('');
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            displayList[value.toInt()].key.substring(0, displayList[value.toInt()].key.length.clamp(0, 4)),
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

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
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
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
            onPressed: () => widget.onNavigate?.call(1), // Nav to PracticeTab
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

  Widget _buildScheduledReviewSection(AppProvider appProvider) {
    final reviews = appProvider.scheduledReviews;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
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
                      isSpecialTraining: true, // Use special training UI for reviews
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
