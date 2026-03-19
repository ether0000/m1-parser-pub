import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../models/exam_question.dart';
import '../../services/firestore_service.dart';
import '../../utils/data_importer.dart';
import '../manage_questions_screen.dart';

class SettingsTab extends StatefulWidget {
  final List<ExamQuestion> questions;
  
  const SettingsTab({Key? key, required this.questions}) : super(key: key);

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  DateTime? _examDate;

  @override
  void initState() {
    super.initState();
    _loadExamDate();
  }

  Future<void> _loadExamDate() async {
    // 1. Local cache
    final prefs = await SharedPreferences.getInstance();
    final localDateStr = prefs.getString('examDate');
    if (mounted && localDateStr != null) {
      setState(() {
        _examDate = DateTime.tryParse(localDateStr);
      });
    }

    // 2. Firestore sync
    try {
      final service = Provider.of<FirestoreService>(context, listen: false);
      final remoteDate = await service.fetchExamDate();
      if (remoteDate != null && mounted) {
        setState(() => _examDate = remoteDate);
        await prefs.setString('examDate', remoteDate.toIso8601String());
      }
    } catch (e) {
      // Ignore background errors
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
            largeTitle: Text('設定'),
            backgroundColor: Color(0xFFF2F2F7),
            border: null,
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 20),
              _buildSectionHeader('考試時程'),
              _buildSettingsGroup([
                _buildSettingsItem(
                  context,
                  icon: CupertinoIcons.calendar,
                  iconColor: const Color(0xFF5856D6),
                  title: '設定考試日期',
                  subtitle: _examDate == null ? '點此設定預計考試日期' : '目前設定: ${DateFormat('yyyy/MM/dd').format(_examDate!)}',
                  onTap: () => _showDatePicker(context),
                ),
              ]),
              const SizedBox(height: 32),
              _buildSectionHeader('資料管理'),
              _buildSettingsGroup([
                _buildSettingsItem(
                  context,
                  icon: CupertinoIcons.cloud_upload,
                  iconColor: const Color(0xFF34C759),
                  title: '上傳外部 JSON 題庫',
                  subtitle: '從手機檔案選取 JSON 檔案匯入',
                  onTap: () => _handleExternalImport(context, firestoreService),
                ),
                _buildSettingsItem(
                  context,
                  icon: CupertinoIcons.cloud_download,
                  iconColor: const Color(0xFF007AFF),
                  title: '載入內建題庫',
                  subtitle: '匯入 assets/JSON/ 中的題目',
                  onTap: () => _handleLocalImport(context, firestoreService),
                ),
                _buildSettingsItem(
                  context,
                  icon: CupertinoIcons.pencil_ellipsis_rectangle,
                  iconColor: const Color(0xFF5856D6),
                  title: '管理現有題庫',
                  subtitle: '修改題幹、選項、正確答案',
                  onTap: () {
                    Navigator.push(
                      context,
                      CupertinoPageRoute(builder: (context) => const ManageQuestionsScreen()),
                    );
                  },
                ),
              ]),
              const SizedBox(height: 32),
              _buildSectionHeader('危險區域'),
              _buildSettingsGroup([
                _buildSettingsItem(
                  context,
                  icon: CupertinoIcons.trash,
                  iconColor: const Color(0xFFFF3B30),
                  title: '重置所有學習狀態',
                  subtitle: '清空進度與錯題紀錄，不可復原',
                  onTap: () => _handleReset(context, firestoreService),
                ),
                _buildSettingsItem(
                  context,
                  icon: CupertinoIcons.delete,
                  iconColor: const Color(0xFFFF3B30),
                  title: '清空所有題庫',
                  subtitle: '刪除 Firestore 中的所有題目資料',
                  onTap: () => _handleDeleteAll(context, firestoreService),
                ),
              ]),
              const SizedBox(height: 100),
            ]),
          ),
        ],
      ),
    );
  }

  void _showDatePicker(BuildContext context) {
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
              child: const Text('完成設定'),
              onPressed: () async {
                if (_examDate != null) {
                  // Save to Firestore
                  final service = Provider.of<FirestoreService>(context, listen: false);
                  await service.saveExamDate(_examDate!);
                  
                  // Save to Local
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('examDate', _examDate!.toIso8601String());
                }
                if (context.mounted) Navigator.pop(context);
              },
            )
          ],
        ),
      ),
    );
  }

  void _handleExternalImport(BuildContext context, FirestoreService firestoreService) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null) {
        String content;
        if (kIsWeb) {
          content = String.fromCharCodes(result.files.first.bytes!);
        } else {
          final file = File(result.files.single.path!);
          content = await file.readAsString();
        }

        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (c) => const Center(child: CupertinoActivityIndicator()),
          );
        }

        List<String> existingIds = widget.questions.map((q) => q.id).toList();
        await DataImporter.importJsonContent(content, firestoreService, existingIds);

        if (context.mounted) {
          Navigator.pop(context); // hide indicator
          _showCupertinoAlert(context, '成功', '外部題庫匯入成功！');
        }
      }
    } catch (e) {
      if (context.mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        _showCupertinoAlert(context, '失敗', '匯入失敗: $e');
      }
    }
  }

  void _handleLocalImport(BuildContext context, FirestoreService firestoreService) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CupertinoActivityIndicator()),
    );
    try {
      List<String> existingIds = widget.questions.map((q) => q.id).toList();
      await DataImporter.importLocalJson(firestoreService, existingIds);
      if (context.mounted) {
        Navigator.pop(context);
        _showCupertinoAlert(context, '成功', '題庫更新成功！');
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        _showCupertinoAlert(context, '失敗', '題庫更新失敗: $e');
      }
    }
  }

  void _handleDeleteAll(BuildContext context, FirestoreService firestoreService) async {
    showCupertinoDialog(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: const Text('確認清空題庫？'),
        content: const Text('即將刪除雲端所有題目，此操作無法復原。建議先備份 JSON。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(c),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('確認清空'),
            onPressed: () async {
              Navigator.pop(c);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (c) => const Center(child: CupertinoActivityIndicator()),
              );
              try {
                await firestoreService.deleteAllQuestions();
                if (context.mounted) {
                  Navigator.pop(context); // hide indicator
                  _showCupertinoAlert(context, '已清空', '題庫已全數刪除。');
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                  _showCupertinoAlert(context, '失敗', '刪除失敗: $e');
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _handleReset(BuildContext context, FirestoreService firestoreService) async {
    showCupertinoDialog(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: const Text('確認重置？'),
        content: const Text('即將清空所有題目的作答紀錄與精通狀態，此動作無法復原。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(c),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('確認重置'),
            onPressed: () async {
              Navigator.pop(c);
              await firestoreService.resetAllProgress(widget.questions);
              if (context.mounted) {
                _showCupertinoAlert(context, '已重置', '所有學習進度已歸零。');
              }
            },
          ),
        ],
      ),
    );
  }

  void _showCupertinoAlert(BuildContext context, String title, String message) {
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
      ),
    );
  }

  Widget _buildSettingsGroup(List<Widget> items) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: items,
      ),
    );
  }

  Widget _buildSettingsItem(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 17, color: Colors.black)),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_forward, color: Color(0xFFC7C7CC), size: 18),
          ],
        ),
      ),
    );
  }
}
