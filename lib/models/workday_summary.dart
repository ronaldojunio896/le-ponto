import 'punch.dart';
import 'remote_app_config.dart';

class WorkdaySummary {
  WorkdaySummary({
    required this.day,
    required List<Punch> punches,
    RemoteAppConfig? config,
  })  : config = config ?? RemoteAppConfig.defaults(),
        punches = [...punches]
          ..sort((a, b) => a.serverTime.compareTo(b.serverTime));

  static const startHour = 8;
  static const noLunchExitHour = 15;
  static const lunchExitHour = 16;
  static const autoExitDistanceMeters = 60;
  static const paymentWeekBaseNumber = 72;
  static final paymentWeekBaseStart = DateTime(2026, 7, 5);

  final DateTime day;
  final List<Punch> punches;
  final RemoteAppConfig config;

  WorkdaySchedule get schedule => config.scheduleFor(day);

  DateTime get scheduledStart => _dateWithMinute(schedule.startMinute);

  DateTime get scheduledExit => _dateWithMinute(
      hasLunch ? schedule.lunchExitMinute : schedule.noLunchExitMinute);

  Punch? get entry => _first(PunchType.entry);
  Punch? get lunchOut => _first(PunchType.lunchOut);
  Punch? get lunchIn => _first(PunchType.lunchIn);
  Punch? get exit => _first(PunchType.exit);

  bool get hasLunch => lunchOut != null || lunchIn != null;
  bool get isClosed => exit != null;
  bool get onLunch => lunchOut != null && lunchIn == null && exit == null;
  bool get isWorking => entry != null && exit == null && !onLunch;
  bool get canAutoExit => isWorking;

  int get earlyArrivalSeconds {
    final firstEntry = entry;
    if (firstEntry == null || !firstEntry.serverTime.isBefore(scheduledStart)) {
      return 0;
    }
    return scheduledStart.difference(firstEntry.serverTime).inSeconds;
  }

  int get lateExitSeconds {
    final finalExit = exit;
    if (finalExit == null || !finalExit.serverTime.isAfter(scheduledExit)) {
      return 0;
    }
    return finalExit.serverTime.difference(scheduledExit).inSeconds;
  }

  int projectedLateExitSeconds(DateTime now) {
    if (WorkdaySummary.dayStart(now) != WorkdaySummary.dayStart(day)) {
      return 0;
    }
    if (exit != null || entry == null || now.isBefore(scheduledExit)) {
      return 0;
    }
    return now.difference(scheduledExit).inSeconds;
  }

  int overtimeSeconds({DateTime? now}) {
    final grossOvertime = earlyArrivalSeconds +
        lateExitSeconds +
        projectedLateExitSeconds(now ?? DateTime.now());
    final deductions = lateSeconds + earlyLeaveSeconds;
    final netOvertime = grossOvertime - deductions;
    return netOvertime < 0 ? 0 : netOvertime;
  }

  int get workedSeconds {
    var total = 0;
    final firstEntry = entry;
    final lunchStart = lunchOut;
    final lunchEnd = lunchIn;
    final finalExit = exit;

    if (firstEntry == null) return 0;
    if (lunchStart != null) {
      total +=
          lunchStart.serverTime.difference(firstEntry.serverTime).inSeconds;
    } else if (finalExit != null) {
      total += finalExit.serverTime.difference(firstEntry.serverTime).inSeconds;
    }

    if (lunchEnd != null && finalExit != null) {
      total += finalExit.serverTime.difference(lunchEnd.serverTime).inSeconds;
    }

    return total < 0 ? 0 : total;
  }

  int get lateSeconds {
    final firstEntry = entry;
    if (firstEntry == null || !firstEntry.serverTime.isAfter(scheduledStart)) {
      return 0;
    }
    return firstEntry.serverTime.difference(scheduledStart).inSeconds;
  }

  int get earlyLeaveSeconds {
    final finalExit = exit;
    if (finalExit == null || !finalExit.serverTime.isBefore(scheduledExit)) {
      return 0;
    }
    return scheduledExit.difference(finalExit.serverTime).inSeconds;
  }

  List<PunchType> get nextActions {
    if (entry == null) return const [PunchType.entry];
    if (exit != null) return const [];
    if (lunchOut == null) return const [PunchType.lunchOut, PunchType.exit];
    if (lunchIn == null) return const [PunchType.lunchIn];
    return const [PunchType.exit];
  }

  String expectedActionMessage(PunchType attempted) {
    final labels = nextActions.map((type) => type.label).join(' ou ');
    if (labels.isEmpty) return 'Todos os pontos de hoje ja foram registrados.';
    return 'O proximo ponto esperado e $labels.';
  }

  static DateTime dayStart(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime dayEnd(DateTime date) =>
      dayStart(date).add(const Duration(days: 1));

  static DateTime paymentWeekStart(DateTime date) {
    final today = dayStart(date);
    return today.subtract(Duration(days: today.weekday % DateTime.daysPerWeek));
  }

  static DateTime paymentWeekEnd(DateTime date) =>
      paymentWeekStart(date).add(const Duration(days: 7));

  static int paymentWeekNumber(DateTime date) {
    final start = paymentWeekStart(date);
    final diff =
        start.difference(paymentWeekBaseStart).inDays ~/ DateTime.daysPerWeek;
    return paymentWeekBaseNumber + diff;
  }

  static int configuredPaymentWeekNumber(
      DateTime date, RemoteAppConfig config) {
    final start = paymentWeekStart(date);
    final baseStart = paymentWeekStart(config.paymentWeekBaseStart);
    final diff = start.difference(baseStart).inDays ~/ DateTime.daysPerWeek;
    return config.paymentWeekBaseNumber + diff;
  }

  Punch? _first(PunchType type) {
    for (final punch in punches) {
      if (punch.type == type) return punch;
    }
    return null;
  }

  DateTime _dateWithMinute(int minuteOfDay) {
    final hour = minuteOfDay ~/ 60;
    final minute = minuteOfDay % 60;
    return DateTime(day.year, day.month, day.day, hour, minute);
  }
}

String formatSeconds(int seconds, {bool compact = false}) {
  final safe = seconds < 0 ? 0 : seconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final remainingSeconds = safe % 60;
  if (compact) {
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
    }
    if (minutes > 0) {
      return '${minutes}min ${remainingSeconds.toString().padLeft(2, '0')}s';
    }
    return '${remainingSeconds}s';
  }
  return '${hours}h ${minutes.toString().padLeft(2, '0')}min ${remainingSeconds.toString().padLeft(2, '0')}s';
}
