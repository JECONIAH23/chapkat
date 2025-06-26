import 'package:flutter/material.dart';
import 'home_page.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return HomePage(
      title: "Voice Book Keep",
      // onLogout: () {}, // Empty callback since no auth
    );
  }
}
