import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleService extends ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _panTiltCharacteristic;

  bool get isConnected => _connectedDevice != null;
  String _status = "Disconnected";
  String get status => _status;

  // The UUIDs for the ESP32 setup (to be defined in Dock Phase 1)
  final String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  Future<void> startScanningAndConnect() async {
    _status = "Scanning...";
    notifyListeners();

    try {
      // Start scanning
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

      // Listen to scan results
      var subscription = FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          // Look for "ShionDock" or specific ESP32 name
          if (r.device.platformName == "ShionDock") {
            await FlutterBluePlus.stopScan();
            _connectToDevice(r.device);
            break;
          }
        }
      });

      // Cleanup subscription if scan finishes without finding
      FlutterBluePlus.isScanning.listen((isScanning) {
        if (!isScanning && _connectedDevice == null) {
          _status = "Dock not found";
          notifyListeners();
          subscription.cancel();
        }
      });
    } catch (e) {
      _status = "Error scanning: $e";
      notifyListeners();
      debugPrint(e.toString());
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      _status = "Connecting...";
      notifyListeners();

      await device.connect(license: License.free);
      _connectedDevice = device;

      _status = "Discovering services...";
      notifyListeners();

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid.toString() == SERVICE_UUID) {
          for (var c in service.characteristics) {
            if (c.uuid.toString() == CHARACTERISTIC_UUID) {
              _panTiltCharacteristic = c;
              _status = "Connected & Ready";
              notifyListeners();
              return;
            }
          }
        }
      }

      _status = "Connected but characteristic not found";
      notifyListeners();
    } catch (e) {
      _status = "Connection failed: $e";
      notifyListeners();
      _connectedDevice = null;
    }
  }

  Future<void> sendPanTiltCommand(int panAngle, int tiltAngle) async {
    if (_panTiltCharacteristic == null) return;

    // Send command as comma separated string or bytes, e.g. "90,90"
    String command = "$panAngle,$tiltAngle";
    try {
      await _panTiltCharacteristic!.write(command.codeUnits);
    } catch (e) {
      debugPrint("Error sending command: $e");
    }
  }

  void disconnect() {
    _connectedDevice?.disconnect();
    _connectedDevice = null;
    _panTiltCharacteristic = null;
    _status = "Disconnected";
    notifyListeners();
  }
}
