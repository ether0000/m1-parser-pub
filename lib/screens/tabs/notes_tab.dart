import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../models/exam_question.dart';
import '../../models/quiz_session.dart';
import '../../models/question_category.dart';
import '../../services/firestore_service.dart';

class NotesTab extends StatefulWidget {
  final List<ExamQuestion> questions;

  const NotesTab({Key? key, required this.questions}) : super(key: key);

  @override
  State<NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<NotesTab> {
  late Future<List<QuizSession>> _sessionsFuture;
  final Set<String> _expandedSessions = {};
  List<QuestionCategory> _categories = [];
  String _selectedTag = '全部';

  static const List<String> mainTags = [
    '醫療資訊系統概論',
    '醫療資訊技術',
    '醫療資訊系統開發',
    '醫療資訊系統個論',
    '醫療資訊發展趨勢'
  ];

  static const List<String> subTags = [
    '醫療資訊標準',
    '醫療資訊資料庫管理系統',
    '醫療資訊安全',
    '病歷管理系統',
    '護理資訊系統',
    '電子病歷',
    '遠距醫療'
  ];

  List<String> get allTags => ['全部', ...mainTags, ...subTags];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final service = Provider.of<FirestoreService>(context, listen: false);
    _sessionsFuture = service.getQuizSessions();
    service.getCategories().then((value) {
      if (mounted) setState(() => _categories = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text('錯題與筆記'),
            backgroundColor: Color(0xFFF2F2F7),
            border: null,
          ),
          SliverToBoxAdapter(
            child: _buildFilterChips(),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: FutureBuilder<List<QuizSession>>(
              future: _sessionsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(
                    child: Center(child: CupertinoActivityIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return SliverToBoxAdapter(
                    child: Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: CupertinoColors.systemRed))),
                  );
                }
                final sessions = snapshot.data ?? [];
                
                // If filter is specific, we might want to show questions globally or filtered by session
                // The spec says "Filter Chips僅顯示該分類的錯題與筆記"
                // Let's filter the sessions content or the sessions themselves.
                
                if (sessions.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 100),
                      child: Center(
                        child: Text('尚無測驗紀錄', style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 16)),
                      ),
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final session = sessions[index];
                      return _buildSessionCard(session);
                    },
                    childCount: sessions.length,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: allTags.length,
        itemBuilder: (context, index) {
          final tag = allTags[index];
          final isSelected = _selectedTag == tag;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(tag, style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontSize: 13)),
              selected: isSelected,
              selectedColor: const Color(0xFF007AFF),
              backgroundColor: Colors.white,
              onSelected: (selected) {
                setState(() => _selectedTag = tag);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSessionCard(QuizSession session) {
    // If a tag is selected, check if this session has any questions with that tag
    final questionsInSession = widget.questions.where((q) => session.wrongQuestionIds.contains(q.id)).toList();
    final hasTaggedQuestions = _selectedTag == '全部' || questionsInSession.any((q) => q.tags.contains(_selectedTag));

    if (!hasTaggedQuestions) return const SizedBox.shrink();

    final bool isExpanded = _expandedSessions.contains(session.sessionId);
    final String dateString = DateFormat('yyyy年MM月dd日 HH:mm').format(session.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              setState(() {
                if (isExpanded) {
                  _expandedSessions.remove(session.sessionId);
                } else {
                  _expandedSessions.add(session.sessionId);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$dateString 測驗', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black)),
                        const SizedBox(height: 4),
                        Text('共 ${session.totalQuestions} 題 / 錯 ${session.wrongCount} 題',
                            style: const TextStyle(fontSize: 14, color: Color(0xFFFF3B30))),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                    color: CupertinoColors.systemGrey,
                  ),
                ],
              ),
            ),
          ),
          
          if (isExpanded && session.wrongQuestionIds.isNotEmpty)
            const Divider(height: 1, color: Color(0xFFE5E5EA)),
            
          if (isExpanded)
            _buildWrongQuestionsList(session.wrongQuestionIds),
        ],
      ),
    );
  }

  Widget _buildWrongQuestionsList(List<String> questionIds) {
    final filteredIds = _selectedTag == '全部' 
        ? questionIds 
        : questionIds.where((id) {
            final q = widget.questions.firstWhere((q) => q.id == id, orElse: () => ExamQuestion(id: '', year: '', subject: '', content: '', options: [], correctAnswers: [0]));
            return q.tags.contains(_selectedTag);
          }).toList();

    if (filteredIds.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('符合條件的題目為空。', style: TextStyle(color: CupertinoColors.systemGrey)),
      );
    }
    
    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filteredIds.length,
      separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFE5E5EA), indent: 16),
      itemBuilder: (context, index) {
        final q = widget.questions.firstWhere((q) => q.id == filteredIds[index]);
        return _buildQuestionItem(q);
      },
    );
  }

  Widget _buildQuestionItem(ExamQuestion q) {
    return InkWell(
      onTap: () => _showNoteAndTagBottomSheet(q),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(q.subject, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF007AFF), fontSize: 13))),
                if (q.tags.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    children: q.tags.map((tag) {
                          bool isCustom = !mainTags.contains(tag) && !subTags.contains(tag);
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isCustom ? Colors.blueGrey.withOpacity(0.1) : const Color(0xFFE5E5EA),
                              borderRadius: BorderRadius.circular(4),
                              border: isCustom ? Border.all(color: Colors.blueGrey.withOpacity(0.2), width: 0.5) : null,
                            ),
                            child: Text(tag, style: TextStyle(fontSize: 10, color: isCustom ? Colors.blueGrey : const Color(0xFF8E8E93))),
                          );
                        }).toList(),
                  )
              ],
            ),
            const SizedBox(height: 4),
            Text(q.content, style: const TextStyle(fontSize: 15, color: Colors.black)),
            const SizedBox(height: 8),
            if (q.options.isNotEmpty)
              Text('正確答案: ${q.correctAnswers.map((idx) => q.options[idx]).join(' / ')}', style: const TextStyle(fontSize: 14, color: CupertinoColors.systemGreen)),
            if (q.userNote.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(6)),
                child: Text('筆記: ${q.userNote}', style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93))),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minSize: 0,
                child: const Text('編輯標籤與筆記', style: TextStyle(fontSize: 12, color: Color(0xFF007AFF))),
                onPressed: () => _showNoteAndTagBottomSheet(q),
              ),
            )
          ],
        ),
      ),
    );
  }

  void _showNoteAndTagBottomSheet(ExamQuestion q) {
    final noteController = TextEditingController(text: q.userNote);
    final customTagController = TextEditingController();
    List<String> tempTags = List<String>.from(q.tags);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              decoration: const BoxDecoration(
                color: Color(0xFFF2F2F7),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(color: CupertinoColors.systemGrey4, borderRadius: BorderRadius.circular(3)),
                  ),
                  const Text('編輯筆記與標籤', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black)),
                  const SizedBox(height: 16),
                  
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        const Text('我的筆記', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                          child: CupertinoTextField(
                            controller: noteController,
                            maxLines: 4,
                            placeholder: '在此輸入筆記...',
                            padding: const EdgeInsets.all(12),
                            decoration: null,
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        const Text('主類別標籤', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
                        const SizedBox(height: 8),
                        _buildTagGrid(mainTags, tempTags, setSheetState),
                        
                        const SizedBox(height: 24),
                        const Text('子類別標籤', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
                        const SizedBox(height: 8),
                        _buildTagGrid(subTags, tempTags, setSheetState),
                        
                        const SizedBox(height: 24),
                        const Text('自訂標籤', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: CupertinoTextField(
                                controller: customTagController,
                                placeholder: '輸入新標籤名稱...',
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: CupertinoColors.systemGrey4),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            CupertinoButton(
                              child: const Icon(CupertinoIcons.plus_circle_fill),
                              onPressed: () {
                                if (customTagController.text.isNotEmpty && !tempTags.contains(customTagController.text)) {
                                  setSheetState(() {
                                    tempTags.add(customTagController.text);
                                  });
                                  customTagController.clear();
                                }
                              },
                            ),
                          ],
                        ),
                        if (tempTags.any((t) => !mainTags.contains(t) && !subTags.contains(t)))
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: _buildTagGrid(
                              tempTags.where((t) => !mainTags.contains(t) && !subTags.contains(t)).toList(),
                              tempTags,
                              setSheetState,
                              isCustom: true,
                            ),
                          ),
                        
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                  
                  Container(
                    color: Colors.white,
                    padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16, top: 16, left: 16, right: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: CupertinoButton.filled(
                        onPressed: () async {
                          final service = Provider.of<FirestoreService>(context, listen: false);
                          
                          // Save note
                          await service.updateQuestionNote(q.id, noteController.text);
                          
                          // Save tags
                          // We need a way to update tags in FirestoreService
                          await service.updateQuestionTags(q.id, tempTags);

                          setState(() {
                            q.userNote = noteController.text;
                            q.tags.clear();
                            q.tags.addAll(tempTags);
                          });
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Text('儲存'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildTagGrid(List<String> sourceTags, List<String> selectedTags, Function setSheetState, {bool isCustom = false}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sourceTags.map((tag) {
        final isSelected = selectedTags.contains(tag);
        return FilterChip(
          label: Text(tag, style: TextStyle(color: isSelected ? Colors.white : (isCustom ? Colors.blueGrey : Colors.black87), fontSize: 12)),
          selected: isSelected,
          onSelected: (selected) {
            setSheetState(() {
              if (selected) {
                if (!selectedTags.contains(tag)) selectedTags.add(tag);
              } else {
                selectedTags.remove(tag);
              }
            });
          },
          selectedColor: isCustom ? Colors.blueGrey : const Color(0xFF007AFF),
          backgroundColor: isCustom ? Colors.grey.withOpacity(0.1) : Colors.white,
          checkmarkColor: Colors.white,
          shape: isCustom ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.withOpacity(0.2))) : null,
        );
      }).toList(),
    );
  }
}
