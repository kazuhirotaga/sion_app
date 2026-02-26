import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';

void main() {
  final content = Content.text('hello');
  
  // Create a request to see how it serializes
  final model = GenerativeModel(
    model: 'gemini-2.5-flash',
    apiKey: 'dummy',
    systemInstruction: Content.system('you are a bot'),
  );
  
  // In SDK 0.4.7, tool might not have googleSearchRetrieval built-in, but we can see other fields
  // Let's manually construct the map based on SDK's serialization if we can't instantiate the request object directly.
  
  print('System Instruction JSON:');
  print(jsonEncode(Content.system('you are a bot').toJson()));
  
  print('Content JSON:');
  print(jsonEncode(Content.text('hello').toJson()));
  
  print('Content Model JSON:');
  print(jsonEncode(Content.model([TextPart('reply')]).toJson()));
}
