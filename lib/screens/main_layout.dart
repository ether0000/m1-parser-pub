import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../services/firestore_service.dart';
import '../models/exam_question.dart';
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

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: StreamBuilder<List<ExamQuestion>>(
        stream: firestoreService.getQuestionsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CupertinoActivityIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
          }

          final questions = snapshot.data ?? [];

          // Normal Tab View (Welcome Screen removed as per Task 6)
          Widget currentTab;
          switch (_currentIndex) {
            case 0:
              currentTab = DashboardTab(questions: questions);
              break;
            case 1:
              currentTab = PracticeTab(questions: questions);
              break;
            case 2:
              currentTab = NotesTab(questions: questions);
              break;
            case 3:
            default:
              currentTab = SettingsTab(questions: questions);
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
        },
      ),
    );
  }
}
