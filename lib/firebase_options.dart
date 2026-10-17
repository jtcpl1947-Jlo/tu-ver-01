// Firebase settings for project "jagdamba-logistics".
// These values identify the project; they are not passwords.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    if (defaultTargetPlatform == TargetPlatform.android) return android;
    return web;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAokTnIzZ2ghS5vktwsTpPgfDyOCn8fXE8',
    appId: '1:333923879905:web:9fb8885e1dfe48bd6e60a0',
    messagingSenderId: '333923879905',
    projectId: 'jagdamba-logistics',
    authDomain: 'jagdamba-logistics.firebaseapp.com',
    storageBucket: 'jagdamba-logistics.firebasestorage.app',
    measurementId: 'G-CCDRNN5HLT',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAokTnIzZ2ghS5vktwsTpPgfDyOCn8fXE8',
    appId: '1:333923879905:web:9fb8885e1dfe48bd6e60a0' /* TODO: Android app ID */,
    messagingSenderId: '333923879905',
    projectId: 'jagdamba-logistics',
    storageBucket: 'jagdamba-logistics.firebasestorage.app',
  );
}
