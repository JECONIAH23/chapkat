import 'package:flutter/material.dart';
import 'auth_service.dart';

class LoginScreen extends StatefulWidget {
  final Function(String) onLoginSuccess;
  final VoidCallback onToggle;

  const LoginScreen({
    super.key,
    required this.onLoginSuccess,
    required this.onToggle,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  bool _isLoading = false;
  final _formKey = GlobalKey<FormState>();

  // Future<void> _submitLogin() async {
  //   if (!_formKey.currentState!.validate()) return;

  //   setState(() => _isLoading = true);

  //   try {
  //     final success = await _authService.login(
  //       _usernameController.text,
  //       _pinController.text,
  //     );

  //     if (success && _authService.accessToken != null) {
  //       widget.onLoginSuccess(_authService.accessToken!);
  //       _showSuccessSnackbar('Login successful!');
  //     } else {
  //       _showErrorSnackbar('Invalid username or PIN');
  //     }
  //   } catch (e) {
  //     _showErrorSnackbar('Login failed: ${e.toString()}');
  //   } finally {
  //     if (mounted) {
  //       setState(() => _isLoading = false);
  //     }
  //   }
  // }
Future <void> _submitLogin() async {
  if (!_formKey.currentState!.validate()) return; // Add validation check

  setState(() => _isLoading = true);

  try {
    final success = await _authService.login(
      _usernameController.text,
      _pinController.text,
    );

    if (success && _authService.accessToken != null) {
      widget.onLoginSuccess(_authService.accessToken!);
      _showSuccessSnackbar('Login successful!');
    } else {
      _showErrorSnackbar('Invalid credentials');
    }
  } catch (e) {
    _showErrorSnackbar('Login failed: ${e.toString()}');
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}






  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your username';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _pinController,
                  decoration: const InputDecoration(
                    labelText: '4-digit PIN',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your PIN';
                    }
                    if (value.length != 4) {
                      return 'PIN must be 4 digits';
                    }
                    return null;
                  }
                ),
                const SizedBox(height: 20),
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                      onPressed: _isLoading ? null : () async {
                        if (_formKey.currentState!.validate()) {
                          await _submitLogin();
                          // After successful login, the AuthWrapper will handle navigation
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Login'),
                    ),
                
                TextButton(
                  onPressed: widget.onToggle,
                  child: const Text('Need an account? Register'),
                ),
              ],
            ),   
          ),
        ),
      ),
    );
  }
}