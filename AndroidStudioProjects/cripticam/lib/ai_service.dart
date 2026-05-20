import 'dart:convert';
import 'package:http/http.dart' as http;

class AIService {
  // AI Studio'dan  anahtar
  static const String _apiKey = "AIzaSyCUbxj1qd8q85MfLV9bDqn75Ls0hy_hG7c";
  static const String _baseUrl = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent";

  static Future<String> getResponse(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl?key=$_apiKey"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": prompt}
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // JSON'dan dönen metni ayıklıyoruz
        return data['candidates'][0]['content']['parts'][0]['text'];
      } else {
        return "Sunucu Hatası: ${response.statusCode}\n${response.body}";
      }
    } catch (e) {
      return "Bağlantı Hatası: $e";
    }
  }
}