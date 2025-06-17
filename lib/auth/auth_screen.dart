import 'package:flutter/material.dart';
import 'login.dart';
import 'register.dart';

class AuthScreen extends StatefulWidget {
  final Function(String) onLoginSuccess;

  const AuthScreen({super.key, required this.onLoginSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;

  void toggleView() {
    setState(() {
      _isLogin = !_isLogin;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLogin
          ? LoginScreen(
              onLoginSuccess: (token) {
                widget.onLoginSuccess(token); // Pass the token up
              },
              onToggle: toggleView,
            )
          : RegisterScreen(
              onLoginSuccess: (token) {
                widget.onLoginSuccess(token); // Pass the token up
              },
              onToggle: toggleView,
            ),
    );
  }
}
