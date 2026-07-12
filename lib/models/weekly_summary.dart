import 'punch.dart';
import 'remote_app_config.dart';
import 'workday_summary.dart';

class WeeklySummary {
  const WeeklySummary({
    required this.normalMinutes,
    required this.overtimeMinutes,
    required this.lateMinutes,
    required this.earlyLeaveMinutes,
    required this.amountToPay,
  });

  final int normalMinutes;
  final int overtimeMinutes;
  final int lateMinutes;
  final int earlyLeaveMinutes;
  final double amountToPay;

  static WeeklySummary fromPunches(
    List<Punch> punches,
    double hourlyRate, {
    RemoteAppConfig? config,
  }) {
    final effectiveConfig = config ?? RemoteAppConfig.defaults();
    final byDate = <DateTime, List<Punch>>{};
    for (final punch in punches) {
      final key = WorkdaySummary.dayStart(punch.serverTime);
      byDate.putIfAbsent(key, () => []).add(punch);
    }

    var workedSeconds = 0;
    var overtimeSeconds = 0;
    var lateSeconds = 0;
    var earlyLeaveSeconds = 0;

    for (final entry in byDate.entries) {
      final summary = WorkdaySummary(
        day: entry.key,
        punches: entry.value,
        config: effectiveConfig,
      );
      workedSeconds += summary.workedSeconds;
      overtimeSeconds += summary.overtimeSeconds(now: entry.key);
      lateSeconds += summary.lateSeconds;
      earlyLeaveSeconds += summary.earlyLeaveSeconds;
    }

    final normalSeconds = workedSeconds - overtimeSeconds;
    final normalMinutes = (normalSeconds < 0 ? 0 : normalSeconds) ~/ 60;
    final overtimeMinutes = overtimeSeconds ~/ 60;
    final amount = (overtimeMinutes / 60) * hourlyRate;

    return WeeklySummary(
      normalMinutes: normalMinutes,
      overtimeMinutes: overtimeMinutes,
      lateMinutes: lateSeconds ~/ 60,
      earlyLeaveMinutes: earlyLeaveSeconds ~/ 60,
      amountToPay: amount,
    );
  }
}
