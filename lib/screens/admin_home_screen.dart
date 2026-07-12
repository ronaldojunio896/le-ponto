import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/punch.dart';
import '../models/remote_app_config.dart';
import '../models/store_config.dart';
import '../models/weekly_summary.dart';
import '../models/workday_summary.dart';
import '../services/app_config_service.dart';
import '../services/attendance_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/report_service.dart';
import '../widgets/user_avatar.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _index = 0;
  StreamSubscription<List<Punch>>? _punchAlertSub;
  final _seenPunchAlerts = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startPunchAlerts());
  }

  @override
  void dispose() {
    _punchAlertSub?.cancel();
    super.dispose();
  }

  void _startPunchAlerts() {
    final since = DateTime.now();
    final attendance = context.read<AttendanceService>();
    final notification = context.read<NotificationService>();
    _punchAlertSub = attendance.watchNewPunchesSince(since).listen((punches) {
      for (final punch in punches) {
        if (punch.employeeId == widget.user.id ||
            !_seenPunchAlerts.add(punch.id)) {
          continue;
        }
        notification.showPunchAlert(
          employeeName: punch.employeeName,
          punchLabel: punch.type.label,
        );
        if (!mounted) continue;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('${punch.employeeName} bateu ${punch.type.label}.')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _DashboardTab(),
      const _EmployeesTab(),
      const _PunchesTab(),
      const _ReportsTab(),
      const _StoreTab(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin - Le Ponto'),
        actions: [
          IconButton(
            tooltip: 'Sair',
            onPressed: context.read<AuthService>().signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.leaderboard), label: 'Ranking'),
          NavigationDestination(icon: Icon(Icons.group), label: 'Equipe'),
          NavigationDestination(icon: Icon(Icons.fact_check), label: 'Pontos'),
          NavigationDestination(
              icon: Icon(Icons.summarize), label: 'Relatorios'),
          NavigationDestination(icon: Icon(Icons.store), label: 'Loja'),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekStart = WorkdaySummary.paymentWeekStart(now);
    final weekEnd = WorkdaySummary.paymentWeekEnd(now);
    final configService = context.watch<AppConfigService>();
    return StreamBuilder<RemoteAppConfig>(
      stream: configService.watchConfig(),
      builder: (context, snapshot) {
        final config = snapshot.data ?? RemoteAppConfig.defaults();
        final weekNumber =
            WorkdaySummary.configuredPaymentWeekNumber(now, config);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _AdminRanking(
              weekStart: weekStart,
              weekEnd: weekEnd,
              weekNumber: weekNumber,
              config: config,
            ),
            const SizedBox(height: 16),
            _TeamStatusOverview(config: config),
            const SizedBox(height: 16),
            _TodayPunchesPreview(),
          ],
        );
      },
    );
  }
}

class _AdminRanking extends StatelessWidget {
  const _AdminRanking({
    required this.weekStart,
    required this.weekEnd,
    required this.weekNumber,
    required this.config,
  });

  final DateTime weekStart;
  final DateTime weekEnd;
  final int weekNumber;
  final RemoteAppConfig config;

  @override
  Widget build(BuildContext context) {
    final attendance = context.watch<AttendanceService>();
    final firestore = context.watch<FirebaseFirestore>();
    return StreamBuilder<List<Punch>>(
      stream: attendance.watchAllPunches(weekStart, weekEnd),
      builder: (context, punchSnapshot) {
        final punches = punchSnapshot.data ?? [];
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: firestore.collection('users').orderBy('name').snapshots(),
          builder: (context, userSnapshot) {
            final users = (userSnapshot.data?.docs ?? [])
                .map(AppUser.fromDoc)
                .where((user) => !user.isAdmin && user.active)
                .toList();
            final rows = users.map((user) {
              final userPunches = punches
                  .where((punch) => punch.employeeId == user.id)
                  .toList();
              return _RankingRowData(
                user: user,
                overtimeSeconds: _weekOvertime(userPunches, config),
              );
            }).toList()
              ..sort((a, b) => b.overtimeSeconds.compareTo(a.overtimeSeconds));
            final maxSeconds = rows.isEmpty
                ? 1
                : rows.first.overtimeSeconds.clamp(1, 1 << 31).toInt();
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.leaderboard),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ranking semana $weekNumber',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (rows.isEmpty)
                      const Text('Nenhum funcionario ativo.')
                    else
                      ...rows.map((row) =>
                          _RankingBar(row: row, maxSeconds: maxSeconds)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  int _weekOvertime(List<Punch> punches, RemoteAppConfig config) {
    final byDay = <DateTime, List<Punch>>{};
    for (final punch in punches) {
      final day = WorkdaySummary.dayStart(punch.serverTime);
      byDay.putIfAbsent(day, () => []).add(punch);
    }
    var total = 0;
    for (final entry in byDay.entries) {
      total +=
          WorkdaySummary(day: entry.key, punches: entry.value, config: config)
              .overtimeSeconds();
    }
    return total;
  }
}

class _TeamStatusOverview extends StatelessWidget {
  const _TeamStatusOverview({required this.config});

  final RemoteAppConfig config;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = WorkdaySummary.dayStart(now);
    final todayEnd = WorkdaySummary.dayEnd(todayStart);
    final attendance = context.watch<AttendanceService>();
    final firestore = context.watch<FirebaseFirestore>();

    return StreamBuilder<List<Punch>>(
      stream: attendance.watchAllPunches(todayStart, todayEnd),
      builder: (context, punchSnapshot) {
        final punches = punchSnapshot.data ?? [];
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: firestore.collection('users').orderBy('name').snapshots(),
          builder: (context, userSnapshot) {
            final users = (userSnapshot.data?.docs ?? [])
                .map(AppUser.fromDoc)
                .where((user) =>
                    user.active &&
                    (!user.isAdmin ||
                        punches.any((punch) => punch.employeeId == user.id)))
                .toList();
            final rows = users.map((user) {
              final userPunches = punches
                  .where((punch) => punch.employeeId == user.id)
                  .toList();
              final summary = WorkdaySummary(
                  day: todayStart, punches: userPunches, config: config);
              return _TeamStatusRowData(user: user, summary: summary, now: now);
            }).toList()
              ..sort((a, b) {
                final status = a.priority.compareTo(b.priority);
                if (status != 0) return status;
                return a.user.name.compareTo(b.user.name);
              });

            final workingCount =
                rows.where((row) => row.summary.isWorking).length;
            final lunchCount = rows.where((row) => row.summary.onLunch).length;
            final missingCount =
                rows.where((row) => row.summary.entry == null).length;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.groups),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Equipe agora',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatusPill(
                            icon: Icons.play_circle,
                            label: 'Trabalhando',
                            value: workingCount),
                        _StatusPill(
                            icon: Icons.restaurant,
                            label: 'Almoco',
                            value: lunchCount),
                        _StatusPill(
                            icon: Icons.pending_actions,
                            label: 'Sem entrada',
                            value: missingCount),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (rows.isEmpty)
                      const Text('Nenhum funcionario ativo.')
                    else
                      ...rows.map((row) => _TeamStatusTile(row: row)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text('$label: $value'),
        ],
      ),
    );
  }
}

class _TeamStatusTile extends StatelessWidget {
  const _TeamStatusTile({required this.row});

  final _TeamStatusRowData row;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('HH:mm', 'pt_BR');
    final theme = Theme.of(context);
    final entry = row.summary.entry;
    final exit = row.summary.exit;
    final latest =
        row.summary.punches.isEmpty ? null : row.summary.punches.last;
    final detail = row.summary.isWorking
        ? 'Entrada ${formatter.format(entry!.serverTime)}'
        : row.summary.onLunch
            ? 'Saiu para almoco ${formatter.format(row.summary.lunchOut!.serverTime)}'
            : row.summary.isClosed
                ? 'Saida ${formatter.format(exit!.serverTime)}'
                : latest == null
                    ? 'Ainda nao bateu entrada'
                    : '${latest.type.label} ${formatter.format(latest.serverTime)}';
    final overtime = row.summary.overtimeSeconds(now: row.now);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading:
          UserAvatar(name: row.user.name, photoBase64: row.user.photoBase64),
      title: Text(row.user.name),
      subtitle: Text(detail),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(row.icon, color: row.color(theme), size: 18),
              const SizedBox(width: 4),
              Text(row.label),
            ],
          ),
          if (overtime > 0) Text('+${formatSeconds(overtime, compact: true)}'),
        ],
      ),
    );
  }
}

class _TeamStatusRowData {
  const _TeamStatusRowData(
      {required this.user, required this.summary, required this.now});

  final AppUser user;
  final WorkdaySummary summary;
  final DateTime now;

  int get priority {
    if (summary.isWorking) return 0;
    if (summary.onLunch) return 1;
    if (summary.entry == null) return 2;
    if (summary.isClosed) return 3;
    return 4;
  }

  IconData get icon {
    if (summary.isWorking) return Icons.play_circle;
    if (summary.onLunch) return Icons.restaurant;
    if (summary.entry == null) return Icons.pending_actions;
    if (summary.isClosed) return Icons.check_circle;
    return Icons.warning_amber;
  }

  String get label {
    if (summary.isWorking) return 'Trabalhando';
    if (summary.onLunch) return 'Almoco';
    if (summary.entry == null) return 'Sem entrada';
    if (summary.isClosed) return 'Saiu';
    return 'Pendente';
  }

  Color color(ThemeData theme) {
    final colors = theme.colorScheme;
    if (summary.isWorking) return colors.primary;
    if (summary.onLunch) return colors.secondary;
    if (summary.entry == null) return colors.error;
    if (summary.isClosed) return colors.tertiary;
    return colors.outline;
  }
}

class _TodayPunchesPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = WorkdaySummary.dayStart(now);
    final formatter = DateFormat('HH:mm', 'pt_BR');
    return StreamBuilder<List<Punch>>(
      stream: context
          .watch<AttendanceService>()
          .watchAllPunches(todayStart, WorkdaySummary.dayEnd(todayStart)),
      builder: (context, snapshot) {
        final punches = snapshot.data ?? [];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pontos de hoje',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (punches.isEmpty)
                  const Text('Nenhum ponto registrado hoje.')
                else
                  ...punches.take(6).map(
                        (punch) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(punch.autoRegistered
                              ? Icons.near_me
                              : Icons.access_time),
                          title: Text(punch.employeeName),
                          subtitle: Text(
                              '${punch.type.label} - ${formatter.format(punch.serverTime)}'),
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

class _EmployeesTab extends StatelessWidget {
  const _EmployeesTab();

  @override
  Widget build(BuildContext context) {
    final users = context
        .watch<FirebaseFirestore>()
        .collection('users')
        .orderBy('name')
        .snapshots();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FilledButton.icon(
          onPressed: () => _showCreateEmployee(context),
          icon: const Icon(Icons.person_add),
          label: const Text('Cadastrar funcionario'),
        ),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: users,
          builder: (context, snapshot) {
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) return const Text('Nenhum usuario cadastrado.');
            return Column(
              children: docs.map((doc) {
                final user = AppUser.fromDoc(doc);
                return Card(
                  child: ListTile(
                    leading: UserAvatar(
                        name: user.name, photoBase64: user.photoBase64),
                    title: Text(user.name),
                    subtitle: Text('${user.email} - ${user.role.name}'),
                    trailing: Switch(
                      value: user.active,
                      onChanged: (value) =>
                          doc.reference.update({'active': value}),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _showCreateEmployee(BuildContext context) {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    final rate = TextEditingController(text: '0');
    var role = UserRole.employee;
    var saving = false;
    return showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Novo funcionario'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nome')),
                const SizedBox(height: 10),
                TextField(
                    controller: email,
                    decoration: const InputDecoration(labelText: 'E-mail')),
                const SizedBox(height: 10),
                TextField(
                    controller: password,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Senha inicial')),
                const SizedBox(height: 10),
                TextField(
                    controller: rate,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Valor por hora')),
                const SizedBox(height: 10),
                DropdownButtonFormField<UserRole>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Tipo de conta'),
                  items: const [
                    DropdownMenuItem(
                        value: UserRole.employee, child: Text('Funcionario')),
                    DropdownMenuItem(
                        value: UserRole.admin, child: Text('Admin')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => role = value ?? UserRole.employee),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        await context.read<AuthService>().createEmployeeAccount(
                              name: name.text,
                              email: email.text,
                              password: password.text,
                              role: role,
                              hourlyRate: double.tryParse(
                                      rate.text.replaceAll(',', '.')) ??
                                  0,
                            );
                        if (context.mounted) Navigator.pop(context);
                      } catch (error) {
                        setDialogState(() => saving = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text('Nao foi possivel cadastrar: $error')),
                          );
                        }
                      }
                    },
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PunchesTab extends StatelessWidget {
  const _PunchesTab();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start =
        WorkdaySummary.dayStart(now).subtract(const Duration(days: 7));
    final end = WorkdaySummary.dayEnd(now);
    final formatter = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
    return StreamBuilder<List<Punch>>(
      stream: context.watch<AttendanceService>().watchAllPunches(start, end),
      builder: (context, snapshot) {
        final punches = snapshot.data ?? [];
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton.icon(
              onPressed: () => _showManualPunch(context),
              icon: const Icon(Icons.add_task),
              label: const Text('Adicionar ponto manual'),
            ),
            const SizedBox(height: 16),
            if (punches.isEmpty)
              const Text('Nenhum ponto no periodo.')
            else
              ...punches.map((punch) {
                return Card(
                  child: ListTile(
                    leading: Icon(
                      punch.manual
                          ? Icons.edit_calendar
                          : punch.autoRegistered
                              ? Icons.near_me
                              : punch.edited
                                  ? Icons.edit_note
                                  : Icons.access_time,
                    ),
                    title: Text('${punch.employeeName} - ${punch.type.label}'),
                    subtitle: Text(
                        '${formatter.format(punch.serverTime)} - ${punch.distanceMeters.toStringAsFixed(1)} m'),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Editar',
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editPunch(context, punch),
                        ),
                        IconButton(
                          tooltip: 'Excluir',
                          icon: const Icon(Icons.delete),
                          color: Theme.of(context).colorScheme.error,
                          onPressed: () => _deletePunch(context, punch),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Future<void> _showManualPunch(BuildContext context) async {
    final usersSnapshot = await context
        .read<FirebaseFirestore>()
        .collection('users')
        .orderBy('name')
        .get();
    if (!context.mounted) return;
    final users = usersSnapshot.docs
        .map(AppUser.fromDoc)
        .where((user) => !user.isAdmin)
        .toList();
    AppUser? selected = users.isNotEmpty ? users.first : null;
    final date = TextEditingController(
        text: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()));
    final justification = TextEditingController();
    var type = PunchType.entry;
    var saving = false;
    return showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ponto manual'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<AppUser>(
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Funcionario'),
                  items: users
                      .map((user) =>
                          DropdownMenuItem(value: user, child: Text(user.name)))
                      .toList(),
                  onChanged: (value) => setDialogState(() => selected = value),
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: date,
                    decoration:
                        const InputDecoration(labelText: 'Data e hora')),
                const SizedBox(height: 10),
                DropdownButtonFormField<PunchType>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: PunchType.values
                      .map((value) => DropdownMenuItem(
                          value: value, child: Text(value.label)))
                      .toList(),
                  onChanged: (value) =>
                      setDialogState(() => type = value ?? PunchType.entry),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: justification,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Justificativa obrigatoria'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final employee = selected;
                      if (employee == null) return;
                      setDialogState(() => saving = true);
                      try {
                        final parsed =
                            DateFormat('yyyy-MM-dd HH:mm').parse(date.text);
                        await context
                            .read<AttendanceService>()
                            .createManualPunch(
                              employeeId: employee.id,
                              employeeName: employee.name,
                              serverTime: parsed,
                              type: type,
                              justification: justification.text,
                            );
                        if (context.mounted) Navigator.pop(context);
                      } catch (error) {
                        setDialogState(() => saving = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text('Nao foi possivel salvar: $error')),
                          );
                        }
                      }
                    },
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editPunch(BuildContext context, Punch punch) {
    final date = TextEditingController(
        text: DateFormat('yyyy-MM-dd HH:mm').format(punch.serverTime));
    final justification = TextEditingController();
    var type = punch.type;
    return showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar ponto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: date,
                  decoration: const InputDecoration(labelText: 'Data e hora')),
              const SizedBox(height: 10),
              DropdownButtonFormField<PunchType>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: PunchType.values
                    .map((value) => DropdownMenuItem(
                        value: value, child: Text(value.label)))
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => type = value ?? punch.type),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: justification,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Justificativa obrigatoria'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final parsed = DateFormat('yyyy-MM-dd HH:mm').parse(date.text);
                await context.read<AttendanceService>().editPunch(
                      punchId: punch.id,
                      newTime: parsed,
                      newType: type,
                      justification: justification.text,
                    );
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePunch(BuildContext context, Punch punch) {
    final justification = TextEditingController(text: 'Ponto de teste');
    var deleting = false;
    return showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Excluir ponto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${punch.employeeName} - ${punch.type.label}'),
              const SizedBox(height: 12),
              TextField(
                controller: justification,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Justificativa obrigatoria'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: deleting ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: deleting
                  ? null
                  : () async {
                      setDialogState(() => deleting = true);
                      try {
                        await context.read<AttendanceService>().deletePunch(
                              punchId: punch.id,
                              justification: justification.text,
                            );
                        if (context.mounted) Navigator.pop(context);
                      } catch (error) {
                        setDialogState(() => deleting = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text('Nao foi possivel excluir: $error')),
                          );
                        }
                      }
                    },
              icon: deleting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete),
              label: const Text('Excluir'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportsTab extends StatefulWidget {
  const _ReportsTab();

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  AppUser? _selected;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekStart = WorkdaySummary.paymentWeekStart(now);
    final nextWeek = WorkdaySummary.paymentWeekEnd(now);
    final usersStream = context
        .watch<FirebaseFirestore>()
        .collection('users')
        .orderBy('name')
        .snapshots();
    final configService = context.watch<AppConfigService>();

    return StreamBuilder<RemoteAppConfig>(
      stream: configService.watchConfig(),
      builder: (context, configSnapshot) {
        final config = configSnapshot.data ?? RemoteAppConfig.defaults();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: usersStream,
              builder: (context, snapshot) {
                final users = (snapshot.data?.docs ?? [])
                    .map(AppUser.fromDoc)
                    .where((u) => !u.isAdmin)
                    .toList();
                return DropdownButtonFormField<AppUser>(
                  initialValue: _selected,
                  decoration: const InputDecoration(labelText: 'Funcionario'),
                  items: users
                      .map((u) =>
                          DropdownMenuItem(value: u, child: Text(u.name)))
                      .toList(),
                  onChanged: (value) => setState(() => _selected = value),
                );
              },
            ),
            const SizedBox(height: 16),
            if (_selected != null)
              StreamBuilder<List<Punch>>(
                stream: context
                    .watch<AttendanceService>()
                    .watchPunchesForUser(_selected!.id, weekStart, nextWeek),
                builder: (context, snapshot) {
                  final punches = snapshot.data ?? [];
                  final hourlyRate = _selected!.hourlyRate == 0
                      ? config.hourlyRateDefault
                      : _selected!.hourlyRate;
                  final summary = WeeklySummary.fromPunches(
                    punches,
                    hourlyRate,
                    config: config,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SummaryCard(summary: summary),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () =>
                            context.read<ReportService>().exportPdf(
                                  employeeName: _selected!.name,
                                  punches: punches,
                                  summary: summary,
                                ),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Exportar PDF'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () =>
                            context.read<ReportService>().exportExcel(
                                  employeeName: _selected!.name,
                                  punches: punches,
                                  summary: summary,
                                ),
                        icon: const Icon(Icons.table_chart),
                        label: const Text('Exportar Excel'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => _approveOvertime(
                          context,
                          _selected!,
                          weekStart,
                          summary.overtimeMinutes,
                        ),
                        icon: const Icon(Icons.verified),
                        label: const Text('Aprovar horas extras'),
                      ),
                    ],
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _approveOvertime(
    BuildContext context,
    AppUser user,
    DateTime weekStart,
    int suggestedMinutes,
  ) {
    final minutes = TextEditingController(text: suggestedMinutes.toString());
    final justification = TextEditingController();
    final formatter = DateFormat('dd/MM/yyyy', 'pt_BR');
    var paymentDate = weekStart.add(const Duration(days: 6));
    return showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Aprovar horas extras'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: minutes,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Minutos aprovados'),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available),
                title: const Text('Pagamento previsto'),
                subtitle: Text(formatter.format(paymentDate)),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: paymentDate,
                    firstDate: DateTime(2026, 1, 1),
                    lastDate: DateTime(2035, 12, 31),
                    locale: const Locale('pt', 'BR'),
                  );
                  if (picked != null) {
                    setDialogState(() => paymentDate = picked);
                  }
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: justification,
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
              onPressed: () async {
                await context.read<AttendanceService>().approveOvertime(
                      employeeId: user.id,
                      weekStart: weekStart,
                      paymentDate: paymentDate,
                      minutes: int.tryParse(minutes.text) ?? 0,
                      hourlyRate: user.hourlyRate,
                      justification: justification.text,
                    );
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Horas extras aprovadas. Pagamento previsto para ${formatter.format(paymentDate)}.',
                    ),
                  ),
                );
              },
              child: const Text('Aprovar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final WeeklySummary summary;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resumo da semana',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('Horas normais: ${_minutes(summary.normalMinutes)}'),
            Text('Horas extras liquidas: ${_minutes(summary.overtimeMinutes)}'),
            Text('Atrasos: ${_minutes(summary.lateMinutes)}'),
            Text('Saidas antecipadas: ${_minutes(summary.earlyLeaveMinutes)}'),
            Text(
                'Valor das horas extras: ${money.format(summary.amountToPay)}'),
          ],
        ),
      ),
    );
  }

  String _minutes(int value) {
    final hours = value ~/ 60;
    final minutes = value % 60;
    return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
  }
}

class _StoreTab extends StatefulWidget {
  const _StoreTab();

  @override
  State<_StoreTab> createState() => _StoreTabState();
}

class _StoreTabState extends State<_StoreTab> {
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _hourlyRateDefault = TextEditingController();
  final _autoExitDistance = TextEditingController();
  final _duplicateWindow = TextEditingController();
  final _weekdayStart = TextEditingController();
  final _weekdayNoLunchExit = TextEditingController();
  final _weekdayLunchExit = TextEditingController();
  final _saturdayStart = TextEditingController();
  final _saturdayExit = TextEditingController();
  final _sundayStart = TextEditingController();
  final _sundayExit = TextEditingController();
  double _radius = 40;
  bool _loaded = false;
  bool _configLoaded = false;

  @override
  void dispose() {
    _latitude.dispose();
    _longitude.dispose();
    _hourlyRateDefault.dispose();
    _autoExitDistance.dispose();
    _duplicateWindow.dispose();
    _weekdayStart.dispose();
    _weekdayNoLunchExit.dispose();
    _weekdayLunchExit.dispose();
    _saturdayStart.dispose();
    _saturdayExit.dispose();
    _sundayStart.dispose();
    _sundayExit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firestore = context.watch<FirebaseFirestore>();
    final storeRef =
        firestore.collection('stores').doc('le-racoes-sao-gabriel');
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: storeRef.snapshots(),
      builder: (context, snapshot) {
        final doc = snapshot.data;
        if (doc == null || !doc.exists) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton.icon(
                onPressed: () async {
                  await storeRef.set({
                    'name': 'Le Racoes',
                    'address':
                        'R. Anapurus, 242 - Lj 03 - Sao Gabriel, Belo Horizonte - MG, 31980-140',
                    'latitude': -19.8587,
                    'longitude': -43.9248,
                    'radiusMeters': 40,
                    'coordinateNeedsReview': true,
                    'updatedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                },
                icon: const Icon(Icons.add_location_alt),
                label: const Text('Cadastrar loja padrao'),
              ),
            ),
          );
        }
        final store = StoreConfig.fromDoc(doc);
        if (!_loaded) {
          _latitude.text = store.latitude.toStringAsFixed(6);
          _longitude.text = store.longitude.toStringAsFixed(6);
          _radius = store.radiusMeters.clamp(30, 60).toDouble();
          _loaded = true;
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Le Racoes', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(store.address),
            const SizedBox(height: 16),
            TextField(
              controller: _latitude,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Latitude'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _longitude,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Longitude'),
            ),
            const SizedBox(height: 18),
            Text('Raio permitido: ${_radius.round()} m'),
            Slider(
              min: 30,
              max: 60,
              divisions: 30,
              value: _radius,
              label: '${_radius.round()} m',
              onChanged: (value) => setState(() => _radius = value),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                await storeRef.set({
                  'name': 'Le Racoes',
                  'address':
                      'R. Anapurus, 242 - Lj 03 - Sao Gabriel, Belo Horizonte - MG, 31980-140',
                  'latitude': double.parse(_latitude.text.replaceAll(',', '.')),
                  'longitude':
                      double.parse(_longitude.text.replaceAll(',', '.')),
                  'radiusMeters': _radius.round(),
                  'coordinateNeedsReview': false,
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Loja atualizada.')),
                  );
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('Salvar configuracao'),
            ),
            const SizedBox(height: 24),
            _buildRemoteConfigSection(context),
          ],
        );
      },
    );
  }

  Widget _buildRemoteConfigSection(BuildContext context) {
    final configService = context.watch<AppConfigService>();
    return StreamBuilder<RemoteAppConfig>(
      stream: configService.watchConfig(),
      builder: (context, snapshot) {
        final config = snapshot.data ?? RemoteAppConfig.defaults();
        if (!_configLoaded) {
          _loadRemoteConfig(config);
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Central remota',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                TextField(
                  controller: _hourlyRateDefault,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Valor padrao por hora'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _autoExitDistance,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Distancia para auto-saida (m)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _duplicateWindow,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Trava anti-duplicidade (segundos)'),
                ),
                const SizedBox(height: 16),
                Text('Segunda a sexta',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _timeRow(
                  _weekdayStart,
                  _weekdayNoLunchExit,
                  _weekdayLunchExit,
                  labels: const [
                    'Entrada',
                    'Saida sem almoco',
                    'Saida com almoco'
                  ],
                ),
                const SizedBox(height: 16),
                Text('Sabado', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _timeRow(
                  _saturdayStart,
                  _saturdayExit,
                  null,
                  labels: const ['Entrada', 'Saida', ''],
                ),
                const SizedBox(height: 16),
                Text('Domingo', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _timeRow(
                  _sundayStart,
                  _sundayExit,
                  null,
                  labels: const ['Entrada', 'Saida', ''],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _saveRemoteConfig(context),
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Salvar central remota'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _timeRow(
    TextEditingController first,
    TextEditingController second,
    TextEditingController? third, {
    required List<String> labels,
  }) {
    final fields = [
      Expanded(child: _timeField(first, labels[0])),
      const SizedBox(width: 8),
      Expanded(child: _timeField(second, labels[1])),
      if (third != null) ...[
        const SizedBox(width: 8),
        Expanded(child: _timeField(third, labels[2])),
      ],
    ];
    return Row(children: fields);
  }

  Widget _timeField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(labelText: label, hintText: '08:00'),
    );
  }

  void _loadRemoteConfig(RemoteAppConfig config) {
    _hourlyRateDefault.text =
        config.hourlyRateDefault.toStringAsFixed(2).replaceAll('.', ',');
    _autoExitDistance.text = config.autoExitDistanceMeters.toString();
    _duplicateWindow.text = config.duplicatePunchWindowSeconds.toString();
    _weekdayStart.text =
        WorkdaySchedule.formatMinute(config.weekdaySchedule.startMinute);
    _weekdayNoLunchExit.text =
        WorkdaySchedule.formatMinute(config.weekdaySchedule.noLunchExitMinute);
    _weekdayLunchExit.text =
        WorkdaySchedule.formatMinute(config.weekdaySchedule.lunchExitMinute);
    _saturdayStart.text =
        WorkdaySchedule.formatMinute(config.saturdaySchedule.startMinute);
    _saturdayExit.text =
        WorkdaySchedule.formatMinute(config.saturdaySchedule.noLunchExitMinute);
    _sundayStart.text =
        WorkdaySchedule.formatMinute(config.sundaySchedule.startMinute);
    _sundayExit.text =
        WorkdaySchedule.formatMinute(config.sundaySchedule.noLunchExitMinute);
    _configLoaded = true;
  }

  Future<void> _saveRemoteConfig(BuildContext context) async {
    final config = RemoteAppConfig(
      hourlyRateDefault:
          double.parse(_hourlyRateDefault.text.replaceAll(',', '.')),
      autoExitDistanceMeters: int.parse(_autoExitDistance.text),
      duplicatePunchWindowSeconds: int.parse(_duplicateWindow.text),
      paymentWeekBaseNumber: 72,
      paymentWeekBaseStart: DateTime(2026, 7, 5),
      weekdaySchedule: WorkdaySchedule(
        startMinute: _parseMinute(_weekdayStart.text),
        noLunchExitMinute: _parseMinute(_weekdayNoLunchExit.text),
        lunchExitMinute: _parseMinute(_weekdayLunchExit.text),
      ),
      saturdaySchedule: WorkdaySchedule(
        startMinute: _parseMinute(_saturdayStart.text),
        noLunchExitMinute: _parseMinute(_saturdayExit.text),
        lunchExitMinute: _parseMinute(_saturdayExit.text),
      ),
      sundaySchedule: WorkdaySchedule(
        startMinute: _parseMinute(_sundayStart.text),
        noLunchExitMinute: _parseMinute(_sundayExit.text),
        lunchExitMinute: _parseMinute(_sundayExit.text),
      ),
    );
    await context.read<AppConfigService>().saveConfig(config);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Central remota atualizada.')),
    );
  }

  int _parseMinute(String value) {
    final parts = value.trim().split(':');
    if (parts.length != 2) {
      throw FormatException('Horario invalido: $value');
    }
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    return (hour * 60 + minute).clamp(0, 23 * 60 + 59);
  }
}

class _RankingBar extends StatelessWidget {
  const _RankingBar({required this.row, required this.maxSeconds});

  final _RankingRowData row;
  final int maxSeconds;

  @override
  Widget build(BuildContext context) {
    final factor =
        row.overtimeSeconds == 0 ? 0.04 : row.overtimeSeconds / maxSeconds;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          UserAvatar(
              name: row.user.name,
              photoBase64: row.user.photoBase64,
              radius: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(row.user.name,
                            overflow: TextOverflow.ellipsis)),
                    Text(formatSeconds(row.overtimeSeconds, compact: true)),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: factor.clamp(0.04, 1).toDouble(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingRowData {
  const _RankingRowData({required this.user, required this.overtimeSeconds});

  final AppUser user;
  final int overtimeSeconds;
}
