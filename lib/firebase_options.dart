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
    apiKey: 'REPLACE_API_KEY',
    appId: 'REPLACE_WEB_APP_ID',
    messagingSenderId: 'REPLACE_SENDER_ID',
    projectId: 'jagdamba-logistics',
    authDomain: 'jagdamba-logistics.firebaseapp.com',
    storageBucket: 'jagdamba-logistics.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REPLACE_API_KEY',
    appId: 'REPLACE_ANDROID_APP_ID',
    messagingSenderId: 'REPLACE_SENDER_ID',
    projectId: 'jagdamba-logistics',
    storageBucket: 'jagdamba-logistics.firebasestorage.app',
  );
}
