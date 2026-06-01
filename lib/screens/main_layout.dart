import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';

import 'tabs/dashboard_tab.dart';
import 'tabs/practice_tab.dart';
import 'tabs/notes_tab.dart';
import 'tabs/settings_tab.dart';

/// 主體佈局元件
/// 
/// 採用 [StatefulWidget] 來維護底部導覽列的切換索引（局部 UI 狀態）。
/// 由於切換 Tab 僅影響目前畫面呈現，不涉及跨元件之業務數據共用，
/// 故直接使用原生 [StatefulWidget] 的 `setState()` 即可達到最佳效能與最簡單的程式碼結構。
/// 
/// 同時在建構時，透過 [context.watch<AppProvider>] 響應全域題庫加載狀態：
/// 在雲端資料尚未完全同步前，阻斷並呈現等待載入指示器，確保畫面數據的一致性。
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  // 當前選取的 Tab 索引
  int _currentIndex = 0;
  
  // 記錄跳轉至筆記 Tab 時的初始子頁面索引（例如從看板的某個按鈕點選，能直接跳轉至特定子 Tab）
  int _initialSubTabIndex = 0;

  /// 提供跨頁面跳轉的 Callback 方法
  /// 
  /// 藉由此 Callback 函數，子頁面（如 DashboardTab）可以間接通知 MainLayout
  /// 觸發 `setState` 來改變 `_currentIndex` 以實現 Tab 切換，並攜帶額外的子頁面參數。
  void _navigateToTab(int index, {int initialSubTabIndex = 0}) {
    setState(() {
      _currentIndex = index;
      _initialSubTabIndex = initialSubTabIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    
    // 若題庫與統計資料尚在從 Firestore 載入中，則展示讀取圈圈
    if (appProvider.isLoading) {
      return const Scaffold(
        body: Center(child: CupertinoActivityIndicator()),
      );
    }

    Widget currentTab;
    switch (_currentIndex) {
      case 0:
        currentTab = DashboardTab(
          onNavigate: _navigateToTab,
        );
        break;
      case 1:
        currentTab = const PracticeTab();
        break;
      case 2:
        currentTab = NotesTab(
          initialSubTabIndex: _initialSubTabIndex,
        );
        // 跳轉後立即重置，避免下次正常切換時仍停在舊的子頁面
        _initialSubTabIndex = 0;
        break;
      case 3:
      default:
        currentTab = const SettingsTab();
        break;
    }
    
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: currentTab,
      bottomNavigationBar: CupertinoTabBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        activeColor: const Color(0xFF007AFF),
        items: const [
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.square_grid_2x2), label: '看板'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.rocket), label: '測驗'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.book), label: '筆記'),
          BottomNavigationBarItem(icon: Icon(CupertinoIcons.settings), label: '設定'),
        ],
      ),
    );
  }
}
