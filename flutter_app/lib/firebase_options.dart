// File generated from EPD2026 Firebase project (epd2026-127ec)
// DO NOT EDIT manually — regenerate via flutterfire configure

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('iOS not configured for this project.');
      case TargetPlatform.macOS:
        throw UnsupportedError('macOS not configured for this project.');
      case TargetPlatform.windows:
        throw UnsupportedError('Windows not configured for this project.');
      case TargetPlatform.linux:
        throw UnsupportedError('Linux not configured for this project.');
      default:
        throw UnsupportedError('Unsupported platform.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_FIREBASE_API_KEY',
    appId: '1:728428143137:android:bd4621ea2dd4e42bee3960',
    messagingSenderId: '728428143137',
    projectId: 'epd2026-127ec',
    storageBucket: 'epd2026-127ec.firebasestorage.app',
    databaseURL: 'https://epd2026-127ec-default-rtdb.firebaseio.com',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_FIREBASE_API_KEY',
    appId: '1:728428143137:web:901944a49c0b1a9fee3960',
    messagingSenderId: '728428143137',
    projectId: 'epd2026-127ec',
    authDomain: 'epd2026-127ec.firebaseapp.com',
    storageBucket: 'epd2026-127ec.firebasestorage.app',
    databaseURL: 'https://epd2026-127ec-default-rtdb.firebaseio.com',
  );
}
