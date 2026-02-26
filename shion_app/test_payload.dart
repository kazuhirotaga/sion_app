import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final payload = {
    "systemInstruction": {
      "parts": [
        {"text": "あなたはシオンです。"}
      ]
    },
    "contents": [
      {
        "role": "user",
        "parts": [{"text": "テスト"}]
      }
    ],
    "tools": [
      {
        "googleSearch": {}
      }
    ]
  };

  final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=DUMMY_KEY');
  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(payload),
  );

  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');
}
