import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/animated_background.dart';
import '../utils/glassmorphism.dart';

/// 身份驗證畫面 (登入 / 註冊)
/// 
/// 採用 [StatefulWidget] 管理輸入控制器的生命週期，並實作 Email/Password 的驗證流程。
/// 視覺上融合了 [AnimatedGradientBackground] 與 [GlassContainer] 玻璃擬態質感，打造極佳的極簡美學。
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSignUp = false; // 是否為註冊模式
  bool _isLoading = false; // 正在發起非同步認證請求的阻斷標記
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 發起 Firebase Auth 認證
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      if (_isSignUp) {
        // 註冊新帳號
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        // 登入現有帳號
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      // 成功登入/註冊後，重置/清除本地考試日期快取，避免被舊 session 的快取污染
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('examDate');
      } catch (e) {
        // 靜默處理
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = _getFriendlyErrorMessage(e);
      });
      _showErrorDialog(_errorMessage!);
    } catch (e) {
      setState(() {
        _errorMessage = "發生未知錯誤，請稍後再試。";
      });
      _showErrorDialog(_errorMessage!);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 將 Firebase Auth 錯誤碼轉換為親切的中文提示
  String _getFriendlyErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Email 格式不正確。';
      case 'user-disabled':
        return '此帳號已被停用。';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email 或密碼錯誤，請重新輸入。';
      case 'email-already-in-use':
        return '該 Email 已被註冊，請直接登入。';
      case 'operation-not-allowed':
        return '系統暫未開放 Email 登入。';
      case 'weak-password':
        return '密碼強度不足，長度至少需 6 個字元。';
      default:
        return e.message ?? '認證失敗，請檢查網路連線。';
    }
  }

  void _showErrorDialog(String message) {
    showCupertinoDialog(
      context: context,
      builder: (c) => CupertinoAlertDialog(
        title: Text(_isSignUp ? '註冊失敗' : '登入失敗'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: AnimatedGradientBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Logo/Icon
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: const Icon(
                      CupertinoIcons.rocket_fill,
                      size: 45,
                      color: Color(0xFF007AFF),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'M1 證照題庫特訓',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSignUp ? '建立專屬帳號，開啟多端同步學習' : '登入您的帳號以同步歷史與錯題',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                  const SizedBox(height: 36),
                  
                  // 登入玻璃卡片
                  GlassContainer(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            '電子郵件',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: Colors.black87),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(CupertinoIcons.mail, size: 20, color: Colors.black45),
                              filled: true,
                              fillColor: Colors.black.withValues(alpha: 0.03),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              hintText: 'name@example.com',
                              hintStyle: const TextStyle(color: Colors.black38),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return '請輸入電子郵件';
                              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val.trim())) {
                                return '請輸入正確的電子郵件格式';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '密碼',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            style: const TextStyle(color: Colors.black87),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(CupertinoIcons.lock, size: 20, color: Colors.black45),
                              filled: true,
                              fillColor: Colors.black.withValues(alpha: 0.03),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              hintText: '至少 6 位密碼',
                              hintStyle: const TextStyle(color: Colors.black38),
                            ),
                            onFieldSubmitted: (_) => _submit(),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return '請輸入密碼';
                              if (val.trim().length < 6) return '密碼長度至少需 6 個字元';
                              return null;
                            },
                          ),
                          const SizedBox(height: 32),
                          
                          // 提交按鈕
                          SizedBox(
                            height: 50,
                            child: _isLoading
                                ? const Center(child: CupertinoActivityIndicator())
                                : CupertinoButton(
                                    color: const Color(0xFF007AFF),
                                    padding: EdgeInsets.zero,
                                    borderRadius: BorderRadius.circular(12),
                                    onPressed: _submit,
                                    child: Text(
                                      _isSignUp ? '註冊帳號' : '登入',
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // 切換登入/註冊模式
                  CupertinoButton(
                    child: Text(
                      _isSignUp ? '已有帳號？立即登入' : '沒有帳號？立即註冊',
                      style: const TextStyle(color: Color(0xFF007AFF), fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    onPressed: () {
                      setState(() {
                        _isSignUp = !_isSignUp;
                        _errorMessage = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
