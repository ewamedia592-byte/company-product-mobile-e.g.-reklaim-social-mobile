cat > lib/main.dart << 'EOF'
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AuthProvider(),
      child: MaterialApp(
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
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      authProvider.initialize();
    });
    
    if (authProvider.isInitializing) {
      return Scaffold(
        backgroundColor: Color(0xFFF5F9FF),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2196F3)),
          ),
        ),
      );
    }
    
    return LoginScreen();
  }
}
EOF