import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/remote_app_config.dart';

class AppConfigService {
  AppConfigService(this._firestore);

  static const docPath = 'system/appConfig';

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _ref => _firestore.doc(docPath);

  Stream<RemoteAppConfig> watchConfig() {
    return _ref.snapshots().map(RemoteAppConfig.fromDoc);
  }

  Future<RemoteAppConfig> currentConfig() async {
    final doc = await _ref.get();
    return RemoteAppConfig.fromDoc(doc);
  }

  Future<void> saveConfig(RemoteAppConfig config) {
    return _ref.set(config.toMap(), SetOptions(merge: true));
  }
}
