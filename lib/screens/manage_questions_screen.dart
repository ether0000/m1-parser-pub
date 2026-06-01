import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../models/exam_question.dart';
import '../services/firestore_service.dart';

/// 管理題庫畫面
/// 
/// 【狀態設計說明】
/// 採用原生的 [StatefulWidget] 來維護題庫的搜尋文字、展開/摺疊狀態以及列表渲染。
/// 由於摺疊面板展開（年份大標題）是純 UI 交互狀態，不影響其他 Tab 的數據，
/// 透過 StatefulWidget 局部維護 `_expandedYears` 具有高內聚性，無須將此狀態污染至全域狀態管理。
/// 與 [FirestoreService] 互動，以非同步進行題目的增刪查改操作，並輔以防禦性 try-catch 處理。
class ManageQuestionsScreen extends StatefulWidget {
  const ManageQuestionsScreen({super.key});

  @override
  State<ManageQuestionsScreen> createState() => _ManageQuestionsScreenState();
}

class _ManageQuestionsScreenState extends State<ManageQuestionsScreen> {
  // 快取從 Firestore 取得的所有題目列表
  List<ExamQuestion> _allQuestions = [];
  
  // 經過搜尋框篩選後的題目列表，供 UI 直接使用
  List<ExamQuestion> _filteredQuestions = [];
  bool _isLoading = true;
  
  // 搜尋框的編輯控制器，生命週期結束時需 dispose
  final TextEditingController _searchController = TextEditingController();
  
  // 記錄哪些年份的題庫處於展開狀態
  final Set<String> _expandedYears = {};

  /// 將篩選後的題目依「年份」進行分組，並依年份降序、題號升序排列
  Map<String, List<ExamQuestion>> get _groupedQuestions {
    final Map<String, List<ExamQuestion>> groups = {};
    for (var q in _filteredQuestions) {
      groups.putIfAbsent(q.year, () => []).add(q);
    }
    
    // 年份降序排序
    final sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    
    final Map<String, List<ExamQuestion>> sortedGroups = {};
    for (var k in sortedKeys) {
      final yearList = groups[k]!;
      // 題號升序排序
      yearList.sort((a, b) => a.questionNumber.compareTo(b.questionNumber));
      sortedGroups[k] = yearList;
    }
    
    return sortedGroups;
  }

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  /// 釋放控制器，防範洩漏
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 從 Firestore 載入所有題目資料，並更新本地 State
  Future<void> _loadQuestions() async {
    final service = Provider.of<FirestoreService>(context, listen: false);
    try {
      final questions = await service.getAllQuestionsCached();
      if (mounted) {
        setState(() {
          _allQuestions = questions;
          _filteredQuestions = questions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showAlert('載入失敗', '無法取得題庫資料：$e');
      }
    }
  }

  /// 搜尋篩選邏輯，依據題幹、年份、科目進行模糊比對
  void _filterQuestions(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredQuestions = _allQuestions;
      } else {
        final lowercaseQuery = query.toLowerCase();
        _filteredQuestions = _allQuestions
            .where((q) =>
                q.content.toLowerCase().contains(lowercaseQuery) ||
                q.year.contains(lowercaseQuery) ||
                q.subject.toLowerCase().contains(lowercaseQuery))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: CupertinoNavigationBar(
        middle: const Text('管理題庫'),
        previousPageTitle: '設定',
        trailing: _isLoading ? const CupertinoActivityIndicator() : Text('${_filteredQuestions.length} 題'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: CupertinoSearchTextField(
              controller: _searchController,
              placeholder: '搜尋題目內容、年份或科目...',
              onChanged: _filterQuestions,
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CupertinoActivityIndicator())
                : _buildGroupedList(),
          ),
        ],
      ),
    );
  }

  /// 將分組的題目展平成 ListView 所需的元素列表
  List<_ListElement> get _flattenedElements {
    final List<_ListElement> elements = [];
    final grouped = _groupedQuestions;
    for (var entry in grouped.entries) {
      final year = entry.key;
      final questions = entry.value;
      final isExpanded = _expandedYears.contains(year);
      elements.add(_YearHeaderElement(year, questions.length));
      if (isExpanded) {
        for (var q in questions) {
          elements.add(_QuestionElement(q));
        }
      }
    }
    return elements;
  }

  /// 建立摺疊列表
  Widget _buildGroupedList() {
    final elements = _flattenedElements;
    if (elements.isEmpty) {
      return const Center(child: Text('查無題目', style: TextStyle(color: Color(0xFF8E8E93))));
    }

    return ListView.builder(
      itemCount: elements.length,
      itemBuilder: (context, index) {
        final element = elements[index];
        if (element is _YearHeaderElement) {
          final year = element.year;
          final isExpanded = _expandedYears.contains(year);
          final count = element.count;

          return GestureDetector(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedYears.remove(year);
                } else {
                  _expandedYears.add(year);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: const Color(0xFFE5E5EA),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right,
                    size: 16,
                    color: const Color(0xFF8E8E93),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$year 年',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    child: const Icon(CupertinoIcons.pencil_circle, size: 20, color: Color(0xFF007AFF)),
                    onPressed: () => _showUpdateYearDialog(year),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    child: const Icon(CupertinoIcons.trash_circle, size: 20, color: Color(0xFFFF3B30)),
                    onPressed: () => _confirmDeleteByYear(year),
                  ),
                  const Spacer(),
                  Text(
                    '$count 題',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                  ),
                ],
              ),
            ),
          );
        } else if (element is _QuestionElement) {
          return _buildQuestionTile(element.question);
        }
        return const SizedBox.shrink();
      },
    );
  }

  /// 建立單一題目的 Card UI
  Widget _buildQuestionTile(ExamQuestion q) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _editQuestion(q),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(q.year, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      q.subject,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF007AFF)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                q.content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, color: Colors.black),
              ),
              const SizedBox(height: 8),
              Text(
                '答案: ${q.correctAnswers.map((idx) => q.options[idx]).join(' / ')}',
                style: const TextStyle(fontSize: 13, color: CupertinoColors.systemGreen),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 彈出編輯題目視窗，將編輯表單封裝至 [_EditQuestionDialog] 確保 Controller 生命週期結束時被妥善銷毀
  void _editQuestion(ExamQuestion q) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => _EditQuestionDialog(
        question: q,
        firestoreService: Provider.of<FirestoreService>(context, listen: false),
        onSaved: (updatedQ) {
          setState(() {
            int idx = _allQuestions.indexWhere((element) => element.id == q.id);
            if (idx != -1) _allQuestions[idx] = updatedQ;
            _filterQuestions(_searchController.text);
          });
        },
      ),
    );
  }

  /// 確認並刪除指定年份的所有題目
  void _confirmDeleteByYear(String year) {
    final navigator = Navigator.of(context);
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('確認刪除 $year 年題庫？'),
        content: const Text('此操作將刪除該年份所有題目，且無法復原。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => navigator.pop(),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('確認刪除'),
            onPressed: () async {
              navigator.pop(); // 關閉確認視窗
              _showLoading('正在刪除 $year 年題目...');
              try {
                final service = Provider.of<FirestoreService>(context, listen: false);
                await service.deleteQuestionsByYear(year);
                await _loadQuestions();
                if (mounted) navigator.pop(); // 關閉 Loading 畫面
              } catch (e) {
                if (mounted) {
                  navigator.pop(); // 關閉 Loading 畫面
                  _showAlert('錯誤', '刪除失敗: $e');
                }
              }
            },
          ),
        ],
      ),
    );
  }

  /// 修改指定年份名稱的對話框
  void _showUpdateYearDialog(String oldYear) {
    final controller = TextEditingController(text: oldYear);
    final navigator = Navigator.of(context);
    
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('修改 $oldYear 年份'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: '輸入新年份',
            keyboardType: TextInputType.number,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () {
              controller.dispose();
              navigator.pop();
            },
          ),
          CupertinoDialogAction(
            child: const Text('確認修改'),
            onPressed: () async {
              final newYear = controller.text.trim();
              controller.dispose();
              navigator.pop();
              
              if (newYear.isEmpty || newYear == oldYear) return;
              
              _showLoading('正在批次更新年份...');
              try {
                final service = Provider.of<FirestoreService>(context, listen: false);
                await service.updateQuestionsYear(oldYear, newYear);
                await _loadQuestions();
                if (mounted) navigator.pop(); // 關閉 Loading
              } catch (e) {
                if (mounted) {
                  navigator.pop(); // 關閉 Loading
                  _showAlert('錯誤', '更新失敗: $e');
                }
              }
            },
          ),
        ],
      ),
    );
  }

  /// 顯示不可手動關閉的等待畫面，採用 [PopScope] 取代被廢棄的 `WillPopScope`
  void _showLoading(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false, // 阻止 Android 物理返回鍵
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CupertinoActivityIndicator(radius: 15),
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 16, decoration: TextDecoration.none),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顯示提示訊息對話框
  void _showAlert(String title, String message) {
    showCupertinoDialog(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
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

/// 編輯題目的對話框元件
/// 
/// 【生命週期與資源釋放設計】
/// 由於題目含有多個選項（通常為 4 個），每個選項在編輯時都需要獨立的 [TextEditingController]。
/// 我們將此 Dialog 抽離為專屬的 [StatefulWidget]，其最大好處在於：
/// 能夠在 State 的 `dispose` 生命週期方法中，安全且確實地遍歷 `_optionControllers` 並逐一呼叫 `dispose()`。
/// 如此一來，即使使用者點選對話框外的區域或以系統手勢返回取消，也能保證資源 100% 被垃圾回收，免去 Memory Leak 隱患。
class _EditQuestionDialog extends StatefulWidget {
  final ExamQuestion question;
  final FirestoreService firestoreService;
  final ValueChanged<ExamQuestion> onSaved;

  const _EditQuestionDialog({
    required this.question,
    required this.firestoreService,
    required this.onSaved,
  });

  @override
  State<_EditQuestionDialog> createState() => _EditQuestionDialogState();
}

class _EditQuestionDialogState extends State<_EditQuestionDialog> {
  // 題幹編輯控制器
  late TextEditingController _contentController;
  
  // 動態生成的選項編輯控制器列表
  late List<TextEditingController> _optionControllers;
  
  // 當前選取的正確答案索引清單（支援複選）
  late List<int> _selectedAnswers;
  
  // 阻斷標記，防範網路延遲時重複點擊造成資源浪費
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.question.content);
    _optionControllers = widget.question.options
        .map((opt) => TextEditingController(text: opt))
        .toList();
    _selectedAnswers = List<int>.from(widget.question.correctAnswers);
  }

  /// 徹底回收 dialog 內使用的所有資源
  @override
  void dispose() {
    _contentController.dispose();
    for (var controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 發起異步寫入，更新該題目欄位
  /// 
  /// 邏輯流程：
  /// 1. 整理控制器輸入，移除多餘前後空格。
  /// 2. 呼叫 `firestoreService.updateQuestion` 發起網路更新。
  /// 3. 若成功，透過 `onSaved` 回呼回傳最新的 question 實體供主畫面更新本地快取狀態。
  /// 4. 若失敗，捕獲異常，恢復儲存狀態，並彈出錯誤對話框提示。
  Future<void> _save() async {
    if (_isSaving) return;
    
    setState(() => _isSaving = true);
    
    final updatedQ = ExamQuestion(
      id: widget.question.id,
      year: widget.question.year,
      subject: widget.question.subject,
      content: _contentController.text.trim(),
      options: _optionControllers.map((c) => c.text.trim()).toList(),
      correctAnswers: _selectedAnswers,
      userNote: widget.question.userNote,
      errorCount: widget.question.errorCount,
      correctCount: widget.question.correctCount,
      attemptCount: widget.question.attemptCount,
      lastAttemptDate: widget.question.lastAttemptDate,
      isMastered: widget.question.isMastered,
      isFavorite: widget.question.isFavorite,
    );
    
    final navigator = Navigator.of(context);
    try {
      await widget.firestoreService.updateQuestion(updatedQ);
      widget.onSaved(updatedQ);
      navigator.pop(); // 關閉對話框
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
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Color(0xFFF2F2F7),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          CupertinoNavigationBar(
            middle: const Text('修改題目'),
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Text('取消'),
              onPressed: () => Navigator.pop(context),
            ),
            trailing: _isSaving
                ? const CupertinoActivityIndicator()
                : CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _save,
                    child: const Text('儲存'),
                  ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('題幹內文', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: _contentController,
                  maxLines: 5,
                  padding: const EdgeInsets.all(12),
                ),
                const SizedBox(height: 24),
                const Text('選項 (點擊圓圈設定正確答案)', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
                const SizedBox(height: 8),
                ...List.generate(_optionControllers.length, (index) {
                  final isSelected = _selectedAnswers.contains(index);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            setState(() {
                              if (isSelected) {
                                // 限制至少保留一個正確答案
                                if (_selectedAnswers.length > 1) {
                                  _selectedAnswers.remove(index);
                                }
                              } else {
                                _selectedAnswers.add(index);
                              }
                            });
                          },
                          child: Icon(
                            isSelected
                                ? CupertinoIcons.checkmark_circle_fill 
                                : CupertinoIcons.circle,
                            color: isSelected ? const Color(0xFF34C759) : const Color(0xFFC7C7CC),
                          ),
                        ),
                        Expanded(
                          child: CupertinoTextField(
                            controller: _optionControllers[index],
                            padding: const EdgeInsets.all(10),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 摺疊清單元素抽象類
abstract class _ListElement {}

class _YearHeaderElement extends _ListElement {
  final String year;
  final int count;
  _YearHeaderElement(this.year, this.count);
}

class _QuestionElement extends _ListElement {
  final ExamQuestion question;
  _QuestionElement(this.question);
}
