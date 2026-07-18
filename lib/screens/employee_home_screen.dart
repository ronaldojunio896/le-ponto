import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/punch.dart';
import '../models/remote_app_config.dart';
import '../models/weekly_summary.dart';
import '../models/workday_summary.dart';
import '../services/app_config_service.dart';
import '../services/attendance_service.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../widgets/app_credits.dart';
import '../widgets/user_avatar.dart';

class EmployeeHomeScreen extends StatefulWidget {
  const EmployeeHomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends State<EmployeeHomeScreen> {
  Timer? _calendarTimer;
  Timer? _departureTimer;
  late DateTime _todayStart;
  late DateTime _todayEnd;
  late DateTime _weekStart;
  late DateTime _weekEnd;
  bool _nearStoreNotified = false;
  bool _autoExitInProgress = false;
  int _autoExitCandidateCount = 0;
  DateTime? _departureNotifiedForDay;
  StreamSubscription? _locationSub;
  StreamSubscription? _approvalSub;
  late DateTime _approvalWatchStartedAt;
  final _seenApprovalIds = <String>{};

  @override
  void initState() {
    super.initState();
    _approvalWatchStartedAt = DateTime.now();
    _updateCalendarAnchors();
    _scheduleCalendarRefresh();
    _departureTimer = Timer.periodic(
        const Duration(minutes: 1), (_) => _checkDepartureReminder());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startArrivalWatcher();
      _startOvertimeApprovalWatcher();
      _checkDepartureReminder();
    });
  }

  @override
  void dispose() {
    _calendarTimer?.cancel();
    _departureTimer?.cancel();
    _locationSub?.cancel();
    _approvalSub?.cancel();
    super.dispose();
  }

  void _updateCalendarAnchors() {
    final now = DateTime.now();
    _todayStart = WorkdaySummary.dayStart(now);
    _todayEnd = WorkdaySummary.dayEnd(now);
    _weekStart = WorkdaySummary.paymentWeekStart(now);
    _weekEnd = WorkdaySummary.paymentWeekEnd(now);
  }

  void _scheduleCalendarRefresh() {
    _calendarTimer?.cancel();
    final now = DateTime.now();
    final nextDay = WorkdaySummary.dayEnd(now).add(const Duration(seconds: 1));
    _calendarTimer = Timer(nextDay.difference(now), () {
      if (!mounted) return;
      setState(_updateCalendarAnchors);
      _scheduleCalendarRefresh();
      _checkDepartureReminder();
    });
  }

  Future<void> _startArrivalWatcher() async {
    final attendance = context.read<AttendanceService>();
    final location = context.read<LocationService>();
    final notification = context.read<NotificationService>();
    final config = await context.read<AppConfigService>().currentConfig();
    final store = await attendance.watchStore().first;
    if (!mounted || store == null) return;
    _locationSub = location.positionStream().listen((position) async {
      final distance = location.distanceMeters(
        fromLatitude: position.latitude,
        fromLongitude: position.longitude,
        toLatitude: store.latitude,
        toLongitude: store.longitude,
      );
      if (distance <= store.radiusMeters && !_nearStoreNotified) {
        _nearStoreNotified = true;
        notification.showArrivalPrompt();
      }
      if (distance > store.radiusMeters + 80) {
        _nearStoreNotified = false;
      }
      final confirmedDistance = distance - position.accuracy;
      final reliableReading = position.accuracy <= 40;
      if (reliableReading &&
          confirmedDistance >= config.autoExitDistanceMeters) {
        _autoExitCandidateCount += 1;
      } else {
        _autoExitCandidateCount = 0;
      }
      if (_autoExitCandidateCount >= 2) {
        await _tryAutoExit(distance);
      }
    });
  }

  void _startOvertimeApprovalWatcher() {
    final firestore = context.read<FirebaseFirestore>();
    final notification = context.read<NotificationService>();
    _approvalSub = firestore
        .collection('overtimeApprovals')
        .where('employeeId', isEqualTo: widget.user.id)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final doc = change.doc;
        if (!_seenApprovalIds.add(doc.id)) continue;
        final data = doc.data();
        if (data == null) continue;
        final createdAt = data['createdAt'];
        if (createdAt is! Timestamp ||
            !createdAt.toDate().isAfter(_approvalWatchStartedAt)) {
          continue;
        }
        final paymentDate = data['paymentDate'];
        final minutes = (data['minutes'] as num?)?.toInt() ?? 0;
        final amount = (data['amount'] as num?)?.toDouble() ?? 0;
        final paymentDateText = paymentDate is Timestamp
            ? DateFormat('dd/MM/yyyy', 'pt_BR').format(paymentDate.toDate())
            : 'data informada';
        final amountText = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
            .format(amount);
        final minutesText = formatSeconds(minutes * 60, compact: true);
        notification.showOvertimeApprovalAlert(
          paymentDateText: paymentDateText,
          amountText: amountText,
          minutesText: minutesText,
        );
      }
    });
  }

  Future<void> _tryAutoExit(double distanceMeters) async {
    if (_autoExitInProgress) return;
    _autoExitInProgress = true;
    final attendance = context.read<AttendanceService>();
    final notification = context.read<NotificationService>();
    try {
      final todayStart = WorkdaySummary.dayStart(DateTime.now());
      final config = await context.read<AppConfigService>().currentConfig();
      final punches = await attendance
          .watchPunchesForUser(
              widget.user.id, todayStart, WorkdaySummary.dayEnd(todayStart))
          .first;
      final summary =
          WorkdaySummary(day: todayStart, punches: punches, config: config);
      if (!summary.canAutoExit) return;
      await attendance.registerPunch(
        PunchType.exit,
        justification:
            'Saida automatica ao sair de ${distanceMeters.toStringAsFixed(0)} m da loja.',
        autoRegistered: true,
      );
      _autoExitCandidateCount = 0;
      await Future<void>.delayed(const Duration(seconds: 1));
      final updated = await attendance
          .watchPunchesForUser(
              widget.user.id, todayStart, WorkdaySummary.dayEnd(todayStart))
          .first;
      final updatedSummary =
          WorkdaySummary(day: todayStart, punches: updated, config: config);
      final overtime =
          formatSeconds(updatedSummary.overtimeSeconds(), compact: true);
      notification.showAutoExitPrompt(overtime);
      if (mounted) _showExitComplete(updatedSummary);
    } catch (_) {
      // The watcher runs often. Validation errors are expected when there is no open shift.
    } finally {
      _autoExitInProgress = false;
    }
  }

  Future<void> _checkDepartureReminder() async {
    if (!mounted) return;
    final todayStart = WorkdaySummary.dayStart(DateTime.now());
    if (_departureNotifiedForDay == todayStart) return;
    final attendance = context.read<AttendanceService>();
    final notification = context.read<NotificationService>();
    try {
      final punches = await attendance
          .watchPunchesForUser(
              widget.user.id, todayStart, WorkdaySummary.dayEnd(todayStart))
          .first;
      if (!mounted) return;
      final config = await context.read<AppConfigService>().currentConfig();
      final summary =
          WorkdaySummary(day: todayStart, punches: punches, config: config);
      if (summary.entry != null &&
          !summary.isClosed &&
          !summary.onLunch &&
          DateTime.now().isAfter(summary.scheduledExit)) {
        _departureNotifiedForDay = todayStart;
        await notification.showDeparturePrompt();
      }
    } catch (_) {
      // Reminder is best effort.
    }
  }

  Future<void> _register(PunchType type) async {
    final attendance = context.read<AttendanceService>();
    try {
      await attendance.registerPunch(type);
      if (!mounted) return;
      if (type == PunchType.exit) {
        await _showLatestExitComplete();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${type.label} registrada.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      final message = error.toString();
      if (!message.toLowerCase().contains('fora do raio')) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      final justification = await _askJustification(message);
      if (!mounted || justification == null || justification.trim().isEmpty) {
        return;
      }
      try {
        await attendance.registerPunch(type, justification: justification);
        if (!mounted) return;
        if (type == PunchType.exit) {
          await _showLatestExitComplete();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${type.label} registrada.')),
          );
        }
      } catch (retryError) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$retryError')));
      }
    }
  }

  Future<void> _showLatestExitComplete() async {
    final attendance = context.read<AttendanceService>();
    final todayStart = WorkdaySummary.dayStart(DateTime.now());
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final punches = await attendance
        .watchPunchesForUser(
            widget.user.id, todayStart, WorkdaySummary.dayEnd(todayStart))
        .first;
    if (!mounted) return;
    final config = await context.read<AppConfigService>().currentConfig();
    _showExitComplete(
        WorkdaySummary(day: todayStart, punches: punches, config: config));
  }

  Future<void> _showExitComplete(WorkdaySummary summary) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Expediente encerrado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.4, end: 1),
              duration: const Duration(milliseconds: 650),
              curve: Curves.elasticOut,
              builder: (context, value, child) =>
                  Transform.scale(scale: value, child: child),
              child: Icon(
                Icons.check_circle,
                color: Theme.of(context).colorScheme.primary,
                size: 72,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Extras liquidas hoje: ${formatSeconds(summary.overtimeSeconds(), compact: true)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context), child: const Text('Ok')),
        ],
      ),
    );
  }

  Future<String?> _askJustification(String reason) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Justificar ponto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(reason),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Justificativa'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Enviar')),
        ],
      ),
    );
  }

  Future<void> _linkGoogleAccount() async {
    try {
      await context.read<AuthService>().linkCurrentUserWithGoogle();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conta Google vinculada.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel vincular Google: $error')),
      );
    }
  }

  Future<void> _pickProfilePhoto() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Foto de perfil entra na proxima atualizacao.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attendance = context.watch<AttendanceService>();
    final configService = context.watch<AppConfigService>();

    return StreamBuilder<RemoteAppConfig>(
      stream: configService.watchConfig(),
      builder: (context, configSnapshot) {
        final config = configSnapshot.data ?? RemoteAppConfig.defaults();
        final weekNumber =
            WorkdaySummary.configuredPaymentWeekNumber(DateTime.now(), config);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Le Ponto'),
            actions: [
              IconButton(
                tooltip: 'Creditos',
                onPressed: () => showAppCreditsDialog(context),
                icon: const Icon(Icons.info_outline),
              ),
              IconButton(
                tooltip: 'Sair',
                onPressed: context.read<AuthService>().signOut,
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ProfileHeader(
                user: widget.user,
                onPickPhoto: _pickProfilePhoto,
                onLinkGoogle: _linkGoogleAccount,
              ),
              const SizedBox(height: 16),
              const _ClockCard(),
              const SizedBox(height: 16),
              _EmployeeWeeklySummary(
                user: widget.user,
                weekStart: _weekStart,
                weekEnd: _weekEnd,
                weekNumber: weekNumber,
                config: config,
              ),
              const SizedBox(height: 16),
              StreamBuilder<List<Punch>>(
                stream: attendance.watchPunchesForUser(
                    widget.user.id, _todayStart, _todayEnd),
                builder: (context, snapshot) {
                  final punches = snapshot.data ?? [];
                  final summary = WorkdaySummary(
                    day: _todayStart,
                    punches: punches,
                    config: config,
                  );
                  return _TodayPanel(
                    summary: summary,
                    onRegister: _register,
                  );
                },
              ),
              const SizedBox(height: 24),
              Text('Hoje', style: Theme.of(context).textTheme.titleLarge),
              _PunchList(
                  stream: attendance.watchPunchesForUser(
                      widget.user.id, _todayStart, _todayEnd)),
              const SizedBox(height: 16),
              Text('Semana $weekNumber',
                  style: Theme.of(context).textTheme.titleLarge),
              _PunchList(
                  stream: attendance.watchPunchesForUser(
                      widget.user.id, _weekStart, _weekEnd)),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.onPickPhoto,
    required this.onLinkGoogle,
  });

  final AppUser user;
  final VoidCallback onPickPhoto;
  final VoidCallback onLinkGoogle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        UserAvatar(name: user.name, photoBase64: user.photoBase64, radius: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name, style: Theme.of(context).textTheme.titleLarge),
              Text(user.email, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Vincular Google',
          onPressed: onLinkGoogle,
          icon: const Icon(Icons.account_circle),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Trocar foto',
          onPressed: onPickPhoto,
          icon: const Icon(Icons.photo_camera),
        ),
      ],
    );
  }
}

class _ClockCard extends StatefulWidget {
  const _ClockCard();

  @override
  State<_ClockCard> createState() => _ClockCardState();
}

class _ClockCardState extends State<_ClockCard> {
  final _time = DateFormat('HH:mm:ss', 'pt_BR');
  final _date = DateFormat('EEEE, dd/MM', 'pt_BR');
  late DateTime _now;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeStyle = Theme.of(context).textTheme.displayMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          children: [
            Text(_time.format(_now),
                textAlign: TextAlign.center, style: timeStyle),
            const SizedBox(height: 4),
            Text(_date.format(_now), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _TodayPanel extends StatelessWidget {
  const _TodayPanel({
    required this.summary,
    required this.onRegister,
  });

  final WorkdaySummary summary;
  final ValueChanged<PunchType> onRegister;

  @override
  Widget build(BuildContext context) {
    final actions = summary.nextActions;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _LiveOvertimeMetric(summary: summary)),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    label: 'Saida prevista',
                    value: DateFormat('HH:mm', 'pt_BR')
                        .format(summary.scheduledExit),
                    icon: Icons.flag,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (actions.isEmpty)
              FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.check_circle),
                label: const Text('Expediente encerrado'),
              )
            else
              _PunchActionButtons(actions: actions, onRegister: onRegister),
          ],
        ),
      ),
    );
  }
}

class _LiveOvertimeMetric extends StatefulWidget {
  const _LiveOvertimeMetric({required this.summary});

  final WorkdaySummary summary;

  @override
  State<_LiveOvertimeMetric> createState() => _LiveOvertimeMetricState();
}

class _LiveOvertimeMetricState extends State<_LiveOvertimeMetric> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _scheduleRefresh();
  }

  @override
  void didUpdateWidget(covariant _LiveOvertimeMetric oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summary != widget.summary) {
      _now = DateTime.now();
      _scheduleRefresh();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleRefresh() {
    _timer?.cancel();

    if (!widget.summary.isWorking) return;

    if (_now.isBefore(widget.summary.scheduledExit)) {
      final delay = widget.summary.scheduledExit.difference(_now) +
          const Duration(seconds: 1);
      _timer = Timer(delay, () {
        if (!mounted) return;
        setState(() => _now = DateTime.now());
        _scheduleRefresh();
      });
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    return _MetricTile(
      label: 'Extras liquidas',
      value: formatSeconds(widget.summary.overtimeSeconds(now: _now)),
      icon: Icons.timer,
    );
  }
}

class _PunchActionButtons extends StatelessWidget {
  const _PunchActionButtons({required this.actions, required this.onRegister});

  final List<PunchType> actions;
  final ValueChanged<PunchType> onRegister;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: actions
          .map((type) => SizedBox(
                width: actions.length == 1 ? double.infinity : 156,
                child: FilledButton.icon(
                  onPressed: () => onRegister(type),
                  icon: Icon(_iconFor(type)),
                  label: Text(type.label, textAlign: TextAlign.center),
                ),
              ))
          .toList(),
    );
  }

  IconData _iconFor(PunchType type) {
    return switch (type) {
      PunchType.entry => Icons.login,
      PunchType.lunchOut => Icons.restaurant,
      PunchType.lunchIn => Icons.work,
      PunchType.exit => Icons.logout,
    };
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final valueStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const Spacer(),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}

class _EmployeeWeeklySummary extends StatelessWidget {
  const _EmployeeWeeklySummary({
    required this.user,
    required this.weekStart,
    required this.weekEnd,
    required this.weekNumber,
    required this.config,
  });

  final AppUser user;
  final DateTime weekStart;
  final DateTime weekEnd;
  final int weekNumber;
  final RemoteAppConfig config;

  @override
  Widget build(BuildContext context) {
    final attendance = context.watch<AttendanceService>();
    final hourlyRate =
        user.hourlyRate <= 0 ? config.hourlyRateDefault : user.hourlyRate;
    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return StreamBuilder<List<Punch>>(
      stream: attendance.watchPunchesForUser(user.id, weekStart, weekEnd),
      builder: (context, snapshot) {
        final punches = snapshot.data ?? [];
        final summary = WeeklySummary.fromPunches(
          punches,
          hourlyRate,
          config: config,
        );
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.summarize),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Minha semana $weekNumber',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _MetricTile(
                  icon: Icons.add_alarm,
                  label: 'Extras liquidas',
                  value: formatSeconds(
                    summary.overtimeMinutes * 60,
                    compact: true,
                  ),
                ),
                const SizedBox(height: 8),
                _MetricTile(
                  icon: Icons.payments,
                  label: 'Valor estimado',
                  value: money.format(summary.amountToPay),
                ),
                const SizedBox(height: 8),
                _MetricTile(
                  icon: Icons.schedule,
                  label: 'Atrasos',
                  value: formatSeconds(
                    summary.lateMinutes * 60,
                    compact: true,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PunchList extends StatelessWidget {
  const _PunchList({required this.stream});

  final Stream<List<Punch>> stream;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd/MM HH:mm', 'pt_BR');
    return StreamBuilder<List<Punch>>(
      stream: stream,
      builder: (context, snapshot) {
        final punches = snapshot.data ?? [];
        if (punches.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Nenhum ponto registrado.'),
          );
        }
        return Column(
          children: punches
              .map((punch) => Card(
                    child: ListTile(
                      leading: Icon(
                        punch.autoRegistered
                            ? Icons.near_me
                            : punch.outOfRadius
                                ? Icons.warning_amber
                                : Icons.check_circle,
                      ),
                      title: Text(punch.type.label),
                      subtitle: Text(
                        '${formatter.format(punch.serverTime)} - ${punch.distanceMeters.toStringAsFixed(1)} m da loja${punch.manual ? ' - manual' : ''}',
                      ),
                    ),
                  ))
              .toList(),
        );
      },
    );
  }
}
