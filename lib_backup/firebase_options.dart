cat > lib/firebase_options.dart << 'EOF'
import 'package:firebase_core/firebase_core.dart';
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
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA1ldhCBxMt9iuDb09X9Eu7q_LGFR6ZzWE',
    appId: '1:164840589785:web:faef3c47bfb976c47231c8',
    messagingSenderId: '164840589785',
    projectId: 'ewa-app-5c60f',
    authDomain: 'ewa-app-5c60f.firebaseapp.com',
    storageBucket: 'ewa-app-5c60f.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA1ldhCBxMt9iuDb09X9Eu7q_LGFR6ZzWE',
    appId: '1:164840589785:android:faef3c47bfb976c47231c8',
    messagingSenderId: '164840589785',
    projectId: 'ewa-app-5c60f',
    storageBucket: 'ewa-app-5c60f.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA1ldhCBxMt9iuDb09X9Eu7q_LGFR6ZzWE',
    appId: '1:164840589785:ios:faef3c47bfb976c47231c8',
    messagingSenderId: '164840589785',
    projectId: 'ewa-app-5c60f',
    storageBucket: 'ewa-app-5c60f.firebasestorage.app',
    iosBundleId: 'com.example.ewaApp',
  );
}
EOF