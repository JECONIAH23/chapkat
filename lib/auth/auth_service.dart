import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AuthService {
  static const String _baseUrl = 'https://chapkat-backend.onrender.com/api';
  // static const String _baseUrl = 'https://bengieantony.pythonanywhere.com/api';
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';

  String? accessToken;
  String? refreshToken;
  late SharedPreferences _prefs;
  bool _initialized = false;

  // Initialize SharedPreferences once
  Future<void> _init() async {
    if (!_initialized) {
      _prefs = await SharedPreferences.getInstance();
      _initialized = true;
    }
  }

  // Save tokens using SharedPreferences
  Future<void> _saveTokens() async {
    await _init();
    await Future.wait([
      _prefs.setString(_accessTokenKey, accessToken ?? ''),
      _prefs.setString(_refreshTokenKey, refreshToken ?? ''),
    ]);
  }

  // Load tokens from storage
  Future<void> _loadTokens() async {
    await _init();
    accessToken = _prefs.getString(_accessTokenKey);
    refreshToken = _prefs.getString(_refreshTokenKey);
  }

  // Clear tokens from storage
  Future<void> _clearTokens() async {
    await _init();
    await Future.wait([
      _prefs.remove(_accessTokenKey),
      _prefs.remove(_refreshTokenKey),
    ]);
  }

  // Generic HTTP request handler
  Future<http.Response?> _makeRequest(
    String endpoint, {
    Map<String, dynamic>? body,
    String method = 'POST',
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/$endpoint');
      final headers = {'Content-Type': 'application/json'};
      final encodedBody = body != null ? json.encode(body) : null;

      switch (method) {
        case 'POST':
          return await http.post(uri, headers: headers, body: encodedBody);
        case 'GET':
          return await http.get(uri, headers: headers);
        default:
          throw Exception('Unsupported HTTP method');
      }
    } catch (e) {
      _logError('Request to $endpoint failed', e);
      return null;
    }
  }

  // Register user
  Future<bool> register({
    required String firstName,
    required String lastName,
    required String username,
    required String phoneNumber,
    required String email,
    required String pin,
  }) async {
    final response = await _makeRequest(
      'register/',
      body: {
        'first_name': firstName,
        'last_name': lastName,
        'username': username,
        'phone_number': phoneNumber,
        'email': email,
        'pin': pin,
      },
    );

    return _handleResponse(response, successCode: 200);
  }

  // Login user
  Future<bool> login(String username, String pin) async {
    final response = await _makeRequest(
      'login/',
      body: {'username': username, 'pin': pin},
    );

    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      accessToken = data['access'];
      refreshToken = data['refresh'];
      await _saveTokens();
      return true;
    }

    _logError('Login failed', response?.body);
    return false;
  }

  // Refresh access token
  Future<bool> refreshAccessToken() async {
    await _loadTokens();
    if (refreshToken == null) return false;

    final response = await _makeRequest(
      'token/refresh/',
      body: {'refresh': refreshToken},
    );

    if (response != null && response.statusCode == 200) {
      final data = json.decode(response.body);
      accessToken = data['access'];
      await _saveTokens();
      return true;
    }

    await logout(); // Clear invalid tokens
    return false;
  }

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    await _loadTokens();
    return accessToken != null;
  }

  // Logout user
  Future<void> logout() async {
    await _clearTokens();
    accessToken = null;
    refreshToken = null;
  }

  // Helper methods
  bool _handleResponse(http.Response? response, {required int successCode}) {
    if (response == null) return false;

    if (response.statusCode == successCode) {
      return true;
    } else {
      _logError('Request failed', response.body);
      return false;
    }
  }

  void _logError(String message, dynamic error) {
    // In production, use proper logging (e.g., Firebase Crashlytics)
    debugPrint('$message: $error');
  }
}

// import 'package:http/http.dart' as http;
// import 'package:shared_preferences/shared_preferences.dart';
// import 'dart:convert';

// class AuthService {
//   static const String baseUrl = 'https://bengieantony.pythonanywhere.com/api';
//   String? accessToken;
//   String? refreshToken;

//   // Save tokens using SharedPreferences
//   Future<void> _saveTokens() async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setString('access_token', accessToken ?? '');
//     await prefs.setString('refresh_token', refreshToken ?? '');
//   }

//   // Load tokens from storage
//   Future<void> _loadTokens() async {
//     final prefs = await SharedPreferences.getInstance();
//     accessToken = prefs.getString('access_token');
//     refreshToken = prefs.getString('refresh_token');
//   }

//   // Clear tokens from storage
//   Future<void> _clearTokens() async {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.remove('access_token');
//     await prefs.remove('refresh_token');
//   }

//   // Register user
//   Future<bool> register({
//     required String firstName,
//     required String lastName,
//     required String username,
//     required String phoneNumber,
//     required String email,
//     required String pin,
//   }) async {
//     try {
//       final response = await http.post(
//         Uri.parse('$baseUrl/register/'),
//         headers: {'Content-Type': 'application/json'},
//         body: json.encode({
//           'first_name': firstName,
//           'last_name': lastName,
//           'username': username,
//           'phone_number': phoneNumber,
//           'email': email,
//           'pin': pin,
//         }),
//       );

//       if (response.statusCode == 200) {
//         return true;
//       } else {
//         print('Registration failed: ${response.body}');
//         return false;
//       }
//     } catch (e) {
//       print('Registration error: $e');
//       return false;
//     }
//   }

//   // Login user
//   Future<bool> login(String username, String pin) async {
//     try {
//       final response = await http.post(
//         Uri.parse('$baseUrl/login/'),
//         headers: {'Content-Type': 'application/json'},
//         body: json.encode({
//           'username': username,
//           'pin': pin,
//         }),
//       );

//       if (response.statusCode == 200) {
//         final data = json.decode(response.body);
//         accessToken = data['access'];
//         refreshToken = data['refresh'];
//         await _saveTokens();
//         return true;
//       } else {
//         print('Login failed: ${response.body}');
//         return false;
//       }
//     } catch (e) {
//       print('Login error: $e');
//       return false;
//     }
//   }

//   // Refresh access token
//   Future<bool> refreshAccessToken() async {
//     await _loadTokens();
//     if (refreshToken == null) return false;

//     try {
//       final response = await http.post(
//         Uri.parse('$baseUrl/token/refresh/'),
//         headers: {'Content-Type': 'application/json'},
//         body: json.encode({'refresh': refreshToken}),
//       );

//       if (response.statusCode == 200) {
//         final data = json.decode(response.body);
//         accessToken = data['access'];
//         await _saveTokens();
//         return true;
//       } else {
//         print('Refresh failed: ${response.body}');
//         return false;
//       }
//     } catch (e) {
//       print('Refresh error: $e');
//       return false;
//     }
//   }

//   // Check if user is logged in
//   Future<bool> isLoggedIn() async {
//     await _loadTokens();
//     return accessToken != null;
//   }

//   // Logout user
//   Future<void> logout() async {
//     await _clearTokens();
//     accessToken = null;
//     refreshToken = null;
//   }
// }
