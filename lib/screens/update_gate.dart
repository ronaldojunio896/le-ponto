import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_update_config.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';

class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  late final Future<int> _currentBuildFuture;
  final _notifiedBuilds = <int>{};

  @override
  void initState() {
    super.initState();
    _currentBuildFuture = context.read<UpdateService>().currentBuildNumber();
  }

  void _notifyOnce(AppUpdateConfig config, int currentBuild) {
    if (!_notifiedBuilds.add(config.latestBuildNumber)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !config.hasUpdateFor(currentBuild)) return;
      context.read<NotificationService>().showUpdateAvailable(
            requiredUpdate: config.isMandatoryFor(currentBuild),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateService>();
    return FutureBuilder<int>(
      future: _currentBuildFuture,
      builder: (context, versionSnapshot) {
        final currentBuild = versionSnapshot.data;
        if (currentBuild == null) return widget.child;
        return StreamBuilder<AppUpdateConfig?>(
          stream: updates.watchUpdateConfig(),
          builder: (context, configSnapshot) {
            final config = configSnapshot.data;
            if (config == null || !config.hasUpdateFor(currentBuild)) {
              return widget.child;
            }
            _notifyOnce(config, currentBuild);
            if (config.isMandatoryFor(currentBuild)) {
              return _MandatoryUpdateScreen(
                config: config,
                currentBuild: currentBuild,
              );
            }
            return Stack(
              children: [
                widget.child,
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _OptionalUpdateBanner(config: config),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _MandatoryUpdateScreen extends StatelessWidget {
  const _MandatoryUpdateScreen({required this.config, required this.currentBuild});

  final AppUpdateConfig config;
  final int currentBuild;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.system_update,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Atualizacao obrigatoria',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    config.message,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Versao nova: ${config.latestVersionName} (${config.latestBuildNumber})',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    'Versao instalada: $currentBuild',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: config.apkUrl.isEmpty
                        ? null
                        : () => context.read<UpdateService>().openDownload(config.apkUrl),
                    icon: const Icon(Icons.download),
                    label: const Text('Baixar atualizacao'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionalUpdateBanner extends StatefulWidget {
  const _OptionalUpdateBanner({required this.config});

  final AppUpdateConfig config;

  @override
  State<_OptionalUpdateBanner> createState() => _OptionalUpdateBannerState();
}

class _OptionalUpdateBannerState extends State<_OptionalUpdateBanner> {
  var _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.system_update_alt),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Atualizacao disponivel',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    widget.config.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: widget.config.apkUrl.isEmpty
                  ? null
                  : () => context.read<UpdateService>().openDownload(widget.config.apkUrl),
              child: const Text('Baixar'),
            ),
            IconButton(
              tooltip: 'Fechar',
              onPressed: () => setState(() => _dismissed = true),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}