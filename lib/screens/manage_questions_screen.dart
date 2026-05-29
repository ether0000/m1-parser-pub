import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../models/exam_question.dart';
import '../services/firestore_service.dart';

class ManageQuestionsScreen extends StatefulWidget {
  const ManageQuestionsScreen({Key? key}) : super(key: key);

  @override
  State<ManageQuestionsScreen> createState() => _ManageQuestionsScreenState();
}

class _ManageQuestionsScreenState extends State<ManageQuestionsScreen> {
  List<ExamQuestion> _allQuestions = [];
  List<ExamQuestion> _filteredQuestions = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedYears = {};

  Map<String, List<ExamQuestion>> get _groupedQuestions {
    Map<String, List<ExamQuestion>> groups = {};
    for (var q in _filteredQuestions) {
      if (!groups.containsKey(q.year)) {
        groups[q.year] = [];
      }
      groups[q.year]!.add(q);
    }
    // Sort years descending
    var sortedKeys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    
    // Sort questions within each year group by their number
    Map<String, List<ExamQuestion>> sortedGroups = {};
    for (var k in sortedKeys) {
      final yearList = groups[k]!;
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    final service = Provider.of<FirestoreService>(context, listen: false);
    // For management, we might want to fetch all or use pagination. 
    // Starting with a stream-based or simple get for now if count isn't too huge.
    // If it's huge, we'd use getQuestionsPaginated.
    final questions = await service.getAllQuestionsCached();
    if (mounted) {
      setState(() {
        _allQuestions = questions;
        _filteredQuestions = questions;
        _isLoading = false;
      });
    }

  }

  void _filterQuestions(String query) {
    setState(() {
      _filteredQuestions = _allQuestions
          .where((q) =>
              q.content.toLowerCase().contains(query.toLowerCase()) ||
              q.year.contains(query) ||
              q.subject.toLowerCase().contains(query.toLowerCase()))
          .toList();
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
                    minSize: 0,
                    child: const Icon(CupertinoIcons.pencil_circle, size: 20, color: Color(0xFF007AFF)),
                    onPressed: () => _showUpdateYearDialog(year),
                  ),
                  const SizedBox(width: 8),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 0,
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

  void _editQuestion(ExamQuestion q) {
    final contentController = TextEditingController(text: q.content);
    final List<TextEditingController> optionControllers = 
        q.options.map((opt) => TextEditingController(text: opt)).toList();
    final List<int> selectedAnswers = List<int>.from(q.correctAnswers);

    showCupertinoModalPopup(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
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
                trailing: CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Text('儲存'),
                  onPressed: () async {
                    final updatedQ = ExamQuestion(
                      id: q.id,
                      year: q.year,
                      subject: q.subject,
                      content: contentController.text,
                      options: optionControllers.map((c) => c.text).toList(),
                      correctAnswers: selectedAnswers,
                      userNote: q.userNote,
                      errorCount: q.errorCount,
                      correctCount: q.correctCount,
                      attemptCount: q.attemptCount,
                      lastAttemptDate: q.lastAttemptDate,
                      isMastered: q.isMastered,
                      isFavorite: q.isFavorite,
                    );
                    
                    final service = Provider.of<FirestoreService>(context, listen: false);
                    await service.updateQuestion(updatedQ);
                    
                    setState(() {
                      int idx = _allQuestions.indexWhere((element) => element.id == q.id);
                      if (idx != -1) _allQuestions[idx] = updatedQ;
                      _filterQuestions(_searchController.text);
                    });
                    
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('題幹內文', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
                    const SizedBox(height: 8),
                    CupertinoTextField(
                      controller: contentController,
                      maxLines: 5,
                      padding: const EdgeInsets.all(12),
                    ),
                    const SizedBox(height: 24),
                    const Text('選項 (點擊圓圈設定正確正確答案)', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
                    const SizedBox(height: 8),
                    ...List.generate(optionControllers.length, (index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => setModalState(() {
                                if (selectedAnswers.contains(index)) {
                                  if (selectedAnswers.length > 1) {
                                    selectedAnswers.remove(index);
                                  }
                                } else {
                                  selectedAnswers.add(index);
                                }
                              }),
                              child: Icon(
                                selectedAnswers.contains(index)
                                    ? CupertinoIcons.checkmark_circle_fill 
                                    : CupertinoIcons.circle,
                                color: selectedAnswers.contains(index) ? const Color(0xFF34C759) : const Color(0xFFC7C7CC),
                              ),
                            ),
                            Expanded(
                              child: CupertinoTextField(
                                controller: optionControllers[index],
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
        ),
      ),
    );
  }

  void _confirmDeleteByYear(String year) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('確認刪除 $year 年題庫？'),
        content: const Text('此操作將刪除該年份所有題目，且無法復原。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('確認刪除'),
            onPressed: () async {
              Navigator.pop(context);
              _showLoading('正在刪除 $year 年題目...');
              try {
                final service = Provider.of<FirestoreService>(context, listen: false);
                await service.deleteQuestionsByYear(year);
                await _loadQuestions();
                if (mounted) Navigator.pop(context); // Close loading
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  _showAlert('錯誤', '刪除失敗: $e');
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showUpdateYearDialog(String oldYear) {
    final controller = TextEditingController(text: oldYear);
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
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            child: const Text('確認修改'),
            onPressed: () async {
              final newYear = controller.text.trim();
              if (newYear.isEmpty || newYear == oldYear) {
                Navigator.pop(context);
                return;
              }
              Navigator.pop(context);
              _showLoading('正在批次更新年份...');
              try {
                final service = Provider.of<FirestoreService>(context, listen: false);
                await service.updateQuestionsYear(oldYear, newYear);


                await _loadQuestions();
                if (mounted) Navigator.pop(context);
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context);
                  _showAlert('錯誤', '更新失敗: $e');
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showLoading(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CupertinoActivityIndicator(radius: 15),
              const SizedBox(height: 16),
              Text(message, style: const TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

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
