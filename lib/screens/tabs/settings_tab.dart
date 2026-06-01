import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../services/firestore_service.dart';
import '../../utils/data_importer.dart';
import '../manage_questions_screen.dart';

import '../../providers/app_provider.dart';

/// 設定 Tab
/// 
/// 管理考期、資料匯入與清空、學習重置等功能。
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

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

  /// 載入考試日期：快取優先 (SharedPreferences) + 雲端同步 (Firestore) 複合策略
  /// 
  /// 讀取本地快取後快速呈現，隨後非同步從 Firestore 抓取最新考期。
  /// 此處添加了變更檢查 `_examDate == null || !_examDate!.isAtSameMomentAs(remoteDate)`，
  /// 只有在雲端考期與本地不一致時才調用 `setState()` 更新 UI，避免不必要的重新構建。
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
      });
    }

    try {
      final remoteDate = await service.fetchExamDate();
      if (remoteDate != null && mounted) {
        // 唯有與當前日期不同時，才觸發 UI 更新
        if (_examDate == null || !_examDate!.isAtSameMomentAs(remoteDate)) {
          setState(() => _examDate = remoteDate);
        }
        await prefs.setString('examDate', remoteDate.toIso8601String());
      }
    } catch (e) {
      // 靜默處理背景同步失敗（例如離線模式下無法連接雲端，維持本地緩存日期即可）
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
              _buildSectionHeader('個人帳號'),
              _buildSettingsGroup([
                _buildSettingsItem(
                  icon: CupertinoIcons.person_crop_circle,
                  iconColor: const Color(0xFF007AFF),
                  title: '當前帳號',
                  subtitle: FirebaseAuth.instance.currentUser?.email ?? '已登入用戶',
                  onTap: () {},
                ),
                _buildSettingsItem(
                  icon: CupertinoIcons.square_arrow_right,
                  iconColor: const Color(0xFFFF3B30),
                  title: '登出帳號',
                  subtitle: '登出後將返回登入畫面',
                  onTap: _handleSignOut,
                ),
              ]),
              const SizedBox(height: 32),
              _buildSectionHeader('考試時程'),
              _buildSettingsGroup([
                _buildSettingsItem(
                  icon: CupertinoIcons.calendar,
                  iconColor: const Color(0xFF5856D6),
                  title: '設定考試日期',
                  subtitle: _examDate == null ? '點此設定預計考試日期' : '目前設定: ${DateFormat('yyyy/MM/dd').format(_examDate!)}',
                  onTap: _showDatePicker,
                ),
              ]),
              const SizedBox(height: 32),
              _buildSectionHeader('資料管理'),
              _buildSettingsGroup([
                _buildSettingsItem(
                  icon: CupertinoIcons.cloud_upload,
                  iconColor: const Color(0xFF34C759),
                  title: '上傳外部 JSON 題庫',
                  subtitle: '從手機檔案選取 JSON 檔案匯入',
                  onTap: () => _handleExternalImport(firestoreService),
                ),
                _buildSettingsItem(
                  icon: CupertinoIcons.cloud_download,
                  iconColor: const Color(0xFF007AFF),
                  title: '載入內建題庫',
                  subtitle: '匯入 assets/JSON/ 中的題目',
                  onTap: () => _handleLocalImport(firestoreService),
                ),
                _buildSettingsItem(
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
                  icon: CupertinoIcons.trash,
                  iconColor: const Color(0xFFFF3B30),
                  title: '重置所有學習狀態',
                  subtitle: '清空進度與錯題紀錄，不可復原',
                  onTap: () => _handleReset(firestoreService),
                ),
                _buildSettingsItem(
                  icon: CupertinoIcons.delete,
                  iconColor: const Color(0xFFFF3B30),
                  title: '清空所有題庫',
                  subtitle: '刪除 Firestore 中的所有題目資料',
                  onTap: () => _handleDeleteAll(firestoreService),
                ),
              ]),
              const SizedBox(height: 100),
            ]),
          ),
        ],
      ),
    );
  }

  /// 處理帳號登出
  void _handleSignOut() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('確認登出？'),
        content: const Text('登出後需要重新登入才能同步學習進度。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('確認登出'),
            onPressed: () async {
              Navigator.pop(context);
              
              // 1. 重置 Provider 考試日期狀態
              try {
                final appProvider = Provider.of<AppProvider>(context, listen: false);
                appProvider.resetExamDate();
              } catch (e) {
                // 靜默處理，防範 provider 在 context 重置時拋出錯誤
              }

              // 2. 清理本地考試日期快取
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('examDate');

              // 3. 執行 Firebase 登出
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
    );
  }

  /// 顯示考期選擇器
  void _showDatePicker() {
    final service = Provider.of<FirestoreService>(context, listen: false);
    final navigator = Navigator.of(context);
    
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
                  await service.saveExamDate(_examDate!);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('examDate', _examDate!.toIso8601String());
                }
                if (mounted) navigator.pop();
              },
            )
          ],
        ),
      ),
    );
  }

  /// 處理外部 JSON 題庫匯入
  void _handleExternalImport(FirestoreService firestoreService) async {
    final navigator = Navigator.of(context);
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null) {
        String content;
        if (kIsWeb) {
          content = utf8.decode(result.files.first.bytes!);
        } else {
          final file = File(result.files.single.path!);
          content = await file.readAsString(encoding: utf8);
        }

        if (!mounted) return;
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (c) => const Center(child: CupertinoActivityIndicator()),
        );

        Set<String> existingIds = appProvider.questions.map((q) => q.id).toSet();
        await DataImporter.importJsonContent(content, firestoreService, existingIds);

        if (!mounted) return;
        navigator.pop(); // 關閉等待圈圈
        _showCupertinoAlert('成功', '外部題庫匯入成功！');
      }
    } catch (e) {
      if (!mounted) return;
      if (navigator.canPop()) navigator.pop();
      _showCupertinoAlert('失敗', '匯入失敗: $e');
    }
  }

  /// 處理內建（本地 Assets）題庫匯入
  void _handleLocalImport(FirestoreService firestoreService) async {
    final navigator = Navigator.of(context);
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CupertinoActivityIndicator()),
    );
    
    try {
      Set<String> existingIds = appProvider.questions.map((q) => q.id).toSet();
      await DataImporter.importLocalJson(firestoreService, existingIds);

      if (!mounted) return;
      navigator.pop(); // 關閉等待圈圈
      _showCupertinoAlert('成功', '題庫更新成功！');
    } catch (e) {
      if (!mounted) return;
      navigator.pop(); // 關閉等待圈圈
      _showCupertinoAlert('失敗', '題庫更新失敗: $e');
    }
  }

  /// 刪除 Firestore 中的所有題目
  void _handleDeleteAll(FirestoreService firestoreService) async {
    final navigator = Navigator.of(context);
    
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
              Navigator.pop(c); // 關閉確認對話框
              
              if (!mounted) return;
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (c) => const PopScope(
                  canPop: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CupertinoActivityIndicator(radius: 15),
                        SizedBox(height: 16),
                        Text('正在刪除題庫，請稍候...', style: TextStyle(color: Colors.white, fontSize: 16, decoration: TextDecoration.none)),
                      ],
                    ),
                  ),
                ),
              );

              try {
                await firestoreService.deleteAllQuestions();
                if (!mounted) return;
                navigator.pop(); // 關閉等待圈圈
                _showCupertinoAlert('已清空', '題庫已全數刪除。');
              } catch (e) {
                if (!mounted) return;
                navigator.pop(); // 關閉等待圈圈
                _showCupertinoAlert('失敗', '刪除失敗: $e');
              }
            },
          ),
        ],
      ),
    );
  }

  /// 重置學習數據（但不刪除題目）
  void _handleReset(FirestoreService firestoreService) async {
    final appProvider = Provider.of<AppProvider>(context, listen: false);
    
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
              await firestoreService.resetAllProgress(appProvider.questions);
              if (!mounted) return;
              _showCupertinoAlert('已重置', '所有學習進度已歸零。');
            },
          ),
        ],
      ),
    );
  }

  void _showCupertinoAlert(String title, String message) {
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

  Widget _buildSettingsItem({
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
                color: iconColor.withValues(alpha: 0.1),
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
