import 'package:flutter/material.dart';
import 'auth/auth_screen.dart';
import 'home_page.dart';
import 'auth/auth_service.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    final isLoggedIn = await _authService.isLoggedIn();
    debugPrint('isLoggedIn: $isLoggedIn');
    if (mounted) {
      setState(() {
        _isLoggedIn = isLoggedIn;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLoginSuccess(String token) async {
    if (!mounted) return;
    
    debugPrint('Navigating to MyHomePage with token: $token');
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => MyHomePage(
          title: "Voice Book Keep",
          authService: _authService,
          onLogout: _handleLogout,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _isLoggedIn = true;
      });
      debugPrint('Navigation to MyHomePage completed');
    }
  }

  Future<void> _handleLogout() async {
    await _authService.logout();
    if (mounted) {
      setState(() => _isLoggedIn = false);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AuthWrapper()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return _isLoggedIn
        ? MyHomePage(
            title: "Voice Book Keep",
            authService: _authService,
            onLogout: _handleLogout,
          )
        : AuthScreen(
            onLoginSuccess: _handleLoginSuccess,
          );
  }
}