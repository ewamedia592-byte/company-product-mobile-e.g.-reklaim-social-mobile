cat > lib/providers/auth_provider.dart << 'EOF'
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/ewa_user.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  EwaUser? _user;
  bool _isInitializing = true;

  EwaUser? get user => _user;
  bool get isInitializing => _isInitializing;

  void initialize() {
    _authService.userStream.listen((firebaseUser) {
      _user = (firebaseUser != null) 
          ? EwaUser(uid: firebaseUser.uid, email: firebaseUser.email) 
          : null;
      _isInitializing = false;
      notifyListeners();
    });
  }

  Future<bool> signIn(String email, String password) async {
    try {
      User? user = await _authService.signInWithEmailAndPassword(email, password);
      return user != null;
    } catch (e) {
      print('Sign in error: $e');
      return false;
    }
  }

  Future<bool> register(String email, String password) async {
    try {
      User? user = await _authService.registerWithEmailAndPassword(email, password);
      return user != null;
    } catch (e) {
      print('Registration error: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
  }
}
EOF