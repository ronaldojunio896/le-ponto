import 'package:cloud_firestore/cloud_firestore.dart';

class StoreConfig {
  const StoreConfig({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final int radiusMeters;

  factory StoreConfig.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return StoreConfig(
      id: doc.id,
      name: data['name'] as String? ?? 'Le Racoes',
      address: data['address'] as String? ?? '',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      radiusMeters: (data['radiusMeters'] as num?)?.toInt() ?? 40,
    );
  }
}
