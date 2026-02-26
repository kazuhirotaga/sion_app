import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ai_service.dart';
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
  final Random _random = Random();

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

  void _onMicPressed(VoiceService voiceService, AiService aiService) async {
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

          setState(() {
            _isProcessingAi = false;

            // アクションに基づく簡易的な目の動き
            final String action = response['action'] as String? ?? 'none';
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

          // 発話
          final String replyText = response['text'] as String? ?? "";
          if (replyText.isNotEmpty) {
            await voiceService.speak(replyText);
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _behaviorTimer?.cancel();
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voiceService = context.watch<VoiceService>();
    final aiService = context.read<AiService>();

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
                  onPressed: () => _onMicPressed(voiceService, aiService),
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
}
