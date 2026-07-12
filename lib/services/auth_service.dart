import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../models/app_user.dart';

class AuthService {
  AuthService(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<void> signInWithEmail(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
  }

  Future<void> sendPasswordReset(String email) {
    final cleanEmail = email.trim();
    if (cleanEmail.isEmpty) {
      throw Exception('Informe o e-mail primeiro.');
    }
    return _auth.sendPasswordResetEmail(email: cleanEmail);
  }

  GoogleSignIn _googleSignIn() {
    return GoogleSignIn(
      clientId: kIsWeb
          ? '957258916239-hjrfuck4f8n5ailv1ql4rsvvnjrvpki8.apps.googleusercontent.com'
          : null,
    );
  }

  Future<void> signInWithGoogle() async {
    final UserCredential userCredential;
    if (kIsWeb) {
      final provider = GoogleAuthProvider()..addScope('email');
      userCredential = await _auth.signInWithPopup(provider);
    } else {
      final googleUser = await _googleSignIn().signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      userCredential = await _auth.signInWithCredential(credential);
    }
    final user = userCredential.user;
    if (user == null) throw Exception('Nao foi possivel entrar com Google.');

    final profile = await _firestore.collection('users').doc(user.uid).get();
    if (!profile.exists || profile.data()?['active'] != true) {
      await _auth.signOut();
      await _googleSignIn().signOut();
      throw Exception(
        'Conta Google autenticada, mas este usuario nao esta ativo no Le Ponto.',
      );
    }
  }

  Future<void> linkCurrentUserWithGoogle() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception('Login obrigatorio.');

    if (kIsWeb) {
      final provider = GoogleAuthProvider()..addScope('email');
      await currentUser.linkWithPopup(provider);
    } else {
      final googleUser = await _googleSignIn().signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await currentUser.linkWithCredential(credential);
    }
  }

  Future<void> updateCurrentUserPhoto(String photoBase64) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Login obrigatorio.');
    await _firestore.collection('users').doc(user.uid).update({
      'photoBase64': photoBase64,
      'photoUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<bool> watchSetupComplete() {
    return _firestore.collection('system').doc('setup').snapshots().map((doc) {
      return doc.exists && doc.data()?['firstAdminCreated'] == true;
    });
  }

  Future<void> createFirstAdmin({
    required String name,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) throw Exception('Nao foi possivel criar o administrador.');
    await user.updateDisplayName(name.trim());

    final batch = _firestore.batch();
    batch.set(_firestore.collection('users').doc(user.uid), {
      'name': name.trim(),
      'email': email.trim(),
      'role': UserRole.admin.name,
      'active': true,
      'hourlyRate': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_firestore.collection('system').doc('setup'), {
      'firstAdminCreated': true,
      'firstAdminId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<String> createEmployeeAccount({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    required double hourlyRate,
  }) async {
    final uid = await _createAuthUserWithRest(email: email, password: password);
    await _firestore.collection('users').doc(uid).set({
      'name': name.trim(),
      'email': email.trim(),
      'role': role.name,
      'active': true,
      'hourlyRate': hourlyRate,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return uid;
  }

  Future<String> _createAuthUserWithRest({
    required String email,
    required String password,
  }) async {
    final apiKey = Firebase.app().options.apiKey;
    final uri = Uri.https(
      'identitytoolkit.googleapis.com',
      '/v1/accounts:signUp',
      {'key': apiKey},
    );
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'returnSecureToken': false,
      }),
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      final message = (decoded['error'] as Map<String, dynamic>?)?['message'];
      throw Exception(message ?? 'Erro ao criar usuario no Firebase Auth.');
    }
    final uid = decoded['localId'] as String?;
    if (uid == null || uid.isEmpty) {
      throw Exception('Firebase Auth nao retornou o ID do usuario.');
    }
    return uid;
  }

  Stream<AppUser?> watchCurrentUserProfile() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromDoc(doc);
    });
  }

  Future<void> signOut() async {
    if (!kIsWeb) await _googleSignIn().signOut();
    await _auth.signOut();
  }
}
