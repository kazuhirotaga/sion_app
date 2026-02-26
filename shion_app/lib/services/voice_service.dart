import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceService extends ChangeNotifier {
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  bool _isSttInitialized = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  String _lastRecognizedWords = "";

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  String get lastRecognizedWords => _lastRecognizedWords;

  Future<void> initialize() async {
    _isSttInitialized = await _speechToText.initialize();

    // Setup TTS
    await _flutterTts.setLanguage("ja-JP");
    await _flutterTts.setSpeechRate(0.5); // Speed
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(
      1.2,
    ); // Slightly higher pitch for robot-like or character-like voice

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
    _isSpeaking = false;
    notifyListeners();
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    await stopListening();
    await _flutterTts.speak(text);
  }
}
