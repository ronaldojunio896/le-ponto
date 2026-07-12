import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    if (kIsWeb) return;
    await Permission.notification.request();
    const android = AndroidInitializationSettings('@drawable/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
  }

  Future<void> showArrivalPrompt() {
    return _show(
      id: 1,
      channelId: 'arrival_prompt',
      channelName: 'Aviso de chegada',
      title: 'Le Ponto',
      body: 'Voce chegou na loja. Nao esqueca de bater entrada.',
    );
  }

  Future<void> showDeparturePrompt() {
    return _show(
      id: 2,
      channelId: 'departure_prompt',
      channelName: 'Aviso de saida',
      title: 'Le Ponto',
      body: 'Seu horario acabou. Confira e bata a saida antes de ir embora.',
    );
  }

  Future<void> showAutoExitPrompt(String overtimeText) {
    return _show(
      id: 3,
      channelId: 'auto_exit',
      channelName: 'Saida automatica',
      title: 'Saida registrada',
      body: 'Voce saiu do raio da loja. Extras de hoje: $overtimeText.',
    );
  }

  Future<void> showPunchAlert({
    required String employeeName,
    required String punchLabel,
  }) {
    return _show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      channelId: 'admin_punch_alert_v2',
      channelName: 'Pontos dos funcionarios',
      title: '$employeeName bateu ponto',
      body: punchLabel,
      soundName: 'punch_alert',
    );
  }

  Future<void> showOvertimeApprovalAlert({
    required String paymentDateText,
    required String amountText,
    required String minutesText,
  }) {
    return _show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      channelId: 'overtime_approval_v2',
      channelName: 'Horas extras aprovadas',
      title: 'Horas extras aprovadas',
      body:
          '$minutesText aprovados. Pagamento previsto: $paymentDateText ($amountText).',
      soundName: 'overtime_approval',
    );
  }

  Future<void> showUpdateAvailable({required bool requiredUpdate}) {
    return _show(
      id: 4,
      channelId: 'app_update',
      channelName: 'Atualizacoes do app',
      title:
          requiredUpdate ? 'Atualizacao obrigatoria' : 'Atualizacao disponivel',
      body: requiredUpdate
          ? 'Baixe a nova versao do Le Ponto para continuar usando.'
          : 'Nova versao do Le Ponto disponivel para baixar.',
    );
  }

  Future<void> _show({
    required int id,
    required String channelId,
    required String channelName,
    required String title,
    required String body,
    String? soundName,
  }) {
    if (kIsWeb) return Future.value();
    final android = AndroidNotificationDetails(
      channelId,
      channelName,
      importance: Importance.high,
      priority: Priority.high,
      sound: soundName == null
          ? null
          : RawResourceAndroidNotificationSound(soundName),
      playSound: true,
    );
    return _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: android),
    );
  }
}
