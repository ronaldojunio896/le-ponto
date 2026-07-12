import 'package:cloud_firestore/cloud_firestore.dart';

class AppUpdateConfig {
  const AppUpdateConfig({
    required this.latestBuildNumber,
    required this.minimumBuildNumber,
    required this.latestVersionName,
    required this.apkUrl,
    required this.message,
    required this.required,
    required this.enabled,
  });

  final int latestBuildNumber;
  final int minimumBuildNumber;
  final String latestVersionName;
  final String apkUrl;
  final String message;
  final bool required;
  final bool enabled;

  bool hasUpdateFor(int currentBuildNumber) {
    return enabled && latestBuildNumber > currentBuildNumber;
  }

  bool isMandatoryFor(int currentBuildNumber) {
    return enabled && (required || currentBuildNumber < minimumBuildNumber);
  }

  factory AppUpdateConfig.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppUpdateConfig(
      latestBuildNumber: (data['latestBuildNumber'] as num?)?.toInt() ?? 0,
      minimumBuildNumber: (data['minimumBuildNumber'] as num?)?.toInt() ?? 0,
      latestVersionName: data['latestVersionName'] as String? ?? '',
      apkUrl: data['apkUrl'] as String? ?? '',
      message: data['message'] as String? ?? 'Existe uma nova versao do Le Ponto.',
      required: data['required'] as bool? ?? false,
      enabled: data['enabled'] as bool? ?? true,
    );
  }
}