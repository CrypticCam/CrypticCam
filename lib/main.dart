import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'login_screen.dart';

// Uygulama genelinde temayı anlık değiştirmek için global bir dinleyici tanımlıyoruz.
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase başlatma işlemi
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const CrypticCamApp());
}

class CrypticCamApp extends StatelessWidget {
  const CrypticCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ValueListenableBuilder ile tema değişimlerini anlık olarak dinliyoruz.
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'CrypticCam', //

          // --- TEMA AYARLARI ---
          themeMode: mode, // Aktif olan temayı belirler

          // 1. AYDINLIK TEMA (Varsayılan)
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFFFF5F2), // Şeftali Beyazı
            textTheme: GoogleFonts.plusJakartaSansTextTheme(), //
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFFBC8B6),
              primary: const Color(0xFFFBC8B6), // Ana renk
              secondary: const Color(0xFFADCFD0), // Mint Yeşili
            ),
          ),

          // 2. KARANLIK TEMA
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF121212), // Koyu arka plan
            textTheme: GoogleFonts.plusJakartaSansTextTheme(
              ThemeData.dark().textTheme, // Yazıları karanlık moda uyumlu yapar
            ),
            colorScheme: ColorScheme.fromSeed(
              brightness: Brightness.dark,
              seedColor: const Color(0xFFADCFD0),
              primary: const Color(0xFFADCFD0), // Karanlık modda mint yeşili daha belirgin
              secondary: const Color(0xFFFBC8B6),
              surface: const Color(0xFF1E1E1E), // Kartların arka planı
            ),
          ),

          // Uygulama LoginScreen ile başlar
          home: const LoginScreen(),
        );
      },
    );
  }
}