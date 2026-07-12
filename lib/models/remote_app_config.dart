import 'package:cloud_firestore/cloud_firestore.dart';

class WorkdaySchedule {
  const WorkdaySchedule({
    required this.startMinute,
    required this.noLunchExitMinute,
    required this.lunchExitMinute,
  });

  final int startMinute;
  final int noLunchExitMinute;
  final int lunchExitMinute;

  static const weekday = WorkdaySchedule(
    startMinute: 8 * 60,
    noLunchExitMinute: 15 * 60,
    lunchExitMinute: 16 * 60,
  );

  static const saturday = WorkdaySchedule(
    startMinute: 8 * 60,
    noLunchExitMinute: 19 * 60,
    lunchExitMinute: 19 * 60,
  );

  static const sunday = WorkdaySchedule(
    startMinute: 8 * 60,
    noLunchExitMinute: 12 * 60,
    lunchExitMinute: 12 * 60,
  );

  factory WorkdaySchedule.fromMap(Map<String, dynamic>? data, WorkdaySchedule fallback) {
    if (data == null) return fallback;
    return WorkdaySchedule(
      startMinute: _readMinute(data['start'], fallback.startMinute),
      noLunchExitMinute: _readMinute(data['noLunchExit'], fallback.noLunchExitMinute),
      lunchExitMinute: _readMinute(data['lunchExit'], fallback.lunchExitMinute),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'start': formatMinute(startMinute),
      'noLunchExit': formatMinute(noLunchExitMinute),
      'lunchExit': formatMinute(lunchExitMinute),
    };
  }

  static int _readMinute(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    if (value is String) {
      final parts = value.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          return (hour * 60 + minute).clamp(0, 23 * 60 + 59);
        }
      }
    }
    return fallback;
  }

  static String formatMinute(int value) {
    final safe = value.clamp(0, 23 * 60 + 59);
    final hour = safe ~/ 60;
    final minute = safe % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}

class RemoteAppConfig {
  const RemoteAppConfig({
    required this.hourlyRateDefault,
    required this.autoExitDistanceMeters,
    required this.duplicatePunchWindowSeconds,
    required this.paymentWeekBaseNumber,
    required this.paymentWeekBaseStart,
    required this.weekdaySchedule,
    required this.saturdaySchedule,
    required this.sundaySchedule,
    this.backgroundImageUrl = '',
    this.logoUrl = '',
    this.updatedAt,
  });

  factory RemoteAppConfig.defaults() {
    return RemoteAppConfig(
      hourlyRateDefault: 8.08,
      autoExitDistanceMeters: 60,
      duplicatePunchWindowSeconds: 30,
      paymentWeekBaseNumber: 72,
      paymentWeekBaseStart: DateTime(2026, 7, 5),
      weekdaySchedule: WorkdaySchedule.weekday,
      saturdaySchedule: WorkdaySchedule.saturday,
      sundaySchedule: WorkdaySchedule.sunday,
    );
  }

  final double hourlyRateDefault;
  final int autoExitDistanceMeters;
  final int duplicatePunchWindowSeconds;
  final int paymentWeekBaseNumber;
  final DateTime paymentWeekBaseStart;
  final WorkdaySchedule weekdaySchedule;
  final WorkdaySchedule saturdaySchedule;
  final WorkdaySchedule sundaySchedule;
  final String backgroundImageUrl;
  final String logoUrl;
  final DateTime? updatedAt;

  WorkdaySchedule scheduleFor(DateTime day) {
    if (day.weekday == DateTime.saturday) return saturdaySchedule;
    if (day.weekday == DateTime.sunday) return sundaySchedule;
    return weekdaySchedule;
  }

  factory RemoteAppConfig.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final defaults = RemoteAppConfig.defaults();
    final data = doc.data();
    if (data == null) return defaults;
    final schedule = data['schedule'] as Map<String, dynamic>?;
    final updatedAt = data['updatedAt'];
    final baseStart = data['paymentWeekBaseStart'];
    return RemoteAppConfig(
      hourlyRateDefault: (data['hourlyRateDefault'] as num?)?.toDouble() ?? defaults.hourlyRateDefault,
      autoExitDistanceMeters:
          (data['autoExitDistanceMeters'] as num?)?.toInt() ?? defaults.autoExitDistanceMeters,
      duplicatePunchWindowSeconds:
          (data['duplicatePunchWindowSeconds'] as num?)?.toInt() ?? defaults.duplicatePunchWindowSeconds,
      paymentWeekBaseNumber:
          (data['paymentWeekBaseNumber'] as num?)?.toInt() ?? defaults.paymentWeekBaseNumber,
      paymentWeekBaseStart: baseStart is Timestamp ? baseStart.toDate() : defaults.paymentWeekBaseStart,
      weekdaySchedule: WorkdaySchedule.fromMap(
        schedule?['weekday'] as Map<String, dynamic>?,
        defaults.weekdaySchedule,
      ),
      saturdaySchedule: WorkdaySchedule.fromMap(
        schedule?['saturday'] as Map<String, dynamic>?,
        defaults.saturdaySchedule,
      ),
      sundaySchedule: WorkdaySchedule.fromMap(
        schedule?['sunday'] as Map<String, dynamic>?,
        defaults.sundaySchedule,
      ),
      backgroundImageUrl: data['backgroundImageUrl'] as String? ?? '',
      logoUrl: data['logoUrl'] as String? ?? '',
      updatedAt: updatedAt is Timestamp ? updatedAt.toDate() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'hourlyRateDefault': hourlyRateDefault,
      'autoExitDistanceMeters': autoExitDistanceMeters,
      'duplicatePunchWindowSeconds': duplicatePunchWindowSeconds,
      'paymentWeekBaseNumber': paymentWeekBaseNumber,
      'paymentWeekBaseStart': Timestamp.fromDate(paymentWeekBaseStart),
      'schedule': {
        'weekday': weekdaySchedule.toMap(),
        'saturday': saturdaySchedule.toMap(),
        'sunday': sundaySchedule.toMap(),
      },
      'backgroundImageUrl': backgroundImageUrl,
      'logoUrl': logoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
