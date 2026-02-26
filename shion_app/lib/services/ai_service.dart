import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AiService extends ChangeNotifier {
  static const String _historyKey = 'chat_history';
  static const String _apiKeyKey = 'gemini_api_key';

  SharedPreferences? _prefs;
  final List<Map<String, dynamic>> _history = [];

  bool get hasApiKey =>
      _prefs?.getString(_apiKeyKey) != null &&
      _prefs!.getString(_apiKeyKey)!.isNotEmpty;
  String? get currentApiKey => _prefs?.getString(_apiKeyKey);

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _loadHistory();
    notifyListeners();
  }

  void saveApiKey(String key) {
    if (_prefs == null) return;
    _prefs!.setString(_apiKeyKey, key);
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

  Future<String> sendMessage(String text) async {
    if (!hasApiKey) return "APIキーが設定されていません。";
    final apiKey = currentApiKey!;

    try {
      // 1. Add user message to history
      _history.add({
        "role": "user",
        "parts": [
          {"text": text},
        ],
      });

      // 2. Prepare payload
      final payload = {
        "systemInstruction": {
          "role": "system",
          "parts": [
            {
              "text":
                  "あなたは「シオン」という名前のAIロボットです。短く、親しみやすい日本語で返答してください。音声で読み上げるため、1〜2文程度の簡潔な文章でお願いします。",
            },
          ],
        },
        "contents": _history,
        "tools": [
          {"googleSearch": {}},
        ],
      };

      // 3. Send HTTP request
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey',
      );
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final content = candidates.first['content'];
          final parts = content['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            String replyText = parts.first['text'] ?? "返答がありませんでした。";

            // Add model response to history
            _history.add({
              "role": "model",
              "parts": [
                {"text": replyText},
              ],
            });
            await _saveHistory();

            return replyText;
          }
        }
        return "返答がありませんでした。";
      } else {
        debugPrint("API Error: ${response.statusCode} - ${response.body}");
        _history.removeLast(); // Remove the user message if it failed
        return "通信エラーが発生しました(コード${response.statusCode})。";
      }
    } catch (e) {
      debugPrint(e.toString());
      if (_history.isNotEmpty && _history.last['role'] == 'user') {
        _history.removeLast();
      }
      return "アプリ内部エラーが発生しました。";
    }
  }

  void clearHistory() {
    _prefs?.remove(_historyKey);
    _history.clear();
    notifyListeners();
  }
}
