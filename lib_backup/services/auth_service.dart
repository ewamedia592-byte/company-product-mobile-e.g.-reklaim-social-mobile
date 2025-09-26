cat > lib/services/auth_service.dart << 'EOF'
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
          email: email.trim(), password: password);
      return result.user;
    } on FirebaseAuthException catch (e) {
      print('Failed to sign in: ${e.code} - ${e.message}');
      return null;
    }
  }

  Future<User?> registerWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      return result.user;
    } on FirebaseAuthException catch (e) {
      print('Failed to register: ${e.code} - ${e.message}');
      return null;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Stream<User?> get userStream => _auth.authStateChanges();
}
EOF