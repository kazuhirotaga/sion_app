import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ai_service.dart';
import '../services/contact_service.dart';
import '../services/vision_service.dart';
import '../services/voice_service.dart';

class EyesScreen extends StatefulWidget {
  const EyesScreen({super.key});

  @override
  State<EyesScreen> createState() => _EyesScreenState();
}

class _EyesScreenState extends State<EyesScreen> with TickerProviderStateMixin {
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  double _lookX = 0.0;
  double _lookY = 0.0;

  Timer? _behaviorTimer;
  Timer? _financeTimer;
  final Random _random = Random();
  String? _lastFinanceTimestamp;

  bool _isProcessingAi = false;

  @override
  void initState() {
    super.initState();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _blinkAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );

    _startBehaviorLoop();
    _startFinancePolling();
  }

  void _startBehaviorLoop() {
    _behaviorTimer = Timer.periodic(const Duration(milliseconds: 2000), (
      timer,
    ) {
      if (!mounted) return;

      final voiceService = context.read<VoiceService>();

      // If speaking or processing, change behavior
      if (voiceService.isSpeaking) {
        // Look around slightly more while talking
        if (_random.nextBool()) _lookAround(0.3);
        if (_random.nextInt(10) < 2) _blink();
        return;
      }

      int action = _random.nextInt(10);
      if (action < 3) {
        _blink();
      } else if (action < 8) {
        _lookAround(1.0);
      } else {
        setState(() {
          _lookX = 0;
          _lookY = 0;
        });
      }
    });
  }

  Future<void> _blink() async {
    if (!mounted) return;
    await _blinkController.forward();
    await _blinkController.reverse();
  }

  void _lookAround(double intensity) {
    if (!mounted) return;
    setState(() {
      _lookX = ((_random.nextDouble() * 2) - 1) * intensity;
      _lookY = ((_random.nextDouble() * 2) - 1) * intensity;
    });

    if (_random.nextBool()) {
      Future.delayed(const Duration(milliseconds: 300), _blink);
    }
  }

  void _onMicPressed(
    VoiceService voiceService,
    AiService aiService,
    VisionService visionService,
  ) async {
    if (voiceService.isListening) {
      await voiceService.stopListening();
    } else {
      await voiceService.startListening(
        onResult: (text) async {
          if (text.isEmpty) return;

          setState(() {
            _isProcessingAi = true;
            // "Thinking" eye position
            _lookX = 0.0;
            _lookY = -0.5;
          });

          final response = await aiService.sendMessage(text);

          // Check action type BEFORE setState
          final String action = response['action'] as String? ?? 'none';
          final bool isCaptureImage = (action == 'capture_image');
          final bool isMakeCall = (action == 'make_call');

          setState(() {
            _isProcessingAi = false;

            // アクションに基づく簡易的な目の動き
            if (action == 'nod') {
              _lookY = 0.5; // 下を見る
            } else if (action == 'shake') {
              _lookX = 0.5; // 横を見る
            } else if (action == 'tilt') {
              _lookX = -0.3;
              _lookY = -0.3;
            } else {
              _lookX = 0.0;
              _lookY = 0.0;
            }
          });

          if (isCaptureImage) {
            // Handle image capture OUTSIDE setState so async/await works properly
            final String introText = response['text'] as String? ?? "";
            await _handleImageCapture(
              visionService,
              aiService,
              voiceService,
              introText,
            );
          } else if (isMakeCall) {
            // Handle phone call OUTSIDE setState
            final String introText = response['text'] as String? ?? "";
            final String callTarget = response['call_target'] as String? ?? "";
            final contactService = context.read<ContactService>();
            await _handleMakeCall(
              contactService,
              voiceService,
              introText,
              callTarget,
            );
          } else {
            // 発話 (通常のアクション)
            final String replyText = response['text'] as String? ?? "";
            if (replyText.isNotEmpty) {
              await voiceService.speak(replyText);
            }
          }
        },
      );
    }
  }

  Future<void> _handleMakeCall(
    ContactService contactService,
    VoiceService voiceService,
    String introText,
    String callTarget,
  ) async {
    print("EyesScreen: _handleMakeCall START, target='$callTarget'");
    if (!mounted) return;

    // Speak the intro (e.g., "お母さんに電話しますね")
    if (introText.isNotEmpty) {
      await voiceService.speak(introText);
    }

    if (callTarget.isEmpty) {
      await voiceService.speak("電話する相手の名前が分かりませんでした。");
      return;
    }

    // Search contact
    final contact = await contactService.searchContact(callTarget);
    if (contact != null) {
      final name = contact['name']!;
      final phone = contact['phone']!;
      await voiceService.speak("$nameさんに電話をかけます。");
      await contactService.makeCall(phone);
    } else {
      await voiceService.speak("$callTargetさんの連絡先が見つかりませんでした。");
    }
    print("EyesScreen: _handleMakeCall END");
  }

  Future<void> _handleImageCapture(
    VisionService visionService,
    AiService aiService,
    VoiceService voiceService,
    String introText,
  ) async {
    print("EyesScreen: _handleImageCapture START");
    if (!mounted) return;

    if (introText.isNotEmpty) {
      await voiceService.speak(introText);
    }

    // Capture image
    print("EyesScreen: Calling visionService.captureImageBase64...");
    String base64Image;
    try {
      base64Image = await visionService.captureImageBase64();
    } catch (e) {
      print("EyesScreen Capture Error: $e");
      // Read the error directly through TTS so the user can hear the exact exception!
      await voiceService.speak("キャプチャーエラー。$e");

      // Tell the AI that it failed so it can apologize via text/history
      await aiService.sendMessage("システムエラー：$e");
      return;
    }

    if (!mounted) return;
    setState(() {
      _isProcessingAi = true;
      _lookX = 0.0;
      _lookY = -0.5;
    });
    // Send the image directly back to AI
    print("EyesScreen: Sending image to AI Backend...");
    final response = await aiService.sendMessage(
      "画像を取得しました。",
      imageBase64: base64Image,
    );
    print("EyesScreen: Received response from AI Backend.");

    if (!mounted) return;
    setState(() {
      _isProcessingAi = false;
      final String action = response['action'] as String? ?? 'none';
      if (action == 'nod') {
        _lookY = 0.5;
      } else if (action == 'shake') {
        _lookX = 0.5;
      } else {
        _lookX = 0.0;
        _lookY = 0.0;
      }
    });

    final String replyText = response['text'] as String? ?? "";
    if (replyText.isNotEmpty) {
      print("EyesScreen: Speaking reply '$replyText'");
      await voiceService.speak(replyText);
    }

    print("EyesScreen: _handleImageCapture END");
  }

  @override
  Widget build(BuildContext context) {
    final voiceService = context.watch<VoiceService>();
    final aiService = context.read<AiService>();
    final visionService = context.read<VisionService>();

    // Determine eye color and shape based on state
    Color eyeColor = Colors.cyan;
    double scaleY = _blinkAnimation.value;

    if (voiceService.isListening) {
      eyeColor = Colors.greenAccent; // Listening
      scaleY = scaleY * 1.1; // Wide eyes
    } else if (_isProcessingAi) {
      eyeColor = Colors.amber; // Thinking
      scaleY = scaleY * 0.7; // squinting
    } else if (voiceService.isSpeaking) {
      eyeColor = Colors.cyanAccent;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildEye(eyeColor, scaleY),
                const SizedBox(width: 80),
                _buildEye(eyeColor, scaleY),
              ],
            ),
          ),

          // Debug/Speech Text overlay
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Text(
              voiceService.lastRecognizedWords,
              style: const TextStyle(color: Colors.white54, fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ),

          // Mic Button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onLongPress: () {
                  aiService.clearHistory();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Memory cleared')),
                  );
                },
                child: FloatingActionButton(
                  backgroundColor: voiceService.isListening
                      ? Colors.green
                      : Colors.cyan.withOpacity(0.3),
                  onPressed: () =>
                      _onMicPressed(voiceService, aiService, visionService),
                  child: Icon(
                    voiceService.isListening ? Icons.mic : Icons.mic_none,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEye(Color color, double animScale) {
    return Transform.scale(
      scaleY: animScale,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 120,
        height: 180,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(60),
          border: Border.all(color: color.withOpacity(0.5), width: 4),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack,
              left: 60 - 25 + (_lookX * 30),
              top: 90 - 25 + (_lookY * 45),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: color, blurRadius: 10, spreadRadius: 2),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startFinancePolling() {
    // Poll every 3 minutes for new financial analysis
    _financeTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      _pollFinanceAnalysis();
    });
    // Also poll once shortly after startup (30 seconds delay)
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) _pollFinanceAnalysis();
    });
  }

  Future<void> _pollFinanceAnalysis() async {
    if (!mounted) return;
    // Skip if user is speaking or AI is processing
    final voiceService = context.read<VoiceService>();
    final aiService = context.read<AiService>();
    if (_isProcessingAi ||
        voiceService.isListening ||
        voiceService.isSpeaking) {
      print("EyesScreen: Skipping finance poll (busy)");
      return;
    }

    try {
      final analysis = await aiService.fetchLatestAnalysis();
      if (analysis == null) return;

      final timestamp = analysis['timestamp'] as String? ?? '';
      if (timestamp == _lastFinanceTimestamp) return; // Already announced

      _lastFinanceTimestamp = timestamp;
      final speechSummary = analysis['speech_summary'] as String? ?? '';
      if (speechSummary.isEmpty) return;

      print("EyesScreen: Announcing finance report: $speechSummary");
      if (!mounted) return;
      await voiceService.speak("市場レポートです。$speechSummary");
    } catch (e) {
      print("EyesScreen: Finance poll error: $e");
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    _behaviorTimer?.cancel();
    _financeTimer?.cancel();
    super.dispose();
  }
}
