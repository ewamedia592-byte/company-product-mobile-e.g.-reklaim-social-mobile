cat > lib/features/screen_time/screen_time_screen.dart << 'EOF'
import 'package:flutter/material.dart';

class ScreenTimeScreen extends StatelessWidget {
  const ScreenTimeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Wellness Time-Out'),
        backgroundColor: Colors.blue,
      ),
      body: const Center(
        child: Text(
          'EWA Screen Time Feature\\n\\nThis feature will help users take healthy breaks.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
EOF