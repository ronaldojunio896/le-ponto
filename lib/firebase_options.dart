import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    return android;
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBGtpWvEBvw01fQo_6PmqXXjKzeKm-RJIc',
    appId: '1:957258916239:web:48c9982fb3b122ec446bfa',
    messagingSenderId: '957258916239',
    projectId: 'le-ponto-junio896',
    authDomain: 'le-ponto-junio896.firebaseapp.com',
    storageBucket: 'le-ponto-junio896.firebasestorage.app',
    measurementId: 'G-60093Z3G50',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCfH9BD0gSLLalouQUGAtoGsrY6bC7PWPE',
    appId: '1:957258916239:android:a4e14f9311e57650446bfa',
    messagingSenderId: '957258916239',
    projectId: 'le-ponto-junio896',
    storageBucket: 'le-ponto-junio896.firebasestorage.app',
  );
}
