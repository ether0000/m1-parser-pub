import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../models/exam_question.dart';
import '../../models/quiz_session.dart';
import '../../services/firestore_service.dart';
import '../../providers/app_provider.dart';

/// 題庫與筆記 Tab
/// 
/// 展示測驗歷史紀錄、常錯題目摘要，以及以網格形式展示所有題庫的作答狀態。
/// 支援動態搜尋題幹、筆記與 ID 編號。
/// 
/// 這裡繼承自 [StatefulWidget] 並混入 [SingleTickerProviderStateMixin]，
/// 以便託管 [TabController] 實現 iOS 風格的三頁式滑動切換。
class NotesTab extends StatefulWidget {
  final int initialSubTabIndex;

  const NotesTab({
    super.key, 
    this.initialSubTabIndex = 0,
  });

  @override
  State<NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<NotesTab> with SingleTickerProviderStateMixin {
  // 記錄哪些測驗歷史紀錄卡片正被點擊展開，以顯示錯題明細
  final Set<String> _expandedSessions = {};
  
  // 當前搜尋輸入框的關鍵字
  String _searchQuery = '';
  
  // 搜尋框的控制器，我們會在 dispose 中釋放它以避免資源洩漏
  final TextEditingController _searchController = TextEditingController();
  
  // 控制「紀錄」、「常錯」、「總覽」三個 Tab 的 Controller
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // 在initState 初始化 TabController。vsync 使用 this 可優化動畫渲染，防範 widget 處於背景時的無效渲染
    _tabController = TabController(
      length: 3, 
      vsync: this, 
      initialIndex: widget.initialSubTabIndex,
    );
  }

  @override
  void didUpdateWidget(NotesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 當父元件傳入的初始子 Tab 索引改變時（例如點選快捷入口），驅動 Tab 轉場動畫
    if (widget.initialSubTabIndex != oldWidget.initialSubTabIndex) {
      _tabController.animateTo(widget.initialSubTabIndex);
    }
  }

  /// 釋放控制器資源
  /// 
  /// 當 Widget Tree 銷毀此頁面時，必須手動呼叫 dispose，
  /// 否則 TabController 與 TextEditingController 會繼續留在記憶體中，造成嚴重的資源洩漏。
  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final allQuestions = appProvider.questions;
    
    // 依關鍵字模糊搜尋題目內容、筆記或 ID
    final filteredQuestions = allQuestions.where((q) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return q.content.toLowerCase().contains(query) || 
             q.userNote.toLowerCase().contains(query) ||
             q.id.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text('題庫與筆記'),
            backgroundColor: Color(0xFFF2F2F7),
            border: null,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: CupertinoSearchTextField(
                controller: _searchController,
                placeholder: '搜尋題目內容、筆記或編號...',
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyTabBarDelegate(
              child: Container(
                color: const Color(0xFFF2F2F7),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: false,
                  labelColor: const Color(0xFF007AFF),
                  unselectedLabelColor: const Color(0xFF8E8E93),
                  indicatorColor: const Color(0xFF007AFF),
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: const [
                    Tab(text: '紀錄'),
                    Tab(text: '常錯'),
                    Tab(text: '總覽'),
                  ],
                ),
              ),
            ),
          ),
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSessionHistoryTab(appProvider),
                _buildFrequentErrorTab(filteredQuestions),
                _buildBankOverviewTab(filteredQuestions),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Tab 1: 測驗歷史紀錄 ---
  Widget _buildSessionHistoryTab(AppProvider appProvider) {
    final sessions = appProvider.sessions;
    if (sessions.isEmpty) {
      return const Center(child: Text('尚無測驗紀錄', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sessions.length,
      itemBuilder: (context, index) => _buildSessionCard(sessions[index]),
    );
  }

  // --- Tab 2: 常錯題目清單 ---
  Widget _buildFrequentErrorTab(List<ExamQuestion> questions) {
    final freqErrors = questions.where((q) => q.errorCount >= 2 && !q.isMastered).toList();
    freqErrors.sort((a, b) => b.errorCount.compareTo(a.errorCount));

    if (freqErrors.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.checkmark_seal, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text('目前沒有常錯題目，太棒了！', style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: freqErrors.length,
      itemBuilder: (context, index) => _buildFrequentErrorItem(freqErrors[index]),
    );
  }

  // --- Tab 3: 題庫答題狀態總覽 ---
  Widget _buildBankOverviewTab(List<ExamQuestion> questions) {
    Map<String, List<ExamQuestion>> groupedByYear = {};
    for (var q in questions) {
      groupedByYear.putIfAbsent(q.year, () => []).add(q);
    }

    final sortedYears = groupedByYear.keys.toList()..sort((a, b) => b.compareTo(a));

    if (sortedYears.isEmpty) {
      return const Center(child: Text('查無相符題目', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedYears.length,
      itemBuilder: (context, index) {
        final year = sortedYears[index];
        final yearQuestions = groupedByYear[year]!;
        
        yearQuestions.sort((a, b) => a.questionNumber.compareTo(b.questionNumber));
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: ExpansionTile(
            title: Text('$year 年題庫', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('共 ${yearQuestions.length} 題', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: yearQuestions.length,
                  itemBuilder: (context, qIndex) {
                    final q = yearQuestions[qIndex];
                    int qNum = q.questionNumber;
                    Color bgColor;
                    Color textColor = Colors.white;

                    if (q.isMastered) {
                      bgColor = Colors.green;
                    } else if (q.errorCount > 0) {
                      bgColor = Colors.redAccent;
                    } else if (q.attemptCount > 0) {
                      bgColor = Colors.blueAccent;
                    } else {
                      bgColor = Colors.grey.shade200;
                      textColor = Colors.black54;
                    }

                    return InkWell(
                      onTap: () => _showQuestionDetailSheet(q),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          qNum > 0 ? '$qNum' : '${qIndex + 1}',
                          style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _buildLegend(),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendItem(Colors.blueAccent, '已答'),
          const SizedBox(width: 12),
          _legendItem(Colors.redAccent, '錯誤'),
          const SizedBox(width: 12),
          _legendItem(Colors.green, '精熟'),
          const SizedBox(width: 12),
          _legendItem(Colors.grey.shade200, '未答', textColor: Colors.black54),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label, {Color textColor = Colors.white}) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  // --- Helper UI 構建 ---

  Widget _buildSessionCard(QuizSession session) {
    final bool isExpanded = _expandedSessions.contains(session.sessionId);
    final String dateString = DateFormat('yyyy/MM/dd HH:mm').format(session.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => setState(() => isExpanded ? _expandedSessions.remove(session.sessionId) : _expandedSessions.add(session.sessionId)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$dateString 測驗', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const SizedBox(height: 4),
                        Text('答對 ${session.totalQuestions - session.wrongCount}/${session.totalQuestions} 題', 
                           style: TextStyle(fontSize: 13, color: session.wrongCount > 0 ? Colors.redAccent : Colors.green)),
                      ],
                    ),
                  ),
                  Icon(isExpanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down, size: 18, color: Colors.grey),
                  const SizedBox(width: 12),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero, // 解決新版 Flutter 中 minSize 被棄用問題
                    onPressed: () => _confirmDeleteSession(session.sessionId),
                    child: const Icon(CupertinoIcons.trash, color: Colors.redAccent, size: 20),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) _buildWrongQuestionsList(session.wrongQuestionIds),
        ],
      ),
    );
  }

  Widget _buildWrongQuestionsList(List<String> wrongIds) {
    if (wrongIds.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: Text('（無錯誤題目）', style: TextStyle(fontSize: 13, color: Colors.grey)),
      );
    }
    
    return Consumer<AppProvider>(
      builder: (context, appProvider, child) {
        final List<ExamQuestion> wrongQuestions = [];
        for (final id in wrongIds) {
          try {
            final q = appProvider.questions.firstWhere((element) => element.id == id);
            wrongQuestions.add(q);
          } catch (e) {
            // 忽略已被刪除的題目
          }
        }
        
        return Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF2F2F7)))),
          child: Column(
            children: wrongQuestions.map((q) => _buildSimpleQuestionTile(q)).toList(),
          ),
        );
      },
    );
  }

  Widget _buildSimpleQuestionTile(ExamQuestion q) {
    int qNum = q.questionNumber;
    return ListTile(
      dense: true,
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
        child: Text(qNum > 0 ? '#$qNum' : '#--', style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
      ),
      title: Text(q.content, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
      trailing: const Icon(CupertinoIcons.chevron_right, size: 14),
      onTap: () => _showQuestionDetailSheet(q),
    );
  }

  Widget _buildFrequentErrorItem(ExamQuestion q) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('錯 ${q.errorCount} 次', style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(q.subject, style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold))),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(q.content, style: const TextStyle(fontSize: 15, color: Colors.black87)),
            if (q.userNote.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildNotesDisplay(q.userNote),
            ],
          ],
        ),
        onTap: () => _showQuestionDetailSheet(q),
      ),
    );
  }

  Widget _buildNotesDisplay(String note) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Text(note, style: const TextStyle(fontSize: 13, color: Color(0xFF0C4A6E))),
    );
  }

  /// 彈出詳情與筆記修改視窗，將 Sheet 內容封裝至獨立的 [_QuestionDetailSheet] 確保 noteController 被妥善銷毀
  void _showQuestionDetailSheet(ExamQuestion q) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _QuestionDetailSheet(
        question: q,
        firestoreService: Provider.of<FirestoreService>(context, listen: false),
        onSaved: () => setState(() {}),
      ),
    );
  }

  void _confirmDeleteSession(String sessionId) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('確認報廢此紀錄？'),
        content: const Text('刪除後將無法恢復，且會從作答數據中扣除。'),
        actions: [
          CupertinoDialogAction(child: const Text('取消'), onPressed: () => Navigator.pop(context)),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('確認刪除'),
            onPressed: () async {
              Navigator.pop(context);
              final service = Provider.of<FirestoreService>(context, listen: false);
              await service.deleteQuizSession(sessionId);
            },
          ),
        ],
      ),
    );
  }
}

/// 題目詳情與筆記編輯面板
/// 
/// 【設計考量】
/// 為了防止記憶體溢出（Memory Leak），此面板被抽離為獨立的 [StatefulWidget]。
/// 若直接在 `showModalBottomSheet` 的 builder 中創建 `TextEditingController`，
/// 當使用者透過下拉手勢隨機關閉 Sheet 時，該控制器將無法被監聽並釋放。
/// 透過封裝成 `StatefulWidget`，我們能藉由 State 的生命週期 [dispose] 100% 確保編輯控制器被銷毀。
class _QuestionDetailSheet extends StatefulWidget {
  final ExamQuestion question;
  final FirestoreService firestoreService;
  final VoidCallback onSaved;

  const _QuestionDetailSheet({
    required this.question,
    required this.firestoreService,
    required this.onSaved,
  });

  @override
  State<_QuestionDetailSheet> createState() => _QuestionDetailSheetState();
}

class _QuestionDetailSheetState extends State<_QuestionDetailSheet> {
  late TextEditingController _noteController;
  late bool _isMastered;
  
  // 阻斷標記：防止用戶在網速慢時重複點擊「儲存」按鈕造成多重異步請求
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.question.userNote);
    _isMastered = widget.question.isMastered;
  }

  /// 當底部的 Sheet 被關閉（不論是按儲存或是手勢下拉關閉）時，
  /// Flutter 會銷毀此 State 並調用 dispose，在此釋放控制器以消除記憶體洩漏隱患。
  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  /// 執行異步儲存筆記至雲端資料庫
  /// 
  /// 包含三層安全機制：
  /// 1. 儲存中狀態阻斷防止重入。
  /// 2. try-catch 處理可能發生的網路異常，並採用 iOS 對話框進行友善提示。
  /// 3. 若寫入成功，除了同步雲端，亦同步更新本地的 question 實例欄位，
  ///    最後調用 `onSaved` 回呼通知父元件重新渲染 UI，最後關閉 sheet。
  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    
    final navigator = Navigator.of(context);
    try {
      await widget.firestoreService.updateQuestionNote(widget.question.id, _noteController.text.trim());
      // 同步本地快取資料，確保 UI 立刻呈現最新結果而無須重新向伺服器拉取
      widget.question.userNote = _noteController.text.trim();
      widget.question.isMastered = _isMastered;
      
      widget.onSaved();
      navigator.pop();
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (c) => CupertinoAlertDialog(
            title: const Text('儲存失敗'),
            content: Text('$e'),
            actions: [
              CupertinoDialogAction(
                child: const Text('確定'),
                onPressed: () => Navigator.pop(c),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final qNum = q.questionNumber;
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFFF2F2F7),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    const Icon(CupertinoIcons.doc_text, size: 18, color: Colors.blueAccent),
                    const SizedBox(width: 8),
                    Text(q.subject, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                    if (qNum > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('${q.year} 年 第 $qNum 題', style: const TextStyle(fontSize: 11, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                      ),
                    ],
                    const Spacer(),
                    Text('ID: ${q.id}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 16),
                Text(q.content, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                ...List.generate(q.options.length, (index) {
                  bool isCorrect = q.correctAnswers.contains(index);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isCorrect ? Colors.green.withValues(alpha: 0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isCorrect ? Colors.green : Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: isCorrect ? Colors.green : Colors.grey.shade200,
                          child: Text(
                            String.fromCharCode(65 + index),
                            style: TextStyle(fontSize: 12, color: isCorrect ? Colors.white : Colors.black54),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            q.options[index],
                            style: TextStyle(color: isCorrect ? Colors.green.shade900 : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 24),
                const Text('我的筆記', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: _noteController,
                  maxLines: 5,
                  placeholder: '在此紀錄您的學習心得與口訣...',
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('標記為精熟', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    CupertinoSwitch(
                      value: _isMastered,
                      onChanged: (val) async {
                        setState(() => _isMastered = val);
                        q.isMastered = val;
                        await widget.firestoreService.updateQuestion(q);
                        widget.onSaved();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
            color: Colors.white,
            child: SizedBox(
              width: double.infinity,
              child: _isSaving
                  ? const CupertinoActivityIndicator()
                  : CupertinoButton.filled(
                      onPressed: _save,
                      child: const Text('儲存修改內容', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _StickyTabBarDelegate({required this.child});
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => child;
  @override
  double get maxExtent => 48.0;
  @override
  double get minExtent => 48.0;
  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => false;
}
