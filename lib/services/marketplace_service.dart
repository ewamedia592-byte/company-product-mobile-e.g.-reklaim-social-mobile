import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class Product {
  final String id;
  final String ownerId;
  final String title;
  final int priceCents;
  final String currency;
  final String? description;
  final String? culturalStory;
  final String? meetupLocation;
  final String? imageUrl;
  final DateTime createdAt;

  const Product({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.priceCents,
    required this.currency,
    required this.description,
    required this.culturalStory,
    required this.meetupLocation,
    required this.imageUrl,
    required this.createdAt,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      title: map['title'] as String,
      priceCents: (map['price_cents'] as num).toInt(),
      currency: (map['currency'] ?? 'USD') as String,
      description: map['description'] as String?,
      culturalStory: map['cultural_story'] as String?,
      meetupLocation: map['meetup_location'] as String?,
      imageUrl: map['image_url'] as String?,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  double get price => priceCents / 100.0;
}

class SafeSpot {
  final String id;
  final String ownerId;
  final String name;
  final String? address;
  final String? city;
  final String? country;
  final String? notes;
  final DateTime createdAt;

  const SafeSpot({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.address,
    required this.city,
    required this.country,
    required this.notes,
    required this.createdAt,
  });

  factory SafeSpot.fromMap(Map<String, dynamic> map) {
    return SafeSpot(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      name: map['name'] as String,
      address: map['address'] as String?,
      city: map['city'] as String?,
      country: map['country'] as String?,
      notes: map['notes'] as String?,
      createdAt:
          DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class MarketplaceService {
  static final SupabaseClient _client = Supabase.instance.client;

  static Future<List<Product>> fetchMyProducts() async {
    final user = _requireUser();
    final rows = await _client
        .from('marketplace_products')
        .select()
        .eq('owner_id', user.id)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows)
        .map(Product.fromMap)
        .toList();
  }

  static Future<Product> createProduct({
    required String title,
    required int priceCents,
    String currency = 'USD',
    String? description,
    String? culturalStory,
    String? meetupLocation,
    String? imageUrl,
  }) async {
    final user = _requireUser();

    final inserted = await _client
        .from('marketplace_products')
        .insert({
          'owner_id': user.id,
          'title': title.trim(),
          'price_cents': priceCents,
          'currency': currency,
          'description': description?.trim(),
          'cultural_story': culturalStory?.trim(),
          'meetup_location': meetupLocation?.trim(),
          'image_url': imageUrl,
        })
        .select()
        .single();

    return Product.fromMap(inserted as Map<String, dynamic>);
  }

  static Future<Product> updateProduct({
    required String id,
    required String title,
    required int priceCents,
    String currency = 'USD',
    String? description,
    String? culturalStory,
    String? meetupLocation,
    String? imageUrl,
  }) async {
    final user = _requireUser();

    final updated = await _client
        .from('marketplace_products')
        .update({
          'title': title.trim(),
          'price_cents': priceCents,
          'currency': currency,
          'description': description?.trim(),
          'cultural_story': culturalStory?.trim(),
          'meetup_location': meetupLocation?.trim(),
          'image_url': imageUrl,
        })
        .eq('id', id)
        .eq('owner_id', user.id)
        .select()
        .single();

    return Product.fromMap(updated as Map<String, dynamic>);
  }

  static Future<void> deleteProduct(String productId) async {
    final user = _requireUser();
    await _client
        .from('marketplace_products')
        .delete()
        .eq('id', productId)
        .eq('owner_id', user.id);
  }

  static Future<List<SafeSpot>> fetchMySafeSpots() async {
    final user = _requireUser();
    final rows = await _client
        .from('marketplace_safe_spots')
        .select()
        .eq('owner_id', user.id)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows)
        .map(SafeSpot.fromMap)
        .toList();
  }

  static Future<SafeSpot> createSafeSpot({
    required String name,
    String? address,
    String? city,
    String? country,
    String? notes,
  }) async {
    final user = _requireUser();
    final inserted = await _client
        .from('marketplace_safe_spots')
        .insert({
          'owner_id': user.id,
          'name': name.trim(),
          'address': address?.trim(),
          'city': city?.trim(),
          'country': country?.trim(),
          'notes': notes?.trim(),
        })
        .select()
        .single();

    return SafeSpot.fromMap(inserted as Map<String, dynamic>);
  }

  static Future<void> deleteSafeSpot(String safeSpotId) async {
    final user = _requireUser();
    await _client
        .from('marketplace_safe_spots')
        .delete()
        .eq('id', safeSpotId)
        .eq('owner_id', user.id);
  }

  static Future<String> uploadProductImage(Uint8List bytes, {required String ext}) async {
    final user = _requireUser();
    final storage = _client.storage.from('product-images');
    final path = '${user.id}/product_${DateTime.now().millisecondsSinceEpoch}.$ext';

    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: 'image/$ext'),
    );

    return await storage.createSignedUrl(path, 60 * 60 * 24 * 365); // 1 year
  }

  static User _requireUser() {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Not signed in');
    }
    return user;
  }
}
