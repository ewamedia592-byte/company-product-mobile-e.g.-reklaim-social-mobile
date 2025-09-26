import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeFeedScreen extends StatefulWidget {
  @override
  _HomeFeedScreenState createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  List<String> _categories = ['All', 'Writers', 'Music', 'Art', 'Lifestyle', 'Health', 'Education', 'Culture'];
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
      final response = await supabase
          .from('posts')
          .select('*, profiles(username, is_business)')
          .order('created_at', ascending: false);

      List<dynamic> filteredByCategory = response;
      if (_selectedCategory != 'All') {
        filteredByCategory = response.where((post) => post['category'] == _selectedCategory).toList();
      }

      List<dynamic> filteredPosts = filteredByCategory;
      if (_hideBusiness) {
        filteredPosts = filteredByCategory
            .where((post) => (post['profiles']?['is_business'] ?? false) == false)
            .toList();
      }

      if (mounted) {
        setState(() {
          _posts = filteredPosts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load posts: $e')),
        );
      }
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
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
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (value) {
                setState(() => _selectedCategory = value!);
                Navigator.pop(context);
                _fetchPosts();
              },
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _hideBusiness,
                  onChanged: (v) {
                    setState(() => _hideBusiness = v!);
                    Navigator.pop(context);
                    _fetchPosts();
                  },
                ),
                Text('Hide business content'),
              ],
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Close'))],
      ),
    );
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
            tabs: [Tab(text: 'Following'), Tab(text: 'For You')],
          ),
          actions: [IconButton(icon: Icon(Icons.filter_list), onPressed: _showFilterDialog)],
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
                                CircleAvatar(backgroundColor: Color(0xFF2196F3), child: Icon(Icons.person, color: Colors.white)),
                                SizedBox(width: 8),
                                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(profile['username'] ?? 'Anonymous', style: TextStyle(fontWeight: FontWeight.bold)),
                                  if (profile['is_business'] == true) Text('Business', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                ]),
                                Spacer(),
                                Text(post['category'], style: TextStyle(color: Color(0xFF2196F3), fontWeight: FontWeight.bold)),
                              ],
                            ),
                            SizedBox(height: 12),
                            Text(post['content'] ?? ''),
                            if (post['filter_used'] != null) ...[
                              SizedBox(height: 8),
                              Text('Filter: ${post['filter_used']}', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.favorite_border, size: 18),
                                SizedBox(width: 4),
                                Text('0'),
                                Spacer(),
                                Text(_formatTime(DateTime.parse(post['created_at'])), style: TextStyle(color: Colors.grey, fontSize: 12)),
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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
