import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
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
  bool _isRecording = false;
  bool _isRecorderReady = false;
  String _status = 'Initializing...';
  String? _filePath;
  late AnimationController _animationController;
  final List<ChatMessage> _messages = [];
  bool _showSidebar = false;
  double _recordingDuration = 0;
  Timer? _recordingTimer;
  String _selectedLanguage = 'lug';

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    debugPrint('Initializing with token: ${widget.authService.accessToken}');
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _animationController.dispose();
    _recorder.closeRecorder();
    super.dispose();
  }

  Future<void> _initRecorder() async {
    try {
      final micStatus = await Permission.microphone.request();

      if (!micStatus.isGranted) {
        setState(() {
          _status = 'Microphone permission denied';
        });
        return;
      }

      await _recorder.openRecorder();
      setState(() {
        _isRecorderReady = true;
        _status = 'Ready to record';
      });
    } catch (e) {
      setState(() {
        _status = 'Failed to initialize recorder: $e';
      });
      debugPrint('Recorder initialization error: $e');
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
    if (!_isRecorderReady) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      _filePath =
          '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.aac';

      await _recorder.startRecorder(toFile: _filePath, codec: Codec.aacADTS);

      setState(() {
        _isRecording = true;
        _status = 'Recording...';
      });
      _startRecordingTimer();
    } catch (e) {
      setState(() {
        _status = 'Error starting recording: $e';
      });
      debugPrint('Recording start error: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      _recordingTimer?.cancel();
      await _recorder.stopRecorder();

      setState(() {
        _isRecording = false;
        _status = 'Recording stopped (${_recordingDuration}s)';
      });

      _addMessage('Recording saved (${_recordingDuration}s)', false);
    } catch (e) {
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

    try {
      final file = File(_filePath!);
      final bytes = await file.readAsBytes();

      final uri = Uri.parse(
        'https://bengieantony.pythonanywhere.com/api/audio-process/',
      );

      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${widget.authService.accessToken}'
        ..fields['language'] = _selectedLanguage
        ..files.add(
          http.MultipartFile.fromBytes(
            'audio',
            bytes,
            filename: 'recording.aac',
          ),
        );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        setState(() {
          _status = 'Recording processed successfully';
          _addMessage('Server response: $responseBody', true);
        });
      } else if (response.statusCode == 401) {
        final refreshed = await widget.authService.refreshAccessToken();

        if (refreshed && widget.authService.accessToken != null) {
          request.headers['Authorization'] =
              'Bearer ${widget.authService.accessToken}';
          final newResponse = await request.send();
          final newResponseBody = await newResponse.stream.bytesToString();

          if (newResponse.statusCode == 200) {
            setState(() {
              _status = 'Recording processed successfully';
              _addMessage('Server response: $newResponseBody', true);
            });
          } else {
            _handleErrorResponse(newResponse.statusCode, newResponseBody);
          }
        } else {
          _handleSessionExpired();
        }
      } else {
        _handleErrorResponse(response.statusCode, responseBody);
      }
    } catch (e) {
      setState(() {
        _status = 'Error sending recording: $e';
        _addMessage('Error: $e', true);
      });
      debugPrint('Error sending recording: $e');
    }
  }

  void _handleErrorResponse(int statusCode, String responseBody) {
    setState(() {
      _status = 'Failed to process recording. Status: $statusCode';
      _addMessage('Error: $statusCode - $responseBody', true);
    });
  }

  void _handleSessionExpired() {
    setState(() {
      _status = 'Session expired. Please login again.';
      _addMessage('Session expired', true);
    });
    widget.onLogout();
  }

  void _addMessage(String text, bool isResponse) {
    setState(() {
      _messages.insert(
        0,
        ChatMessage(
          text: text,
          isResponse: isResponse,
          timestamp: DateTime.now(),
        ),
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
            left: _showSidebar ? MediaQuery.of(context).size.width * 0.7 : 0,
            right: _showSidebar ? -MediaQuery.of(context).size.width * 0.7 : 0,
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
                              items: const [
                                DropdownMenuItem(
                                  value: 'lug',
                                  child: Text("Luganda"),
                                ),
                                DropdownMenuItem(
                                  value: 'lgg',
                                  child: Text("Lugbara"),
                                ),
                                DropdownMenuItem(
                                  value: 'nyn',
                                  child: Text("Runyankore"),
                                ),
                                DropdownMenuItem(
                                  value: 'ach',
                                  child: Text("Acholi"),
                                ),
                                DropdownMenuItem(
                                  value: 'teo',
                                  child: Text("Ateso"),
                                ),
                              ],
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
                            reverse: true,
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
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
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: MediaQuery.of(context).size.width * 0.7,
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
                                final message = _messages[index];
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
        margin: const EdgeInsets.symmetric(vertical: 4),
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
