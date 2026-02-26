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
    _cameraController!.startImageStream((image) {
      // Process image here later
      // debugPrint('Received image frame for processing');
    });
  }

  void stopFaceTracking() {
    if (_cameraController?.value.isStreamingImages ?? false) {
      _cameraController?.stopImageStream();
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }
}
