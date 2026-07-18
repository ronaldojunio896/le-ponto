import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/punch.dart';
import '../models/remote_app_config.dart';
import '../models/store_config.dart';
import '../models/workday_summary.dart';
import 'app_config_service.dart';
import 'location_service.dart';

class AttendanceService {
  AttendanceService(this._firestore, this._auth, this._location, this._config);

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final LocationService _location;
  final AppConfigService _config;

  Stream<StoreConfig?> watchStore() {
    return _firestore
        .collection('stores')
        .doc('le-racoes-sao-gabriel')
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return StoreConfig.fromDoc(doc);
    });
  }

  Stream<List<Punch>> watchPunchesForUser(
      String userId, DateTime start, DateTime end) {
    return _firestore
        .collection('punches')
        .where('employeeId', isEqualTo: userId)
        .where('serverTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('serverTime', isLessThan: Timestamp.fromDate(end))
        .orderBy('serverTime', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Punch.fromDoc).toList());
  }

  Stream<List<Punch>> watchAllPunches(DateTime start, DateTime end) {
    return _firestore
        .collection('punches')
        .where('serverTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('serverTime', isLessThan: Timestamp.fromDate(end))
        .orderBy('serverTime', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Punch.fromDoc).toList());
  }

  Stream<List<Punch>> watchNewPunchesSince(DateTime since) {
    return _firestore
        .collection('punches')
        .where('createdAt', isGreaterThan: Timestamp.fromDate(since))
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Punch.fromDoc).toList());
  }

  Future<void> registerPunch(
    PunchType type, {
    String? justification,
    bool autoRegistered = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Login obrigatorio.');
    final config = await _config.currentConfig();
    final now = DateTime.now();
    final todayStart = WorkdaySummary.dayStart(now);

    await _ensurePunchSequence(
      user.uid,
      type,
      now: now,
      duplicateWindowSeconds: config.duplicatePunchWindowSeconds,
      config: config,
    );

    final storeDoc = await _firestore
        .collection('stores')
        .doc('le-racoes-sao-gabriel')
        .get();
    if (!storeDoc.exists) {
      throw Exception('Loja nao cadastrada.');
    }
    final store = StoreConfig.fromDoc(storeDoc);

    final profileDoc = await _firestore.collection('users').doc(user.uid).get();
    if (!profileDoc.exists) {
      throw Exception('Perfil do usuario nao encontrado.');
    }
    final profile = profileDoc.data() ?? {};
    if (profile['active'] != true) {
      throw Exception('Conta inativa. Procure a administracao da loja.');
    }

    final position = await _location.currentPosition();
    final distanceMeters = _location.distanceMeters(
      fromLatitude: position.latitude,
      fromLongitude: position.longitude,
      toLatitude: store.latitude,
      toLongitude: store.longitude,
    );
    final outOfRadius = distanceMeters > store.radiusMeters;
    final cleanJustification = justification?.trim();
    if (outOfRadius &&
        (cleanJustification == null || cleanJustification.isEmpty)) {
      throw Exception('Ponto fora do raio permitido. Informe justificativa.');
    }

    final punchData = {
      'employeeId': user.uid,
      'employeeName': profile['name'] as String? ?? user.email ?? '',
      'type': type.name,
      'storeId': store.id,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'storeLatitude': store.latitude,
      'storeLongitude': store.longitude,
      'distanceMeters': distanceMeters,
      'radiusMeters': store.radiusMeters,
      'outOfRadius': outOfRadius,
      'justification':
          cleanJustification?.isEmpty == true ? null : cleanJustification,
      'serverTime': FieldValue.serverTimestamp(),
      'edited': false,
      'autoRegistered': autoRegistered,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final punchRef = _firestore
        .collection('punches')
        .doc(_punchDocId(user.uid, todayStart, type));
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(punchRef);
      if (existing.exists) {
        throw Exception('Ponto duplicado ignorado. Aguarde alguns segundos.');
      }
      transaction.set(punchRef, punchData);
    });
  }

  Future<void> createManualPunch({
    required String employeeId,
    required String employeeName,
    required DateTime serverTime,
    required PunchType type,
    required String justification,
  }) async {
    final admin = _auth.currentUser;
    if (admin == null) throw Exception('Login obrigatorio.');
    if (justification.trim().isEmpty) {
      throw Exception('Justificativa obrigatoria.');
    }

    final adminDoc = await _firestore.collection('users').doc(admin.uid).get();
    final adminData = adminDoc.data() ?? {};
    if (adminData['role'] != 'admin' || adminData['active'] != true) {
      throw Exception('Somente admin ativo pode cadastrar ponto manual.');
    }

    final storeDoc = await _firestore
        .collection('stores')
        .doc('le-racoes-sao-gabriel')
        .get();
    final store = storeDoc.exists ? StoreConfig.fromDoc(storeDoc) : null;

    await _firestore.collection('punches').add({
      'employeeId': employeeId,
      'employeeName': employeeName,
      'type': type.name,
      'storeId': store?.id ?? 'manual',
      'latitude': store?.latitude ?? 0,
      'longitude': store?.longitude ?? 0,
      'accuracy': 0,
      'storeLatitude': store?.latitude ?? 0,
      'storeLongitude': store?.longitude ?? 0,
      'distanceMeters': 0,
      'radiusMeters': store?.radiusMeters ?? 0,
      'outOfRadius': false,
      'justification': null,
      'serverTime': Timestamp.fromDate(serverTime),
      'edited': false,
      'autoRegistered': false,
      'manual': true,
      'manualJustification': justification.trim(),
      'createdBy': admin.uid,
      'createdByName': adminData['name'] as String? ?? admin.email ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> editPunch({
    required String punchId,
    required DateTime newTime,
    required PunchType newType,
    required String justification,
  }) async {
    final admin = _auth.currentUser;
    if (admin == null) throw Exception('Login obrigatorio.');
    if (justification.trim().isEmpty) {
      throw Exception('Justificativa obrigatoria.');
    }

    final adminDoc = await _firestore.collection('users').doc(admin.uid).get();
    final adminData = adminDoc.data() ?? {};
    final ref = _firestore.collection('punches').doc(punchId);
    final before = await ref.get();
    if (!before.exists) throw Exception('Ponto nao encontrado.');

    final update = {
      'serverTime': Timestamp.fromDate(newTime),
      'type': newType.name,
      'edited': true,
      'editJustification': justification.trim(),
      'editedBy': admin.uid,
      'editedAt': FieldValue.serverTimestamp(),
    };
    final logRef = _firestore.collection('changeLogs').doc();
    final batch = _firestore.batch();
    batch.update(ref, update);
    batch.set(logRef, {
      'entity': 'punch',
      'entityId': punchId,
      'action': 'edit',
      'before': before.data(),
      'after': {
        'serverTime': Timestamp.fromDate(newTime),
        'type': newType.name,
        'edited': true,
        'editJustification': justification.trim(),
        'editedBy': admin.uid,
      },
      'justification': justification.trim(),
      'adminId': admin.uid,
      'adminName': adminData['name'] as String? ?? admin.email ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> deletePunch({
    required String punchId,
    required String justification,
  }) async {
    final admin = _auth.currentUser;
    if (admin == null) throw Exception('Login obrigatorio.');
    if (justification.trim().isEmpty) {
      throw Exception('Justificativa obrigatoria.');
    }

    final adminDoc = await _firestore.collection('users').doc(admin.uid).get();
    final adminData = adminDoc.data() ?? {};
    if (adminData['role'] != 'admin' || adminData['active'] != true) {
      throw Exception('Somente admin ativo pode excluir ponto.');
    }

    final ref = _firestore.collection('punches').doc(punchId);
    final before = await ref.get();
    if (!before.exists) throw Exception('Ponto nao encontrado.');

    final logRef = _firestore.collection('changeLogs').doc();
    final batch = _firestore.batch();
    batch.delete(ref);
    batch.set(logRef, {
      'entity': 'punch',
      'entityId': punchId,
      'action': 'delete',
      'before': before.data(),
      'justification': justification.trim(),
      'adminId': admin.uid,
      'adminName': adminData['name'] as String? ?? admin.email ?? '',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> approveOvertime({
    required String employeeId,
    required DateTime weekStart,
    required DateTime paymentDate,
    required int minutes,
    required double hourlyRate,
    required String justification,
  }) async {
    final admin = _auth.currentUser;
    if (admin == null) throw Exception('Login obrigatorio.');
    if (justification.trim().isEmpty) {
      throw Exception('Justificativa obrigatoria.');
    }
    if (minutes < 0) {
      throw Exception('Minutos aprovados invalidos.');
    }
    if (hourlyRate <= 0) {
      throw Exception('Valor por hora invalido.');
    }
    final adminDoc = await _firestore.collection('users').doc(admin.uid).get();
    final adminData = adminDoc.data() ?? {};
    if (adminData['role'] != 'admin' || adminData['active'] != true) {
      throw Exception('Somente admin ativo pode aprovar horas extras.');
    }

    final safeWeekStart = WorkdaySummary.paymentWeekStart(weekStart);
    final approvalRef = _firestore
        .collection('overtimeApprovals')
        .doc(_approvalDocId(employeeId, safeWeekStart));
    final approvalData = {
      'employeeId': employeeId,
      'weekStart': Timestamp.fromDate(safeWeekStart),
      'paymentDate': Timestamp.fromDate(paymentDate),
      'minutes': minutes,
      'hourlyRate': hourlyRate,
      'amount': (minutes / 60) * hourlyRate,
      'justification': justification.trim(),
      'approvedBy': admin.uid,
      'approvedByName': adminData['name'] as String? ?? admin.email ?? '',
      'status': 'approved',
      'createdAt': FieldValue.serverTimestamp(),
    };
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(approvalRef);
      if (existing.exists) {
        throw Exception('Horas extras desta semana ja foram aprovadas.');
      }
      transaction.set(approvalRef, approvalData);
    });
  }

  Future<void> _ensurePunchSequence(
    String userId,
    PunchType type, {
    required DateTime now,
    required int duplicateWindowSeconds,
    required RemoteAppConfig config,
  }) async {
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final snapshot = await _firestore
        .collection('punches')
        .where('employeeId', isEqualTo: userId)
        .where('serverTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('serverTime', isLessThan: Timestamp.fromDate(end))
        .orderBy('serverTime', descending: true)
        .get();

    final punches = snapshot.docs.map(Punch.fromDoc).toList();
    final duplicateWindow = Duration(seconds: duplicateWindowSeconds);
    for (final punch in punches) {
      if (punch.type == type &&
          now.difference(punch.serverTime).abs() <= duplicateWindow) {
        throw Exception('Ponto duplicado ignorado. Aguarde alguns segundos.');
      }
    }

    final summary =
        WorkdaySummary(day: start, punches: punches, config: config);
    if (summary.nextActions.contains(type)) {
      return;
    }
    throw Exception(summary.expectedActionMessage(type));
  }

  String _punchDocId(String userId, DateTime day, PunchType type) {
    return '${_safeId(userId)}_${_dateKey(day)}_${type.name}';
  }

  String _approvalDocId(String employeeId, DateTime weekStart) {
    return '${_safeId(employeeId)}_${_dateKey(weekStart)}';
  }

  String _safeId(String value) {
    return value.replaceAll(RegExp(r'[/\\]'), '_');
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
