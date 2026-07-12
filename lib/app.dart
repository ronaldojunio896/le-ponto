import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models/app_user.dart';
import 'screens/admin_home_screen.dart';
import 'screens/employee_home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/update_gate.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

class LePontoApp extends StatelessWidget {
  const LePontoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Le Ponto',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const UpdateGate(child: AuthGate()),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();

        return StreamBuilder<AppUser?>(
          stream: auth.watchCurrentUserProfile(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final profile = profileSnapshot.data;
            if (profile == null) {
              return _MissingProfileAccount(onLogout: auth.signOut);
            }
            if (!profile.active) {
              return _BlockedAccount(onLogout: auth.signOut);
            }
            return profile.isAdmin
                ? AdminHomeScreen(user: profile)
                : EmployeeHomeScreen(user: profile);
          },
        );
      },
    );
  }
}

class _MissingProfileAccount extends StatelessWidget {
  const _MissingProfileAccount({required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_off, size: 56),
              const SizedBox(height: 16),
              Text('Perfil nao encontrado', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('Peca para o admin cadastrar este usuario no app.'),
              const SizedBox(height: 24),
              FilledButton(onPressed: onLogout, child: const Text('Sair')),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlockedAccount extends StatelessWidget {
  const _BlockedAccount({required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_clock, size: 56),
              const SizedBox(height: 16),
              Text('Conta inativa', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('Procure a administracao da loja para liberar seu acesso.'),
              const SizedBox(height: 24),
              FilledButton(onPressed: onLogout, child: const Text('Sair')),
            ],
          ),
        ),
      ),
    );
  }
}
