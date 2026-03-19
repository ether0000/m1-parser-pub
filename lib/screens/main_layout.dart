import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../services/firestore_service.dart';
import '../models/exam_question.dart';
import '../utils/animated_background.dart';
import '../utils/glassmorphism.dart';
import '../utils/data_importer.dart';

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
            return Center(child: CupertinoActivityIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
          }

            final questions = snapshot.data ?? [];

            // Beautiful Empty/Welcome State
            if (questions.isEmpty) {
              return _buildWelcomeScreen(context, firestoreService);
            }

            // Normal Tab View
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
                items: [
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

  // Remove _buildGlassBottomNav as we're using CupertinoTabBar now


  Widget _buildGlassBottomNav() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.6),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.8))),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            backgroundColor: Colors.transparent,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: Colors.blueAccent,
            unselectedItemColor: Colors.black45,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: '看板'),
              BottomNavigationBarItem(icon: Icon(Icons.rocket_launch_rounded), label: '測驗'),
              BottomNavigationBarItem(icon: Icon(Icons.menu_book_rounded), label: '筆記'),
              BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: '設定'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeScreen(BuildContext context, FirestoreService firestoreService) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: GlassContainer(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.school_rounded, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 24),
              const Text(
                '歡迎來到醫管題庫',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '目前題庫是空的。點擊下方按鈕開始載入精選題目，展開你的學習之旅！',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.download_rounded),
                label: const Text('載入精選題庫', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 0,
                ),
                onPressed: () async {
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (c) => const Center(child: CircularProgressIndicator()),
                  );
                  try {
                    await DataImporter.importLocalJson(firestoreService, []);
                  } finally {
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text('點擊上方按鈕載入 JSON 題庫。', style: TextStyle(color: Colors.blueAccent)),
            ],
          ),
        ),
      ),
    );
  }
}
