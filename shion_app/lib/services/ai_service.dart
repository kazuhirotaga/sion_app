import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AiService extends ChangeNotifier {
  static const String _historyKey = 'chat_history';
  static const String _backendUrlKey = 'backend_url';

  SharedPreferences? _prefs;
  final List<Map<String, dynamic>> _history = [];

  bool get hasBackendUrl =>
      _prefs?.getString(_backendUrlKey) != null &&
      _prefs!.getString(_backendUrlKey)!.isNotEmpty;
  String? get currentBackendUrl => _prefs?.getString(_backendUrlKey);

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _loadHistory();
    notifyListeners();
  }

  void saveBackendUrl(String url) {
    if (_prefs == null) return;
    _prefs!.setString(_backendUrlKey, url);
    notifyListeners();
  }

  void _loadHistory() {
    if (_prefs == null) return;

    _history.clear();
    final historyStrList = _prefs!.getStringList(_historyKey);

    if (historyStrList != null) {
      for (var str in historyStrList) {
        try {
          final map = jsonDecode(str);
          // 旧フォーマット対応 ( {"role": "...", "text": "..."} )
          if (map.containsKey('text') && !map.containsKey('parts')) {
            _history.add({
              "role": map['role'] ?? "user",
              "parts": [
                {"text": map['text']},
              ],
            });
          } else {
            // 新フォーマット ( {"role": "...", "parts": [{"text": "..."}]} )
            _history.add(map);
          }
        } catch (e) {
          debugPrint("Failed to parse history: $e");
        }
      }
    }
  }

  Future<void> _saveHistory() async {
    if (_prefs == null) return;

    List<String> historyStrList = [];

    // Only save the recent context (e.g., last 20 messages) to avoid breaking context limits
    final saveAmount = _history.length > 20 ? 20 : _history.length;
    final recentHistory = _history.sublist(_history.length - saveAmount);

    for (var content in recentHistory) {
      historyStrList.add(jsonEncode(content));
    }
    await _prefs!.setStringList(_historyKey, historyStrList);
  }

  Future<Map<String, dynamic>> sendMessage(
    String text, {
    String? imageBase64,
  }) async {
    if (!hasBackendUrl)
      return {
        "text": "バックエンドURLが設定されていません。",
        "emotion": "default",
        "action": "none",
      };
    final backendUrl = currentBackendUrl!;

    try {
      // 1. Prepare payload
      // We do not add the user message to history here. The backend will handle the concatenation.
      final payload = {"message": text, "history": _history};
      if (imageBase64 != null) {
        payload["image_base64"] = imageBase64;
      }

      // 2. Build HTTP request URL robustly
      String targetUrl = backendUrl.trim();
      if (!targetUrl.startsWith('http')) {
        targetUrl = 'https://$targetUrl';
      } else if (targetUrl.startsWith('http://') &&
          !targetUrl.contains('10.0.2.2') &&
          !targetUrl.contains('localhost') &&
          !targetUrl.contains('192.168.')) {
        // Enforce https for remote urls (like render)
        targetUrl = targetUrl.replaceFirst('http://', 'https://');
      }

      if (targetUrl.endsWith('/')) {
        targetUrl = targetUrl.substring(0, targetUrl.length - 1);
      }
      if (!targetUrl.endsWith('/chat')) {
        targetUrl = '$targetUrl/chat';
      }
      final url = Uri.parse(targetUrl);
      debugPrint("Sending request to: $url");

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));

        final reply = data['reply'];
        final String replyText = reply['text'] ?? "返答がありませんでした。";
        final String emotion = reply['emotion'] ?? "default";
        final String action = reply['action'] ?? "none";

        // Update local history entirely from backend's response if provided
        if (data.containsKey('history')) {
          _history.clear();
          List<dynamic> newHistory = data['history'];
          for (var h in newHistory) {
            _history.add(h as Map<String, dynamic>);
          }
        } else {
          // Fallback history update if backend returns only reply
          _history.add({
            "role": "user",
            "parts": [
              {"text": text},
            ],
          });
          _history.add({
            "role": "model",
            "parts": [
              {"text": replyText},
            ],
          });
        }

        await _saveHistory();

        final String callTarget = reply['call_target'] ?? "";

        return {
          "text": replyText,
          "emotion": emotion,
          "action": action,
          "call_target": callTarget,
        };
      } else {
        debugPrint("API Error: ${response.statusCode} - ${response.body}");
        return {
          "text": "通信エラーが発生しました(コード${response.statusCode})。",
          "emotion": "default",
          "action": "none",
        };
      }
    } catch (e) {
      debugPrint(e.toString());
      return {
        "text": "アプリ内部エラーが発生しました。",
        "emotion": "default",
        "action": "none",
      };
    }
  }

  void clearHistory() {
    _prefs?.remove(_historyKey);
    _history.clear();
    notifyListeners();
  }

  /// Fetch the latest financial analysis from the backend.
  /// Returns null if no analysis is available.
  Future<Map<String, dynamic>?> fetchLatestAnalysis() async {
    if (currentBackendUrl == null) return null;

    try {
      String targetUrl = currentBackendUrl!.trim();
      if (!targetUrl.startsWith('http')) {
        targetUrl = 'https://$targetUrl';
      } else if (targetUrl.startsWith('http://') &&
          !targetUrl.contains('10.0.2.2') &&
          !targetUrl.contains('localhost') &&
          !targetUrl.contains('192.168.')) {
        targetUrl = targetUrl.replaceFirst('http://', 'https://');
      }
      if (targetUrl.endsWith('/')) {
        targetUrl = targetUrl.substring(0, targetUrl.length - 1);
      }
      // Remove /chat suffix if present to get base URL
      if (targetUrl.endsWith('/chat')) {
        targetUrl = targetUrl.substring(0, targetUrl.length - 5);
      }

      final url = Uri.parse('$targetUrl/finance/latest');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (data['status'] == 'ok' && data['analysis'] != null) {
          return data['analysis'] as Map<String, dynamic>;
        }
      }
    } catch (e) {
      print('AiService: Error fetching financial analysis: $e');
    }
    return null;
  }
}
