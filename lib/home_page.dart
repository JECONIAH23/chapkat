import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_tts/flutter_tts.dart';

// Database setup
late Database _database;

Future<void> initDatabase() async {
  _database = await openDatabase(
    join(await getDatabasesPath(), 'voice_records.db'),
    onCreate: (db, version) {
      return db.execute('''
        CREATE TABLE recordings(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          file_path TEXT,
          language TEXT,
          status TEXT,
          transcript TEXT,
          created_at TEXT,
          uploaded_at TEXT
        )
        ''');
    },
    version: 1,
  );
}

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    await _syncPendingRecordings();
    return true;
  });
}

Future<void> _syncPendingRecordings() async {
  final pending = await _database.query(
    'recordings',
    where: 'status = ?',
    whereArgs: ['pending'],
  );

  for (final record in pending) {
    try {
      final file = File(record['file_path'] as String);
      if (await file.exists()) {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse(
            'https://2e0e-41-210-154-141.ngrok-free.app/api/voicebook/api/audio/',
          ),
        );

        request.files.add(
          await http.MultipartFile.fromPath('audio_file', file.path),
        );
        request.fields['language'] = record['language'] as String;

        final response = await http.Response.fromStream(await request.send());

        if (response.statusCode == 200) {
          final jsonResponse = json.decode(response.body);
          await _database.update(
            'recordings',
            {
              'status': 'uploaded',
              'uploaded_at': DateTime.now().toIso8601String(),
              'transcript': jsonResponse['transcription'] ?? '',
            },
            where: 'id = ?',
            whereArgs: [record['id']],
          );
        }
      }
    } catch (e) {
      debugPrint('Sync error: $e');
    }
  }
}

// Future<void> _syncPendingRecordings() async {
//   final pending = await _database.query(
//     'recordings',
//     where: 'status = ?',
//     whereArgs: ['pending'],
//   );

//   for (final record in pending) {
//     try {
//       final file = File(record['file_path'] as String);
//       if (await file.exists()) {
//         final bytes = await file.readAsBytes();

//         final response = await http.post(
//           Uri.parse(
//             ' https://2e0e-41-210-154-141.ngrok-free.app/api/voicebook/api/audio/',
//           ),
//           body: {
//             'audio': base64Encode(bytes),
//             'language': record['language'] as String,
//           },
//         );

//         if (response.statusCode == 200) {
//           await _database.update(
//             'recordings',
//             {
//               'status': 'uploaded',
//               'uploaded_at': DateTime.now().toIso8601String(),
//               'transcript': response.body,
//             },
//             where: 'id = ?',
//             whereArgs: [record['id']],
//           );
//         }
//       }
//     } catch (e) {
//       debugPrint('Sync error: $e');
//     }
//   }
// }

class HomePage extends StatefulWidget {
  final String title;
  const HomePage({super.key, required this.title});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
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
  List<Map<String, dynamic>> _recordings = [];
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _initPlayer();
    _initTts();
    _loadRecordings();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Setup background sync
    Workmanager().initialize(callbackDispatcher);
    Workmanager().registerPeriodicTask(
      "syncTask",
      "syncRecordings",
      frequency: const Duration(minutes: 15),
    );

    // Check connectivity on startup
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity != ConnectivityResult.none) {
      await _syncPendingRecordings();
      _loadRecordings(); // Refresh list after sync
    }
  }

  Future<void> _loadRecordings() async {
    final records = await _database.query(
      'recordings',
      orderBy: 'created_at DESC',
    );
    setState(() => _recordings = records);
  }

  Future<void> _initRecorder() async {
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        setState(() => _status = 'Microphone permission denied');
        return;
      }

      await _recorder.openRecorder();
      setState(() {
        _isRecorderReady = true;
        _status = 'Ready to record';
      });
    } catch (e) {
      setState(() => _status = 'Recorder init failed: $e');
    }
  }

  // Future<void> _initPlayer() async {
  //   try {
  //     await _player.openPlayer();
  //     setState(() => _isPlayerReady = true);
  //   } catch (e) {
  //     debugPrint('Player init error: $e');
  //   }
  // }
  Future<void> _initPlayer() async {
    try {
      await _player.openPlayer();
      setState(() => _isPlayerReady = true);
    } catch (e) {
      debugPrint('Player init error: $e');
      setState(() => _isPlayerReady = false);
    }
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
    } catch (e) {
      debugPrint('TTS init error: $e');
    }
  }

  void _startRecordingTimer() {
    _recordingDuration = 0;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _recordingDuration++);
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
      _animationController.repeat(reverse: true);
      _startRecordingTimer();
    } catch (e) {
      setState(() => _status = 'Recording error: $e');
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();
    _animationController.stop();

    try {
      await _recorder.stopRecorder();
      setState(() {
        _isRecording = false;
        _status = 'Recording saved';
      });
      await _saveRecording();
    } catch (e) {
      setState(() => _status = 'Stop recording error: $e');
    }
  }

  Future<void> _saveRecording() async {
    if (_filePath == null) return;

    await _database.insert('recordings', {
      'file_path': _filePath,
      'language': _selectedLanguage,
      'status': 'pending',
      'transcript': '',
      'created_at': DateTime.now().toIso8601String(),
      'uploaded_at': null,
    });

    _loadRecordings(); // Refresh list
    await _checkConnectivity(); // Try to sync immediately
  }

  // Future<void> _playRecording(String filePath) async {
  //   try {
  //     await _player.startPlayer(fromURI: filePath);
  //   } catch (e) {
  //     debugPrint('Playback error: $e');
  //     ScaffoldMessenger.of(context as BuildContext).showSnackBar(
  //       SnackBar(content: Text('Playback failed: ${e.toString()}')),
  //     );
  //   }
  // }
  Future<void> _playRecording(String filePath) async {
    if (!_isPlayerReady) {
      ScaffoldMessenger.of(
        context as BuildContext,
      ).showSnackBar(const SnackBar(content: Text('Player is not ready yet')));
      return;
    }

    try {
      await _player.startPlayer(fromURI: filePath);
    } catch (e) {
      debugPrint('Playback error: $e');
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Playback failed: ${e.toString()}')),
      );
    }
  }

  Future<void> _processRecording(String filePath) async {
    setState(() => _status = 'Processing...');

    try {
      final file = File(filePath);
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          'https://2e0e-41-210-154-141.ngrok-free.app/api/voicebook/api/audio/',
        ),
      );

      request.files.add(
        await http.MultipartFile.fromPath('audio_file', file.path),
      );
      request.fields['language'] = _selectedLanguage;

      final response = await http.Response.fromStream(await request.send());

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        final transcription = jsonResponse['transcription'] ?? 'Empty Transcription';

        await _database.update(
          'recordings',
          {
            'status': 'uploaded',
            'uploaded_at': DateTime.now().toIso8601String(),
            'transcript': transcription,
          },
          where: 'file_path = ?',
          whereArgs: [filePath],
        );

        setState(() => _status = 'Processing complete');
        if (_enableTts && transcription.isNotEmpty) {
          await _tts.speak(transcription);
        }
        _loadRecordings();
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _status = 'Processing failed');
      debugPrint('Processing error: $e');
    }
  }

  // Future<void> _processRecording(String filePath) async {
  //   setState(() => _status = 'Processing...');

  //   try {
  //     final file = File(filePath);
  //     final bytes = await file.readAsBytes();

  //     final response = await http.post(
  //       Uri.parse('https://your-api-endpoint.com/audio-process'),
  //       body: {'audio': base64Encode(bytes), 'language': _selectedLanguage},
  //     );

  //     if (response.statusCode == 200) {
  //       await _database.update(
  //         'recordings',
  //         {
  //           'status': 'uploaded',
  //           'uploaded_at': DateTime.now().toIso8601String(),
  //           'transcript': response.body,
  //         },
  //         where: 'file_path = ?',
  //         whereArgs: [filePath],
  //       );

  //       setState(() => _status = 'Processing complete');
  //       if (_enableTts) {
  //         await _tts.speak(response.body);
  //       }
  //       _loadRecordings();
  //     } else {
  //       throw Exception('Server error: ${response.statusCode}');
  //     }
  //   } catch (e) {
  //     setState(() => _status = 'Processing failed');
  //     debugPrint('Processing error: $e');
  //   }
  // }

  String _formatDuration(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    return '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _animationController.dispose();
    _recorder.closeRecorder();
    _player.closePlayer();
    _tts.stop();
    _player.closePlayer();
    setState(() => _isPlayerReady = false); // Add this
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => setState(() => _showHistory = !_showHistory),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _showHistory ? _buildHistoryView() : _buildMainView(),
          ),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildMainView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
                  const Icon(Icons.mic, size: 80, color: Colors.red),
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
          else
            const Icon(Icons.mic_none, size: 80, color: Colors.grey),

          const SizedBox(height: 20),
          Text(_status, style: const TextStyle(fontSize: 18)),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: DropdownButton<String>(
              value: _selectedLanguage,
              items: _languages
                  .map(
                    (lang) => DropdownMenuItem(
                      value: lang['code'],
                      child: Text(lang['name']!),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _selectedLanguage = value ?? 'lug'),
            ),
          ),

          SwitchListTile(
            title: const Text('Enable Text-to-Speech'),
            value: _enableTts,
            onChanged: (value) => setState(() => _enableTts = value),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryView() {
    return ListView.builder(
      itemCount: _recordings.length,
      itemBuilder: (context, index) {
        final record = _recordings[index];
        return ListTile(
          leading: Icon(
            record['status'] == 'uploaded' ? Icons.cloud_done : Icons.cloud_off,
            color: record['status'] == 'uploaded'
                ? Colors.green
                : Colors.orange,
          ),
          title: Text(record['transcript']?.toString() ?? 'No transcript'),
          subtitle: Text(
            '${record['language']} • ${_formatCreatedAt(record['created_at'])}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () => _playRecording(record['file_path'].toString()),
              ),
              if (record['status'] == 'pending')
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      _processRecording(record['file_path'].toString()),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FloatingActionButton(
            onPressed: _isRecording ? _stopRecording : _startRecording,
            backgroundColor: _isRecording ? Colors.red : Colors.blue,
            child: Icon(_isRecording ? Icons.stop : Icons.mic),
          ),
          if (_filePath != null && !_isRecording)
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: FloatingActionButton(
                onPressed: () => _processRecording(_filePath!),
                backgroundColor: Colors.green,
                child: const Icon(Icons.send),
              ),
            ),
        ],
      ),
    );
  }

  String _formatCreatedAt(String? isoDate) {
    if (isoDate == null) return '';
    final date = DateTime.parse(isoDate);
    return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
