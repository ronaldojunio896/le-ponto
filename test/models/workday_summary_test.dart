import 'package:flutter_test/flutter_test.dart';
import 'package:le_ponto/models/punch.dart';
import 'package:le_ponto/models/remote_app_config.dart';
import 'package:le_ponto/models/weekly_summary.dart';
import 'package:le_ponto/models/workday_summary.dart';

void main() {
  group('WorkdaySummary', () {
    test('soma extras de entrada antecipada e saida depois do horario', () {
      final day = DateTime(2026, 7, 7);
      final summary = WorkdaySummary(
        day: day,
        punches: [
          _punch(PunchType.entry, DateTime(2026, 7, 7, 7, 45)),
          _punch(PunchType.exit, DateTime(2026, 7, 7, 15, 30)),
        ],
      );

      expect(summary.overtimeSeconds(), 45 * 60);
    });

    test('nao projeta hora extra em jornada antiga sem saida', () {
      final day = DateTime(2026, 7, 7);
      final summary = WorkdaySummary(
        day: day,
        punches: [
          _punch(PunchType.entry, DateTime(2026, 7, 7, 8)),
        ],
      );

      expect(summary.overtimeSeconds(now: DateTime(2026, 7, 10, 20)), 0);
    });

    test('projeta hora extra apenas no proprio dia aberto', () {
      final day = DateTime(2026, 7, 7);
      final summary = WorkdaySummary(
        day: day,
        punches: [
          _punch(PunchType.entry, DateTime(2026, 7, 7, 8)),
        ],
      );

      expect(
          summary.overtimeSeconds(now: DateTime(2026, 7, 7, 15, 30)), 30 * 60);
    });
  });

  group('WeeklySummary', () {
    test('calcula valor usando apenas minutos extras liquidos', () {
      final summary = WeeklySummary.fromPunches(
        [
          _punch(PunchType.entry, DateTime(2026, 7, 7, 7, 30)),
          _punch(PunchType.exit, DateTime(2026, 7, 7, 15, 30)),
        ],
        8.08,
        config: RemoteAppConfig.defaults(),
      );

      expect(summary.overtimeMinutes, 60);
      expect(summary.amountToPay, closeTo(8.08, 0.001));
    });
  });
}

Punch _punch(PunchType type, DateTime serverTime) {
  return Punch(
    id: '${type.name}_${serverTime.microsecondsSinceEpoch}',
    employeeId: 'employee-1',
    employeeName: 'Funcionario',
    type: type,
    serverTime: serverTime,
    latitude: -19.855833,
    longitude: -43.918139,
    distanceMeters: 0,
    outOfRadius: false,
  );
}
