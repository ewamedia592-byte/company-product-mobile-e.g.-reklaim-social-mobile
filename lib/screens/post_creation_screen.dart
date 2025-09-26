// lib/screens/post_creation_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PostCreationScreen extends StatefulWidget {
  @override
  _PostCreationScreenState createState() => _PostCreationScreenState();
}

class _PostCreationScreenState extends State<PostCreationScreen> {
  final _captionController = TextEditingController();
  String _selectedCategory = 'Culture';
  final List<String> _categories = [
    'Writers', 'Music', 'Art', 'Lifestyle', 'Health', 'Education', 'Culture'
  ];
  String? _selectedFilter;
  final List<String> _filters = [
    'None',
    'LIB Jue',
    'Odogwu',
    'FBNP',
    'FGNP',
    'Big Jue',
    'Wangu',
    'Mabel',
    'Uzuri'
  ];

  Future<void> _post() async {
    if (_captionController.text.trim().isEmpty) {
      _showError('Please add a caption or media');
      return;
    }

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) return;

      // In MVP, we'll just save text + category
      await supabase.from('posts').insert({
        'user_id': user.id,
        'category': _selectedCategory,
        'content': _captionController.text.trim(),
        'filter_used': _selectedFilter != 'None' ? _selectedFilter : null,
        'created_at': DateTime.now().toIso8601String(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Posted successfully!'), backgroundColor: Colors.green),
      );

      Navigator.pop(context); // Go back to home
    } on Exception catch (e) {
      _showError('Failed to post: $e');
    }
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
        title: Text('Create Post'),
        actions: [
          IconButton(
            icon: Icon(Icons.send),
            onPressed: _post,
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category picker
            Text('Category', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              items: _categories.map((cat) {
                return DropdownMenuItem(value: cat, child: Text(cat));
              }).toList(),
              onChanged: (value) => setState(() => _selectedCategory = value!),
              decoration: InputDecoration(
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),

            // Caption
            Text('Caption', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            TextField(
              controller: _captionController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'Share your story...',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),

            // Filter picker
            Text('Beauty Filter', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _filters.map((filter) {
                final isSelected = _selectedFilter == filter;
                return FilterChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedFilter = filter),
                  selectedColor: Color(0xFF2196F3),
                  checkmarkColor: Colors.white,
                );
              }).toList(),
            ),
            SizedBox(height: 16),

            // Media placeholder (we'll add image/video picker later)
            Container(
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text('➕ Add Image/Video\n(Media picker coming soon)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}