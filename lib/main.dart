import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';

import 'services/firestore_service.dart';
import 'providers/app_provider.dart';
import 'screens/main_layout.dart';
import 'screens/auth_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  // 使用 runZonedGuarded 捕捉 Flutter 框架以外的未處理異步錯誤，
  // 這是生產環境下不可或缺的防禦措施，防止 App 因為底層非同步任務異常而無預警閃退。
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // 捕獲 Flutter 渲染與佈局階段的框架錯誤，將其呈現在螢幕並輸出日誌
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      developer.log("Flutter Error: ${details.exception}", error: details.exception);
    };

    // 捕獲 Platform / 異步任務中未處理的錯誤，防止未捕獲的 Future 異常導致應用崩潰
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      developer.log("Platform Error: $error", error: error, stackTrace: stack);
      return true; // 標記為已處理，阻斷錯誤進一步擴散
    };

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // 配置 Firestore 的本地離線持久化與快取容量設定
      // 如此一來，即使用戶網路中斷，App 依然能無縫讀取已快取的題庫資料，保證完全不受離線影響的離線體驗
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
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
    return Provider<FirestoreService>(
      create: (_) => FirestoreService(),
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
        // 監聽登入身份狀態
        // 若未登入則導向 AuthScreen 進行登入/註冊；
        // 已登入則將當前用戶專屬的 AppProvider 注入，並導向主 Layout。
        // 這種做法在帳號登出或切換時，會自動觸發舊 Provider 銷毀與新 Provider 的創立，確保資料隔離安全性。
        home: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CupertinoActivityIndicator()),
              );
            }
            
            if (snapshot.hasData && snapshot.data != null) {
              return ChangeNotifierProvider<AppProvider>(
                create: (context) => AppProvider(
                  Provider.of<FirestoreService>(context, listen: false),
                ),
                child: const MainLayout(),
              );
            }
            
            return const AuthScreen();
          },
        ),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

