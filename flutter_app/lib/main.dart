import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hello_buddy/firebase_options.dart';
import 'package:hello_buddy/core/theme/buddy_theme.dart';
import 'package:hello_buddy/features/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with safety fallback
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init fallback: $e');
    try {
      await Firebase.initializeApp();
    } catch (_) {}
  }

  // Lock to portrait mode safely
  try {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (_) {}

  // System UI overlay style
  try {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: BuddyColors.carbon,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  } catch (_) {}

  runApp(const ProviderScope(child: HelloBuddyApp()));
}

class HelloBuddyApp extends StatelessWidget {
  const HelloBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hello Buddy',
      debugShowCheckedModeBanner: false,
      theme: BuddyTheme.light(),
      darkTheme: BuddyTheme.dark(),
      themeMode: ThemeMode.light,
      home: const SplashScreen(),
    );
  }
}
