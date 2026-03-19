import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../services/firestore_service.dart';
import '../../models/exam_question.dart';
import 'package:intl/intl.dart';

class DashboardTab extends StatefulWidget {
  final List<ExamQuestion> questions;
  
  const DashboardTab({Key? key, required this.questions}) : super(key: key);

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  DateTime? _examDate;
  bool _isLoadingDate = true;

  @override
  void initState() {
    super.initState();
    _loadExamDate();
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
    int doneCount = widget.questions.where((q) => q.attemptCount > 0 || q.isMastered).length;
    int totalCount = widget.questions.length;

    // Calculate Weaknesses by TAG
    Map<String, List<int>> tagStats = {}; // tag: [errors, attempts]
    for (var q in widget.questions) {
      for (var tag in q.tags) {
        if (!tagStats.containsKey(tag)) {
          tagStats[tag] = [0, 0];
        }
        tagStats[tag]![0] += q.errorCount;
        tagStats[tag]![1] += q.attemptCount;
      }
    }

    List<MapEntry<String, double>> tagWeaknessList = tagStats.entries.map((entry) {
      double rate = entry.value[1] > 0 ? (entry.value[0] / entry.value[1]) * 100 : 0.0;
      return MapEntry(entry.key, rate);
    }).where((e) => e.value > 0).toList();
    
    tagWeaknessList.sort((a, b) => b.value.compareTo(a.value));

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
                _buildCountdownCard(),
                const SizedBox(height: 16),
                _buildProgressCard(doneCount, totalCount),
                const SizedBox(height: 16),
                if (tagWeaknessList.isNotEmpty) _buildChartCard(tagWeaknessList),
                const SizedBox(height: 16),
                _buildWeaknessListCard(tagWeaknessList),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownCard() {
    if (_isLoadingDate) return const CupertinoActivityIndicator();

    int? daysLeft;
    if (_examDate != null) {
      daysLeft = _examDate!.difference(DateTime.now()).inDays;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF007AFF),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.blueAccent.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.calendar, color: Colors.white, size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('醫管資訊證照考試', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 4),
                _examDate == null
                    ? const Text('尚未設定考試日期', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))
                    : Text(
                        daysLeft! >= 0 ? '距離考試還有 $daysLeft 天' : '考試已結束',
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
              ],
            ),
          ),
          CupertinoButton(
            padding: EdgeInsets.zero,
            child: const Icon(CupertinoIcons.settings, color: Colors.white),
            onPressed: () {
              // Navigate to Settings or show Picker
              _showDatePicker();
            },
          )
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

  Widget _buildWeaknessListCard(List<MapEntry<String, double>> tagWeaknessList) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('標籤錯誤率詳情', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (tagWeaknessList.isEmpty)
            const Text('尚無錯誤紀錄。', style: TextStyle(color: Color(0xFF8E8E93)))
          else
            ...tagWeaknessList.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text(e.key, style: const TextStyle(fontSize: 15))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFFFF3B30).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                    child: Text('${e.value.toStringAsFixed(1)}%', style: const TextStyle(color: Color(0xFFFF3B30), fontWeight: FontWeight.bold, fontSize: 13)),
                  )
                ],
              ),
            )).toList(),
        ],
      ),
    );
  }
}
