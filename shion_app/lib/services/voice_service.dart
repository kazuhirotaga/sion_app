import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VoiceService extends ChangeNotifier {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isSttInitialized = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  String _lastRecognizedWords = "";

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  String get lastRecognizedWords => _lastRecognizedWords;

  Future<void> initialize() async {
    _isSttInitialized = await _speechToText.initialize();

    // Setup local TTS as fallback
    await _flutterTts.setLanguage("ja-JP");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.2);

    _flutterTts.setStartHandler(() {
      _isSpeaking = true;
      notifyListeners();
    });

    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
      notifyListeners();
    });

    _flutterTts.setErrorHandler((msg) {
      _isSpeaking = false;
      notifyListeners();
    });

    // AudioPlayer completion handler
    _audioPlayer.onPlayerComplete.listen((_) {
      _isSpeaking = false;
      notifyListeners();
    });
  }

  Future<void> startListening({required Function(String) onResult}) async {
    if (!_isSttInitialized) return;

    // Stop speaking if talking
    if (_isSpeaking) {
      await stopSpeaking();
    }

    _lastRecognizedWords = "";
    _isListening = true;
    notifyListeners();

    await _speechToText.listen(
      onResult: (SpeechRecognitionResult result) {
        _lastRecognizedWords = result.recognizedWords;
        notifyListeners();

        // If the user has stopped speaking and the result is final
        if (result.finalResult) {
          _isListening = false;
          notifyListeners();
          onResult(result.recognizedWords);
        }
      },
      localeId: 'ja_JP',
      listenFor: const Duration(seconds: 10),
      cancelOnError: true,
      partialResults: true,
    );
  }

  Future<void> stopListening() async {
    if (_isListening) {
      await _speechToText.stop();
      _isListening = false;
      notifyListeners();
    }
  }

  Future<void> stopSpeaking() async {
    await _flutterTts.stop();
    await _audioPlayer.stop();
    _isSpeaking = false;
    notifyListeners();
  }

  /// Get the backend URL from SharedPreferences
  Future<String?> _getBackendBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    String? url = prefs.getString('backend_url');
    if (url == null || url.isEmpty) return null;

    url = url.trim();
    if (!url.startsWith('http')) {
      url = 'https://$url';
    } else if (url.startsWith('http://') &&
        !url.contains('10.0.2.2') &&
        !url.contains('localhost') &&
        !url.contains('192.168.')) {
      url = url.replaceFirst('http://', 'https://');
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/chat')) {
      url = url.substring(0, url.length - 5);
    }
    return url;
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    await stopListening();

    // Try Gemini TTS first
    try {
      final baseUrl = await _getBackendBaseUrl();
      if (baseUrl != null) {
        final url = Uri.parse('$baseUrl/tts');
        print("VoiceService: Calling Gemini TTS...");

        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'text': text}),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          if (data['status'] == 'ok' && data['audio_base64'] != null) {
            final audioBytes = base64Decode(data['audio_base64']);

            // Save to temp file and play
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/shion_tts.wav');
            await tempFile.writeAsBytes(audioBytes);

            _isSpeaking = true;
            notifyListeners();

            await _audioPlayer.play(DeviceFileSource(tempFile.path));
            print("VoiceService: Playing Gemini TTS audio");
            return;
          }
        }
        print("VoiceService: Gemini TTS failed, falling back to local TTS");
      }
    } catch (e) {
      print("VoiceService: Gemini TTS error: $e, falling back to local TTS");
    }

    // Fallback to local flutter_tts
    await _flutterTts.speak(text);
  }
}
