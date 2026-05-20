import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'login_screen.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Arka planda calisacak gorev ismi
const String periodicNotificationTask = "periodicNotificationTask";

// --- ARKA PLAN ISLEMCISI ---
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'daily_notification_channel',
      'Gunluk Bildirimler',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      'Mesaj Kontrolü',
      'Bugün yeni mesajlarınız olabilir',
      platformChannelSpecifics,
    );

    return Future.value(true);
  });
}

// Tema yonetimi icin global dinleyici
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  // Flutter binding baslatma
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase Baslatma
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 2. Workmanager Baslatma
  await Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );

  // 3. Periyodik Gorev Kaydi (24 saatte bir)
  await Workmanager().registerPeriodicTask(
    "1",
    periodicNotificationTask,
    frequency: const Duration(hours: 24),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
  );

  runApp(const CrypticCamApp());
}

class CrypticCamApp extends StatelessWidget {
  const CrypticCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'CrypticCam',
          themeMode: mode,

          // AYDINLIK TEMA
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFFFF5F2),
            textTheme: GoogleFonts.plusJakartaSansTextTheme(),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFFBC8B6),
              primary: const Color(0xFFFBC8B6),
              secondary: const Color(0xFFADCFD0),
            ),
          ),

          // KARANLIK TEMA
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF121212),
            textTheme: GoogleFonts.plusJakartaSansTextTheme(
              ThemeData.dark().textTheme,
            ),
            colorScheme: ColorScheme.fromSeed(
              brightness: Brightness.dark,
              seedColor: const Color(0xFFADCFD0),
              primary: const Color(0xFFADCFD0),
              secondary: const Color(0xFFFBC8B6),
              surface: const Color(0xFF1E1E1E),
            ),
          ),

          home: const LoginScreen(),
        );
      },
    );
  }
}