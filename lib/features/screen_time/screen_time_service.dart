cat > lib/features/screen_time/screen_time_service.dart << 'EOF'
class ScreenTimeService {
  static Future<void> setTimeOut(int minutes) async {
    print('Time-out set for $minutes minutes');
  }
  
  static Future<String> getStatusMessage() async {
    return 'Screen Time Feature Working!';
  }
}
EOF