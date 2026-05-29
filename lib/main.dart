import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';

import 'services/firestore_service.dart';
import 'providers/app_provider.dart';
import 'screens/main_layout.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // 捕獲 Flutter 渲染與佈局階段的框架錯誤
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      developer.log("Flutter Error: ${details.exception}", error: details.exception);
    };

    // 捕獲 Platform / 異步任務中未處理的錯誤
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      developer.log("Platform Error: $error", error: error, stackTrace: stack);
      return true; // 標記為已處理
    };

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      // 自動執行匿名登入
      try {
        if (FirebaseAuth.instance.currentUser == null) {
          await FirebaseAuth.instance.signInAnonymously();
          developer.log("FirebaseAuth: 成功匿名登入");
        }
      } catch (authError) {
        developer.log("FirebaseAuth: 匿名登入失敗 (離線模式或未啟用)", error: authError);
      }
    } catch (e) {
      developer.log("Firebase 初始化失敗", error: e);
    }
    
    runApp(const QuizApp());
  }, (error, stack) {
    developer.log("Zone Error: $error", error: error, stackTrace: stack);
  });
}

class QuizApp extends StatelessWidget {
  const QuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<FirestoreService>(create: (_) => FirestoreService()),
        ChangeNotifierProvider<AppProvider>(
          create: (context) => AppProvider(
            Provider.of<FirestoreService>(context, listen: false),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Quiz App',
        theme: ThemeData(
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueAccent,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.transparent, // Background provided by AnimatedGradientBackground
        ),
        home: const MainLayout(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

