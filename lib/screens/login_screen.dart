import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await context
          .read<AuthService>()
          .signInWithEmail(_email.text, _password.text);
    } catch (error) {
      if (!mounted) return;
      await _showLoginError('Nao foi possivel entrar', error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      await context.read<AuthService>().signInWithGoogle();
    } catch (error) {
      if (!mounted) return;
      await _showLoginError('Nao foi possivel entrar com Google', error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    setState(() => _loading = true);
    try {
      await context.read<AuthService>().sendPasswordReset(_email.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Link de senha enviado para o e-mail informado.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel enviar o link: $error')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createFirstAdmin() async {
    setState(() => _loading = true);
    try {
      await context.read<AuthService>().createFirstAdmin(
            name: _name.text,
            email: _email.text,
            password: _password.text,
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nao foi possivel criar o admin: $error')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showLoginError(String title, Object error) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SelectableText(error.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return StreamBuilder<bool>(
      stream: auth.watchSetupComplete(),
      builder: (context, snapshot) {
        final setupComplete = snapshot.data ?? true;
        return _LoginShell(
          children: setupComplete ? _loginFields() : _setupFields(context),
        );
      },
    );
  }

  List<Widget> _loginFields() {
    return [
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'E-mail'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Senha'),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _loading ? null : _submit,
        icon: _loading
            ? const SizedBox.square(
                dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.login),
        label: const Text('Entrar'),
      ),
      const SizedBox(height: 10),
      if (!kIsWeb)
        OutlinedButton.icon(
          onPressed: _loading ? null : _signInWithGoogle,
          icon: const Icon(Icons.account_circle),
          label: const Text('Entrar com Google'),
        ),
      if (kIsWeb)
        OutlinedButton.icon(
          onPressed: _loading ? null : _sendPasswordReset,
          icon: const Icon(Icons.mark_email_read),
          label: const Text('Receber link de senha'),
        ),
      const SizedBox(height: 10),
      const Text(
        'Este aparelho entra sozinho nos proximos acessos.',
        textAlign: TextAlign.center,
      ),
    ];
  }

  List<Widget> _setupFields(BuildContext context) {
    return [
      Text(
        'Primeiro acesso',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Crie o usuario admin para cadastrar funcionarios e acompanhar os pontos.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Nome do admin'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'E-mail'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Senha'),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _loading ? null : _createFirstAdmin,
        icon: _loading
            ? const SizedBox.square(
                dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.admin_panel_settings),
        label: const Text('Criar admin'),
      ),
    ];
  }
}

class _LoginShell extends StatelessWidget {
  const _LoginShell({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.access_time_filled,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Le Ponto',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text('Le Racoes', textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  ...children,
                  const SizedBox(height: 24),
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final info = snapshot.data;
                      final text = info == null
                          ? 'Versao do app'
                          : 'Versao ${info.version} (${info.buildNumber})';
                      return Text(
                        text,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    },
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
