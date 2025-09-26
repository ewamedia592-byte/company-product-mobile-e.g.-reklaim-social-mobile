import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://cxcudrvejwabwagqplmf.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN4Y3VkcnZlandhYndhZ3FwbG1mIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg4MjYyNDksImV4cCI6MjA3NDQwMjI0OX0.vGLXIJtnVAND9O2sAbzhZeAqWp8xsXra5XgJnWUyLMc',
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EWA App',
      theme: ThemeData(
        colorScheme: ColorScheme.light(
          primary: Color(0xFF2196F3),
          secondary: Color(0xFF03A9F4),
          background: Color(0xFFF5F9FF),
          surface: Colors.white,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF2196F3),
          foregroundColor: Colors.white,
        ),
      ),
      home: AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    return session == null ? LoginScreen() : HomeScreen();
  }
}
