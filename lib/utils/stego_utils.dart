import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:encrypt/encrypt.dart' as enc;

class StegoUtils {
  // --- 1. AES AYARLARI (GİZLİLİK KATMANI) ---
  // 32 karakterli anahtar AES-256 için şarttır.
  static final _key = enc.Key.fromUtf8('kSrNdLfJTvEkQuYiXmZsWhI.AlC!D301');
  static final _iv = enc.IV.fromLength(16); // Başlatma vektörü

  // --- 2. KRİPTOGRAFİ FONKSİYONLARI ---

  /// Mesajı AES ile şifreler ve piksellere gömülmeye hazır hale getirir.
  static String encryptMessage(String plainText) {
    final encrypter = enc.Encrypter(enc.AES(_key));
    final encrypted = encrypter.encrypt(plainText, iv: _iv);
    return encrypted.base64;
  }

  /// Piksellerden çıkan şifreli veriyi tekrar okunabilir metne dönüştürür.
  static String decryptMessage(String encryptedBase64) {
    try {
      print("Deşifre edilmeye çalışılan metin: $encryptMessage"); // Terminale bak!
      final encrypter = enc.Encrypter(enc.AES(_key));
      final decrypted = encrypter.decrypt64(encryptedBase64, iv: _iv);
      return decrypted;
    } catch (e) {
      print("Deşifre sırasında hata: $e");
      throw e;
    }

  }

  // --- 3. BİT DÖNÜŞTÜRÜCÜLER ---

  static List<int> messageToBits(String message) {
    List<int> bits = [];
    // Mesajın sonuna 'dur' işareti (\x00) eklenir
    List<int> bytes = Uint8List.fromList((message + '\x00').codeUnits);
    for (int byte in bytes) {
      for (int i = 7; i >= 0; i--) {
        bits.add((byte >> i) & 1);
      }
    }
    return bits;
  }

  static String bitsToMessage(List<int> bits) {
    List<int> bytes = [];
    for (int i = 0; i < bits.length; i += 8) {
      if (i + 8 > bits.length) break;
      int byte = 0;
      for (int j = 0; j < 8; j++) {
        byte = (byte << 1) | bits[i + j];
      }
      if (byte == 0) break; // Null terminator kontrolü
      bytes.add(byte);
    }
    return String.fromCharCodes(bytes);
  }

  // --- 4. LSB STEGANOGRAFİ MOTORU ---

  /// Fotoğrafa veri gömer (LSB yöntemi).
  static Uint8List embedData(Uint8List imageBytes, String message) {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) return imageBytes;

    // Resmi 32-bit RGBA moduna zorla (Veri kaybını önlemek için)
    if (image.numChannels != 4) {
      image = image.convert(numChannels: 4);
    }

    List<int> bits = messageToBits(message);
    int bitIndex = 0;

    for (var frame in image.frames) {
      for (var pixel in frame) {
        if (bitIndex >= bits.length) break;

        // Mavi kanaldaki son biti temizle ve sırrı yerleştir
        int newBlue = (pixel.b.toInt() & 0xFE) | bits[bitIndex];
        pixel.setRgba(pixel.r, pixel.g, newBlue, pixel.a);
        bitIndex++;
      }
    }
    return Uint8List.fromList(img.encodePng(image)); // Kayıpsız PNG
  }

  /// Fotoğraftan veri çeker.
  static String extractData(Uint8List imageBytes) {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) return "";

    List<int> bits = [];
    for (var frame in image.frames) {
      for (var pixel in frame) {
        bits.add(pixel.b.toInt() & 1); // Son biti oku

        if (bits.length % 8 == 0) {
          int lastByte = 0;
          for (int i = 0; i < 8; i++) {
            lastByte = (lastByte << 1) | bits[bits.length - 8 + i];
          }
          if (lastByte == 0) return bitsToMessage(bits);
        }
      }
    }
    return bitsToMessage(bits);
  }
}