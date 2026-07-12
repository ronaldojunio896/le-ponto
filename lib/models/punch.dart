import 'package:cloud_firestore/cloud_firestore.dart';

enum PunchType {
  entry('Entrada'),
  lunchOut('Saida para almoco'),
  lunchIn('Volta do almoco'),
  exit('Saida final');

  const PunchType(this.label);
  final String label;
}

class Punch {
  const Punch({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.type,
    required this.serverTime,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
    required this.outOfRadius,
    this.justification,
    this.edited = false,
    this.autoRegistered = false,
    this.manual = false,
    this.createdAt,
  });

  final String id;
  final String employeeId;
  final String employeeName;
  final PunchType type;
  final DateTime serverTime;
  final double latitude;
  final double longitude;
  final double distanceMeters;
  final bool outOfRadius;
  final String? justification;
  final bool edited;
  final bool autoRegistered;
  final bool manual;
  final DateTime? createdAt;

  factory Punch.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final timestamp = data['serverTime'];
    final createdTimestamp = data['createdAt'];
    return Punch(
      id: doc.id,
      employeeId: data['employeeId'] as String? ?? '',
      employeeName: data['employeeName'] as String? ?? '',
      type: PunchType.values.firstWhere(
        (type) => type.name == data['type'],
        orElse: () => PunchType.entry,
      ),
      serverTime: timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      distanceMeters: (data['distanceMeters'] as num?)?.toDouble() ?? 0,
      outOfRadius: data['outOfRadius'] as bool? ?? false,
      justification: data['justification'] as String?,
      edited: data['edited'] as bool? ?? false,
      autoRegistered: data['autoRegistered'] as bool? ?? false,
      manual: data['manual'] as bool? ?? false,
      createdAt: createdTimestamp is Timestamp ? createdTimestamp.toDate() : null,
    );
  }
}
