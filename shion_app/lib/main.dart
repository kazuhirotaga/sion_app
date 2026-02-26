import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ui/eyes_screen.dart';
import 'services/ai_service.dart';
import 'services/voice_service.dart';
import 'services/vision_service.dart';
import 'services/ble_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AiService()),
        ChangeNotifierProvider(create: (_) => VoiceService()),
        ChangeNotifierProvider(create: (_) => VisionService()),
        ChangeNotifierProvider(create: (_) => BleService()),
      ],
      child: const ShionApp(),
    ),
  );
}

class ShionApp extends StatelessWidget {
  const ShionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const BootScreen(),
    );
  }
}

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  String _status = "INITIALIZING SYSTEM...";
  bool _needsBackendUrl = false;
  final TextEditingController _backendUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    setState(() => _status = "INITIALIZING SERVICES...");
    final aiService = context.read<AiService>();
    final voiceService = context.read<VoiceService>();

    await aiService.initialize();
    await voiceService.initialize();

    setState(() => _status = "REQUESTING SENSORY ACCESS...");
    await [
      Permission.camera,
      Permission.microphone,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (!aiService.hasBackendUrl) {
      setState(() {
        _needsBackendUrl = true;
        _status = "AWAITING BACKEND URL...";
      });
      return;
    }

    _finishBoot();
  }

  void _finishBoot() async {
    setState(() {
      _needsBackendUrl = false;
      _status = "SYSTEM READY. AWAKENING SHION.";
    });

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const EyesScreen()));
    }
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_needsBackendUrl)
                const CircularProgressIndicator(color: Colors.cyan),
              const SizedBox(height: 24),
              Text(
                _status,
                style: const TextStyle(
                  color: Colors.cyan,
                  fontFamily: 'Courier',
                  letterSpacing: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              if (_needsBackendUrl) ...[
                const SizedBox(height: 32),
                TextField(
                  controller: _backendUrlController,
                  decoration: const InputDecoration(
                    labelText: "Backend URL",
                    labelStyle: TextStyle(color: Colors.cyan),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.cyan),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.cyanAccent),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  obscureText: false,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    if (_backendUrlController.text.isNotEmpty) {
                      context.read<AiService>().saveBackendUrl(
                        _backendUrlController.text,
                      );
                      _finishBoot();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan.withOpacity(0.3),
                  ),
                  child: const Text(
                    "Save & Continue",
                    style: TextStyle(color: Colors.cyanAccent),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
