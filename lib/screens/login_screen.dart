// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'onboarding_screen.dart'; // We'll navigate to onboarding after login
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isSignUpMode = false;

  Future<void> _submit() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showError('Please fill in all fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      if (_isSignUpMode) {
        await supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        _showMessage('Check your email for confirmation');
      } else {
        await supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        // After login, check if user has a profile
        final response = await supabase
            .from('profiles')
            .select()
            .eq('id', supabase.auth.currentUser!.id);

        if (response.isEmpty) {
          // New user → onboarding
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => OnboardingScreen()),
          );
        } else {
          // Existing user → home
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => HomeScreen()),
          );
        }
      }
    } on AuthException catch (error) {
      _showError(error.message);
    } on Exception catch (error) {
      _showError('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F9FF),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo: Handshake = two people greeting/connecting
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Color(0xFF2196F3),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.handshake,
                    color: Colors.white,
                    size: 50,
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  _isSignUpMode ? 'Create Account' : 'Welcome Back',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Color(0xFF2196F3),
                        fontWeight: FontWeight.bold,
                      ),
                ),
                SizedBox(height: 8),
                Text(
                  _isSignUpMode
                      ? 'Join EWA — The Beauty of Community'
                      : 'Sign in to continue',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                SizedBox(height: 24),
                _isLoading
                    ? CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2196F3)),
                      )
                    : ElevatedButton(
                        onPressed: _submit,
                        child: Text(
                          _isSignUpMode ? 'Sign Up' : 'Sign In',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white, // ✅ Now clearly visible
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(double.infinity, 50),
                          backgroundColor: Color(0xFF2196F3),
                        ),
                      ),
                SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isSignUpMode = !_isSignUpMode;
                      _emailController.clear();
                      _passwordController.clear();
                    });
                  },
                  child: Text(
                    _isSignUpMode
                        ? 'Already have an account? Sign In'
                        : 'Create new account',
                    style: TextStyle(color: Color(0xFF2196F3)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}