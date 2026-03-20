import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../utils/animated_background.dart';
import '../utils/glassmorphism.dart';

import 'tabs/dashboard_tab.dart';
import 'tabs/practice_tab.dart';
import 'tabs/notes_tab.dart';
import 'tabs/settings_tab.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;
  int _initialSubTabIndex = 0;

  void _navigateToTab(int index, {int initialSubTabIndex = 0}) {
    setState(() {
      _currentIndex = index;
      _initialSubTabIndex = initialSubTabIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    
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
        // Reset the initial sub tab index after it's been used
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
