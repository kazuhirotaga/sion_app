import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class VisionService extends ChangeNotifier {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  CameraController? get cameraController => _cameraController;

  Future<void> initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        debugPrint('No cameras found.');
        return;
      }

      // Try to find the front camera for face tracking
      final frontCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset
            .low, // Use low resolution for tracking to save processing power
        enableAudio: false,
      );

      await _cameraController!.initialize();
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  void startFaceTracking() {
    if (!_isInitialized || _cameraController == null) return;

    // In Phase 2, we will use Google ML Kit or similar for face tracking.
    // For now, we will just start the image stream.
    if (!(_cameraController!.value.isStreamingImages)) {
      _cameraController!.startImageStream((image) {
        // Process image here later
        // debugPrint('Received image frame for processing');
      });
    }
  }

  void stopFaceTracking() {
    if (_cameraController?.value.isStreamingImages ?? false) {
      _cameraController?.stopImageStream();
    }
  }

  Future<String> captureImageBase64() async {
    print("VisionService: captureImageBase64 START");
    if (!_isInitialized || _cameraController == null) {
      print("VisionService: Camera not initialized!");
      throw Exception("VISION_ERROR: Camera not initialized");
    }

    try {
      bool wasStreaming = _cameraController!.value.isStreamingImages;
      print("VisionService: wasStreaming=$wasStreaming");

      if (wasStreaming) {
        print("VisionService: stopping image stream...");
        await _cameraController!.stopImageStream();
        print("VisionService: sleeping 500ms...");
        await Future.delayed(const Duration(milliseconds: 500));
      }

      print("VisionService: calling takePicture with 5s timeout...");
      // Add a timeout because some Android devices randomly deadlock on takePicture()
      final XFile file = await _cameraController!.takePicture().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print("VisionService: takePicture TIMED OUT! Throwing exception.");
          throw Exception("Camera capture timed out");
        },
      );

      print("VisionService: reading bytes...");
      final bytes = await file.readAsBytes();
      print("VisionService: encoding base64...");
      final base64String = base64Encode(bytes);

      if (wasStreaming) {
        print("VisionService: restarting face tracking...");
        startFaceTracking();
      }

      print("VisionService: capture complete!");
      return base64String;
    } catch (e) {
      print('VisionService Error capturing image: $e');
      throw Exception("VISION_ERROR: ${e.toString()}");
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }
}
