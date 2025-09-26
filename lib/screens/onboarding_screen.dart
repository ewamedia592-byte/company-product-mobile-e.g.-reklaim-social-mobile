// lib/screens/onboarding_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  @override
  _OnboardingScreenState createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameController = TextEditingController();
  bool _isCreator = false;
  final List<String> _allCategories = [
    'Writers', 'Music', 'Art', 'Lifestyle', 'Health', 'Education', 'Culture'
  ];
  final List<String> _selectedCategories = [];

  Future<void> _completeOnboarding() async {
    if (_nameController.text.trim().isEmpty) {
      _showError('Please enter your name');
      return;
    }
    if (_selectedCategories.length < 3) {
      _showError('Please select at least 3 categories');
      return;
    }

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) return;

      // Insert or update profile
      await supabase.from('profiles').upsert({
        'id': user.id,
        'username': _nameController.text.trim(),
        'is_business': _isCreator,
        'categories': _selectedCategories,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Go to home
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen()),
      );
    } on Exception catch (e) {
      _showError('Failed to save profile: $e');
    }
  }

  void _toggleCategory(String category) {
    setState(() {
      if (_selectedCategories.contains(category)) {
        _selectedCategories.remove(category);
      } else if (_selectedCategories.length < 5) {
        _selectedCategories.add(category);
      }
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F9FF),
      appBar: AppBar(
        backgroundColor: Color(0xFF2196F3),
        foregroundColor: Colors.white,
        title: Text('Welcome to EWA'),
      ),
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tell us about yourself',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            SizedBox(height: 8),
            Text('This helps us personalize your experience.'),
            SizedBox(height: 24),

            // Name field
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Your name',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),

            // Creator toggle
            Row(
              children: [
                Text('I’m a creator or business'),
                Switch(
                  value: _isCreator,
                  onChanged: (value) => setState(() => _isCreator = value),
                ),
              ],
            ),
            SizedBox(height: 24),

            // Category picker
            Text(
              'Choose 3–5 categories you’re interested in:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allCategories.map((category) {
                final isSelected = _selectedCategories.contains(category);
                return FilterChip(
                  label: Text(category),
                  selected: isSelected,
                  onSelected: (_) => _toggleCategory(category),
                  selectedColor: Color(0xFF2196F3),
                  checkmarkColor: Colors.white,
                );
              }).toList(),
            ),
            SizedBox(height: 24),

            // Continue button
            ElevatedButton(
              onPressed: _completeOnboarding,
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
                backgroundColor: Color(0xFF2196F3),
              ),
              child: Text(
                'Continue',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}