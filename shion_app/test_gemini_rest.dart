import 'dart:convert';
import 'dart:io';

void main() async {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null) {
    print('No API key');
    return;
  }

  final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey');
  
  final httpClient = HttpClient();
  final request = await httpClient.postUrl(url);
  request.headers.set('Content-Type', 'application/json');
  
  final payload = {
    "contents": [
      {
        "role": "user",
        "parts": [{"text": "今日の日本の主なニュースを3つ教えて。短く。"}]
      }
    ],
    "tools": [
      {
        "googleSearch": {}
      }
    ]
  };
  
  request.write(jsonEncode(payload));
  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();
  
  print('Status: ${response.statusCode}');
  print('Body: $responseBody');
}
