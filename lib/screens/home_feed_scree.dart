// lib/screens/home_feed_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeFeedScreen extends StatefulWidget {
  @override
  _HomeFeedScreenState createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<String> _categories = [
    'All',
    'Writers',
    'Music',
    'Art',
    'Lifestyle',
    'Health',
    'Education',
    'Culture'
  ];
  String _selectedCategory = 'All';
  bool _hideBusiness = false;
  List<dynamic> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchPosts();
  }

  Future<void> _fetchPosts() async {
    try {
      final supabase = Supabase.instance.client;
      var query = supabase
          .from('posts')
          .select('*, profiles(username, is_business)')
          .order('created_at', ascending: false);

      // Apply category filter
      if (_selectedCategory != 'All') {
        query = query.eq('category', _selectedCategory);
      }

      // Hide business posts if toggled
      if (_hideBusiness) {
        query = query.eq('profiles.is_business', false);
      }

      final response = await query;
      if (mounted) {
        setState(() {
          _posts = response;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load posts')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Color(0xFF2196F3),
          foregroundColor: Colors.white,
          title: Text('EWA'),
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: 'Following'),
              Tab(text: 'For You'),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.filter_list),
              onPressed: () {
                _showFilterDialog();
              },
            ),
          ],
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async => _fetchPosts(),
                child: ListView.builder(
                  padding: EdgeInsets.all(12),
                  itemCount: _posts.length,
                  itemBuilder: (context, index) {
                    final post = _posts[index];
                    final profile = post['profiles'];
                    return Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Color(0xFF2196F3),
                                  child: Icon(Icons.person, color: Colors.white),
                                ),
                                SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      profile['username'] ?? 'Anonymous',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    if (profile['is_business'] == true)
                                      Text(
                                        'Business',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                                Spacer(),
                                Text(
                                  post['category'],
                                  style: TextStyle(
                                    color: Color(0xFF2196F3),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            Text(post['content'] ?? ''),
                            if (post['filter_used'] != null) ...[
                              SizedBox(height: 8),
                              Text(
                                'Filter: ${post['filter_used']}',
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.favorite_border, size: 18),
                                SizedBox(width: 4),
                                Text('0'),
                                Spacer(),
                                Text(
                                  _formatTime(DateTime.parse(post['created_at'])),
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${time.day}/${time.month}';
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Feed Filters'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              items: _categories.map((cat) {
                return DropdownMenuItem(value: cat, child: Text(cat));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCategory = value!;
                });
                Navigator.pop(context);
                _fetchPosts();
              },
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _hideBusiness,
                  onChanged: (value) {
                    setState(() {
                      _hideBusiness = value!;
                    });
                    Navigator.pop(context);
                    _fetchPosts();
                  },
                ),
                Text('Hide business content'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}