import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const LePontoBootstrap());
}

class LePontoBootstrap extends StatelessWidget {
  const LePontoBootstrap({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: AppServices.providers,
      child: const LePontoApp(),
    );
  }
}
