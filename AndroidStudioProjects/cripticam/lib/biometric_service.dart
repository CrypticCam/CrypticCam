import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> authenticate() async {
    try {
      // 1. Donanım ve Sistem Kontrolü
      final bool canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();

      if (!canAuthenticate) {
        print("Biyometrik doğrulama bu cihazda kullanılamıyor.");
        return false;
      }

      // 2. Doğrulama İşlemini Başlat
      return await _auth.authenticate(
        localizedReason: 'Mesajı görmek için kimliğinizi doğrulayın ',
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Biyometrik Kimlik Doğrulama',
            biometricHint: 'Parmak izi okuyucuya dokunun',
            cancelButton: 'İptal',
          ),
        ],
        options: const AuthenticationOptions(
          stickyAuth: true, // Diyalog açıkken uygulama arkaya düşerse işlemi korur
          biometricOnly: true, // PIN veya Desen kullanımını devre dışı bırakır, sadece biyometrik ister
          useErrorDialogs: true, // Sistem hatalarını (parmak izi kayıtlı değilse vb.) otomatik gösterir
        ),
      );
    } on PlatformException catch (e) {
      print("Biyometrik Hata (Platform): ${e.code} - ${e.message}");
      return false;
    } catch (e) {
      print("Bilinmeyen Biyometrik Hata: $e");
      return false;
    }
  }
}