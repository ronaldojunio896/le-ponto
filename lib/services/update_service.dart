import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update_config.dart';

class UpdateService {
  UpdateService(this._firestore);

  final FirebaseFirestore _firestore;

  Stream<AppUpdateConfig?> watchUpdateConfig() {
    return _firestore.collection('system').doc('appUpdate').snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUpdateConfig.fromDoc(doc);
    });
  }

  Future<int> currentBuildNumber() async {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  Future<String> currentVersionLabel() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  Future<void> openDownload(String apkUrl) async {
    final uri = Uri.tryParse(apkUrl);
    if (uri == null || !uri.hasScheme) {
      throw Exception('Link de atualizacao invalido.');
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) throw Exception('Nao foi possivel abrir o link da atualizacao.');
  }
}