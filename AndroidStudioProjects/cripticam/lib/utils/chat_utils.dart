import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatUtils {
  /// 1. İki kullanıcı adını alfabetik sıraya göre birleştirip eşsiz ID üretir
  static String getChatRoomId(String user1, String user2) {
    List<String> users = [user1.toLowerCase().trim(), user2.toLowerCase().trim()];
    users.sort();
    return "${users[0]}_${users[1]}";
  }

  /// 2. Cihazın hafızasına kaydedilmiş olan arka plan dosyasını getirir
  /// [chatId] hem grup ID'si hem de bireysel chat odası ID'si olabilir.
  static Future<File?> loadSavedBackground(String chatId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Her sohbetin kendine özel bir anahtarı olur (Örn: ayse_rana_bg)
      String? imagePath = prefs.getString('${chatId}_bg');

      if (imagePath != null && imagePath.isNotEmpty) {
        File file = File(imagePath);
        // Dosyanın hala telefonda var olup olmadığını kontrol ediyoruz
        if (await file.exists()) {
          return file;
        }
      }
    } catch (e) {
      print("Arka plan yukleme hatasi: $e");
    }
    return null;
  }

  /// 3. Galeriden resim seçtirir ve dosya yolunu SharedPreferences'a kaydeder
  static Future<File?> pickAndSaveBackground(String chatId) async {
    final picker = ImagePicker();

    // Performans için resim kalitesini %50'ye düşürüyoruz (J7 Prime dostu)
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        // Dosya yolunu (path) String olarak kaydediyoruz
        await prefs.setString('${chatId}_bg', pickedFile.path);
        return File(pickedFile.path);
      } catch (e) {
        print("Arka plan kaydetme hatasi: $e");
      }
    }
    return null;
  }

  /// 4. (Opsiyonel) Kaydedilmiş arka planı silmek istersen
  static Future<void> clearSavedBackground(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${chatId}_bg');
  }
}