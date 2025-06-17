import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:convert';
import 'auth/auth_service.dart';

class MyHomePage extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onLogout;
  final String title;

  const MyHomePage({
    super.key,
    required this.title,
    required this.authService,
    required this.onLogout,
  });

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with SingleTickerProviderStateMixin {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  final FlutterTts _tts = FlutterTts();
  bool _isRecording = false;
  bool _isRecorderReady = false;
  bool _isPlayerReady = false;
  bool _enableTts = true;
  String _status = 'Initializing...';
  String? _filePath;
  late AnimationController _animationController;
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _showSidebar = false;
  double _recordingDuration = 0;
  Timer? _recordingTimer;
  String _selectedLanguage = 'lug';
  final List<Map<String, String>> _languages = [
    {'code': 'lug', 'name': 'Luganda'},
    {'code': 'lgg', 'name': 'Lugbara'},
    {'code': 'nyn', 'name': 'Runyankore'},
    {'code': 'ach', 'name': 'Acholi'},
    {'code': 'teo', 'name': 'Ateso'},
  ];

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _initPlayer();
    _loadMessages();
    _initTts();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    debugPrint('Initializing MyHomePage');
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _animationController.dispose();
    _scrollController.dispose();
    if (_recorder.isRecording) {
      _recorder.stopRecorder().then((_) => _recorder.closeRecorder());
    } else {
      _recorder.closeRecorder();
    }
    if (_player.isPlaying) {
      _player.stopPlayer().then((_) => _player.closePlayer());
    } else {
      _player.closePlayer();
    }
    _tts.stop();
    super.dispose();
  }

  Future<void> _initRecorder() async {
    try {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        setState(() {
          _status = 'Microphone permission denied';
          _isRecorderReady = false;
        });
        return;
      }

      await _recorder.openRecorder();
      setState(() {
        _isRecorderReady = true;
        _status = 'Ready to record';
      });
      await _cleanupOldRecordings();
    } catch (e) {
      setState(() {
        _status = 'Failed to initialize recorder: $e';
        _isRecorderReady = false;
      });
      debugPrint('Recorder initialization error: $e');
    }
  }

  Future<void> _initPlayer() async {
    try {
      await _player.openPlayer();
      setState(() {
        _isPlayerReady = true;
      });
    } catch (e) {
      setState(() {
        _isPlayerReady = false;
      });
      debugPrint('Player initialization error: $e');
    }
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US'); // Fallback language
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(0.0);
      await _tts.setPitch(0.0);
    } catch (e) {
      debugPrint('TTS initialization error: $e');
    }
  }

  Future<void> _cleanupOldRecordings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory.listSync();
      for (final file in files) {
        if (file.path.endsWith('.aac') || file.path.endsWith('.wav')) {
          if (file is File) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up old recordings: $e');
    }
  }

  Future<void> _loadMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = prefs.getString('messages');
      if (messagesJson != null) {
        final List<dynamic> decoded = json.decode(messagesJson);
        setState(() {
          _messages.clear();
          _messages.addAll(
            decoded.map(
              (m) => ChatMessage(
                text: m['text'],
                isResponse: m['isResponse'],
                timestamp: DateTime.parse(m['timestamp']),
              ),
            ),
          );
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        });
      }
    } catch (e) {
      debugPrint('Error loading messages: $e');
    }
  }

  Future<void> _saveMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = _messages
          .map(
            (m) => {
              'text': m.text,
              'isResponse': m.isResponse,
              'timestamp': m.timestamp.toIso8601String(),
            },
          )
          .toList();
      await prefs.setString('messages', json.encode(messagesJson));
    } catch (e) {
      debugPrint('Error saving messages: $e');
    }
  }

  void _startRecordingTimer() {
    _recordingDuration = 0;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration++;
      });
    });
  }

  Future<void> _startRecording() async {
    if (!_isRecorderReady) {
      await _initRecorder();
      if (!_isRecorderReady) return;
    }

    try {
      final directory = await getApplicationDocumentsDirectory();
      _filePath =
          '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.aac';
      await _recorder.startRecorder(toFile: _filePath, codec: Codec.aacADTS);
      setState(() {
        _isRecording = true;
        _status = 'Recording...';
        _recordingDuration = 0;
      });
      _animationController.repeat(reverse: true);
      _startRecordingTimer();
    } catch (e) {
      _recordingTimer?.cancel();
      setState(() {
        _status = 'Error starting recording: $e';
      });
      debugPrint('Recording start error: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      _recordingTimer?.cancel();
      _animationController.stop();
      await _recorder.stopRecorder();
      setState(() {
        _isRecording = false;
        _status = 'Ready to record';
      });
      _addMessage('Recording saved (${_recordingDuration}s)', false);
    } catch (e) {
      _recordingTimer?.cancel();
      setState(() {
        _status = 'Error stopping recording: $e';
      });
      debugPrint('Recording stop error: $e');
    }
  }

  Future<void> _sendRecording() async {
    if (_filePath == null) return;

    setState(() {
      _status = 'Sending recording...';
      _addMessage('Sending recording...', false);
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final responseBody = await _uploadRecording(
        widget.authService.accessToken,
      );
      Navigator.pop(context);
      setState(() {
        _status = 'Recording processed successfully';
        _addMessage('Server response: $responseBody', true);
      });
      if (_enableTts) {
        await _convertTextToSpeech(responseBody);
      }
    } catch (e) {
      Navigator.pop(context);
      setState(() {
        _status = 'Error sending recording: $e';
        _addMessage('Error: $e', true);
      });
      debugPrint('Error sending recording: $e');
    }
  }

  Future<String> _uploadRecording(String? accessToken) async {
    final file = File(_filePath!);
    final bytes = await file.readAsBytes();
    final uri = Uri.parse(
      'https://chapkat-backend.onrender.com/api/audio-process/',
      // 'https://bengieantony.pythonanywhere.com/api/audio-process/',
    );
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..fields['language'] = _selectedLanguage
      ..files.add(
        http.MultipartFile.fromBytes('audio', bytes, filename: 'recording.aac'),
      );

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      return responseBody;
    } else if (response.statusCode == 401) {
      final refreshed = await widget.authService.refreshAccessToken();
      if (refreshed && widget.authService.accessToken != null) {
        final newRequest = http.MultipartRequest('POST', uri)
          ..headers['Authorization'] =
              'Bearer ${widget.authService.accessToken}'
          ..fields['language'] = _selectedLanguage
          ..files.add(
            http.MultipartFile.fromBytes(
              'audio',
              bytes,
              filename: 'recording.aac',
            ),
          );
        final newResponse = await newRequest.send();
        final newResponseBody = await newResponse.stream.bytesToString();
        if (newResponse.statusCode == 200) {
          return newResponseBody;
        } else {
          _handleErrorResponse(newResponse.statusCode, newResponseBody);
          throw Exception('Failed to process recording after token refresh');
        }
      } else {
        _handleSessionExpired();
        throw Exception('Session expired and token refresh failed');
      }
    } else {
      _handleErrorResponse(response.statusCode, responseBody);
      throw Exception('Failed to process recording');
    }
  }

  Future<void> _convertTextToSpeech(String text) async {
    setState(() {
      _status = 'Converting response to speech...';
      _addMessage('Converting response to speech...', false);
    });

    try {
      final uri = Uri.parse('https://bengieantony.pythonanywhere.com/api/tts/');
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer ${widget.authService.accessToken}',
          'Content-Type': 'application/json',
        },
        body: json.encode({'text': text, 'language': _selectedLanguage}),
      );

      if (response.statusCode == 200) {
        final audioPath = await _saveAudioResponse(response.bodyBytes);
        setState(() {
          _status = 'Text-to-speech successful';
          _addMessage('Response converted to speech', true);
        });
        if (_isPlayerReady) {
          await _player.startPlayer(fromURI: audioPath);
        } else {
          throw Exception('Player not initialized');
        }
      } else if (response.statusCode == 401) {
        final refreshed = await widget.authService.refreshAccessToken();
        if (refreshed && widget.authService.accessToken != null) {
          final newResponse = await http.post(
            uri,
            headers: {
              'Authorization': 'Bearer ${widget.authService.accessToken}',
              'Content-Type': 'application/json',
            },
            body: json.encode({'text': text, 'language': _selectedLanguage}),
          );
          if (newResponse.statusCode == 200) {
            final audioPath = await _saveAudioResponse(newResponse.bodyBytes);
            setState(() {
              _status = 'Text-to-speech successful';
              _addMessage('Response converted to speech', true);
            });
            if (_isPlayerReady) {
              await _player.startPlayer(fromURI: audioPath);
            } else {
              throw Exception('Player not initialized');
            }
          } else {
            _handleErrorResponse(newResponse.statusCode, newResponse.body);
            throw Exception('TTS failed after token refresh');
          }
        } else {
          _handleSessionExpired();
          throw Exception('Session expired and token refresh failed');
        }
      } else {
        _handleErrorResponse(response.statusCode, response.body);
        throw Exception('TTS failed');
      }
    } catch (e) {
      try {
        await _tts.speak(text);
        setState(() {
          _status = 'Text-to-speech successful (fallback)';
          _addMessage('Response converted to speech (fallback)', true);
        });
      } catch (ttsError) {
        setState(() {
          _status = 'Error converting text to speech: $ttsError';
          _addMessage('TTS Error: $ttsError', true);
        });
        debugPrint('TTS error: $ttsError');
      }
    }
  }

  Future<String> _saveAudioResponse(List<int> bytes) async {
    final directory = await getApplicationDocumentsDirectory();
    final audioPath =
        '${directory.path}/tts_output_${DateTime.now().millisecondsSinceEpoch}.wav';
    final file = File(audioPath);
    await file.writeAsBytes(bytes);
    return audioPath;
  }

  void _handleErrorResponse(int statusCode, String responseBody) {
    setState(() {
      _status = 'Failed to process request. Status: $statusCode';
      _addMessage('Error: $statusCode - $responseBody', true);
    });
  }

  void _handleSessionExpired() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session Expired'),
        content: const Text('Your session has expired. Please log in again.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onLogout();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _addMessage(String text, bool isResponse) {
    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          isResponse: isResponse,
          timestamp: DateTime.now(),
        ),
      );
    });
    _saveMessages();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _toggleSidebar() {
    setState(() {
      _showSidebar = !_showSidebar;
    });
  }

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    return '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.of(context).size.width > 600;
    final sidebarWidth = isLargeScreen
        ? 300.0
        : MediaQuery.of(context).size.width * 0.7;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: widget.onLogout,
          ),
        ],
      ),
      body: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            left: _showSidebar ? sidebarWidth : 0,
            right: _showSidebar ? -sidebarWidth : 0,
            top: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    children: [
                      if (_isRecording)
                        ScaleTransition(
                          scale: Tween(begin: 0.8, end: 1.2).animate(
                            CurvedAnimation(
                              parent: _animationController,
                              curve: Curves.easeInOut,
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.mic,
                                size: 80,
                                color: Colors.red,
                              ),
                              Text(
                                _formatDuration(_recordingDuration),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (_filePath != null)
                        const Icon(
                          Icons.audio_file,
                          size: 80,
                          color: Colors.blue,
                        )
                      else
                        const Icon(
                          Icons.mic_none,
                          size: 80,
                          color: Colors.grey,
                        ),
                      const SizedBox(height: 20),
                      Text(
                        _status,
                        style: const TextStyle(fontSize: 18),
                        textAlign: TextAlign.center,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("Select Language: "),
                            const SizedBox(width: 10),
                            DropdownButton<String>(
                              value: _selectedLanguage,
                              items: _languages
                                  .map(
                                    (lang) => DropdownMenuItem(
                                      value: lang['code'],
                                      child: Text(lang['name']!),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _selectedLanguage = value;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      SwitchListTile(
                        title: const Text(
                          'Enable Text-to-Speech for Responses',
                        ),
                        value: _enableTts,
                        onChanged: (value) {
                          setState(() {
                            _enableTts = value;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Expanded(
                    child: _messages.isEmpty
                        ? const Center(
                            child: Text(
                              'No recordings yet',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message =
                                  _messages[_messages.length - 1 - index];
                              return ChatBubble(
                                text: message.text,
                                isResponse: message.isResponse,
                                timestamp: message.timestamp,
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FloatingActionButton(
                          onPressed: _isRecording
                              ? _stopRecording
                              : (_isRecorderReady ? _startRecording : null),
                          backgroundColor: _isRecording
                              ? Colors.red
                              : (_isRecorderReady ? Colors.blue : Colors.grey),
                          child: Icon(
                            _isRecording ? Icons.stop : Icons.mic,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 20),
                        if (_filePath != null && !_isRecording)
                          FloatingActionButton(
                            onPressed: _sendRecording,
                            backgroundColor: Colors.green,
                            child: const Icon(Icons.send, color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showSidebar)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              left: 0,
              top: 0,
              bottom: 0,
              width: sidebarWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Text(
                            'Recording History',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: _toggleSidebar,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _messages.isEmpty
                          ? const Center(
                              child: Text(
                                'No recordings yet',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final message =
                                    _messages[_messages.length - 1 - index];
                                return ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: message.isResponse
                                          ? Colors.green.withOpacity(0.2)
                                          : Colors.blue.withOpacity(0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      message.isResponse
                                          ? Icons.reply
                                          : Icons.mic,
                                      color: message.isResponse
                                          ? Colors.green
                                          : Colors.blue,
                                    ),
                                  ),
                                  title: Text(message.text),
                                  subtitle: Text(
                                    '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleSidebar,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(
          _showSidebar ? Icons.close : Icons.history,
          color: Colors.white,
        ),
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isResponse;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isResponse,
    required this.timestamp,
  });
}

class ChatBubble extends StatelessWidget {
  final String text;
  final bool isResponse;
  final DateTime timestamp;

  const ChatBubble({
    super.key,
    required this.text,
    required this.isResponse,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isResponse ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isResponse
              ? Colors.green.withOpacity(0.1)
              : Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isResponse ? Colors.green : Colors.blue,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(color: isResponse ? Colors.green : Colors.blue),
            ),
            const SizedBox(height: 4),
            Text(
              '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
