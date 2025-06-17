import 'package:flutter/material.dart';
import 'auth_service.dart';

class RegisterScreen extends StatefulWidget {
  final Function(String) onLoginSuccess;
  final VoidCallback onToggle;

  const RegisterScreen({
    super.key,
    required this.onLoginSuccess,
    required this.onToggle,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  String _firstName = '';
  String _lastName = '';
  String _username = '';
  String _phone = '';
  String _email = '';
  String _pin = '';
  bool _isLoading = false;
  String _errorMessage = '';

  Future<void> _submitRegister() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final success = await _authService.register(
      firstName: _firstName,
      lastName: _lastName,
      username: _username,
      phoneNumber: _phone,
      email: _email,
      pin: _pin,
    );

    if (success) {
      final loginSuccess = await _authService.login(_username, _pin);
      if (loginSuccess && _authService.accessToken != null) {
        widget.onLoginSuccess(_authService.accessToken!);
      } else {
        setState(() {
          _errorMessage = 'Registered but login failed.';
        });
      }
    } else {
      setState(() {
        _errorMessage = 'Registration failed.';
      });
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  decoration: const InputDecoration(labelText: 'First Name'),
                  onSaved: (val) => _firstName = val!,
                  validator: (val) => val!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Last Name'),
                  onSaved: (val) => _lastName = val!,
                  validator: (val) => val!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Username'),
                  onSaved: (val) => _username = val!,
                  validator: (val) => val!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                  onSaved: (val) => _phone = val!,
                  validator: (val) => val!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  onSaved: (val) => _email = val!,
                  validator: (val) => !val!.contains('@') ? 'Invalid email' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  decoration: const InputDecoration(labelText: '4-digit PIN'),
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  onSaved: (val) => _pin = val!,
                  validator: (val) => val!.length != 4 ? 'Enter 4 digits' : null,
                ),
                if (_errorMessage.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                  ),
                const SizedBox(height: 20),
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _submitRegister,
                        child: const Text('Register'),
                      ),
                TextButton(
                  onPressed: widget.onToggle,
                  child: const Text('Already have an account? Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
