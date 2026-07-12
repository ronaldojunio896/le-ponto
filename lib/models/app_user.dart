import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { employee, admin }

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
    required this.hourlyRate,
    this.photoBase64,
  });

  final String id;
  final String name;
  final String email;
  final UserRole role;
  final bool active;
  final double hourlyRate;
  final String? photoBase64;

  bool get isAdmin => role == UserRole.admin;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppUser(
      id: doc.id,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: (data['role'] as String? ?? 'employee') == 'admin'
          ? UserRole.admin
          : UserRole.employee,
      active: data['active'] as bool? ?? true,
      hourlyRate: (data['hourlyRate'] as num?)?.toDouble() ?? 0,
      photoBase64: data['photoBase64'] as String?,
    );
  }

  Map<String, dynamic> toCreateMap() {
    return {
      'name': name,
      'email': email,
      'role': role.name,
      'active': active,
      'hourlyRate': hourlyRate,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
