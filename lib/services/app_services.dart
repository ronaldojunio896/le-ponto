import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'attendance_service.dart';
import 'app_config_service.dart';
import 'auth_service.dart';
import 'location_service.dart';
import 'notification_service.dart';
import 'report_service.dart';
import 'update_service.dart';

class AppServices {
  static List<SingleChildWidget> get providers => [
        Provider(create: (_) => FirebaseFirestore.instance),
        Provider(create: (_) => FirebaseAuth.instance),
        Provider(create: (_) => NotificationService()..initialize()),
        ProxyProvider<FirebaseFirestore, UpdateService>(
          update: (_, firestore, __) => UpdateService(firestore),
        ),
        ProxyProvider<FirebaseFirestore, AppConfigService>(
          update: (_, firestore, __) => AppConfigService(firestore),
        ),
        Provider(create: (_) => LocationService()),
        ProxyProvider2<FirebaseAuth, FirebaseFirestore, AuthService>(
          update: (_, auth, firestore, __) => AuthService(auth, firestore),
        ),
        ProxyProvider4<FirebaseFirestore, FirebaseAuth, LocationService, AppConfigService,
            AttendanceService>(
          update: (_, firestore, auth, location, config, __) =>
              AttendanceService(firestore, auth, location, config),
        ),
        Provider(create: (_) => ReportService()),
      ];
}
