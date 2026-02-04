import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/kyc_models.dart';

/// Loads KYC settings from Firestore if available.
///
/// Firestore document: `app_settings/kyc`
///
/// If Firestore is not initialized or the doc doesn't exist, we fallback to defaults.
class KycSettingsRepository {
  const KycSettingsRepository();

  Future<KycSettings> load() async {
    try {
      final snap =
          await FirebaseFirestore.instance.doc('app_settings/kyc').get();
      final data = snap.data();
      if (data == null) return KycSettings.defaults();
      return KycSettings.fromMap(data);
    } catch (_) {
      // Covers: Firebase not initialized, permissions, offline, etc.
      return KycSettings.defaults();
    }
  }
}

final kycSettingsRepositoryProvider = Provider<KycSettingsRepository>((ref) {
  return const KycSettingsRepository();
});

final kycSettingsProvider = FutureProvider<KycSettings>((ref) async {
  final repo = ref.read(kycSettingsRepositoryProvider);
  return repo.load();
});

/// Live UI settings for the verification screen.
///
/// Firestore document: `app_settings/kyc`
///
/// This is streamed so Admin changes reflect immediately.
final kycVerificationUiSettingsProvider =
    StreamProvider.autoDispose<KycVerificationUiSettings>((ref) {
  final doc = FirebaseFirestore.instance.doc('app_settings/kyc');
  return doc.snapshots().map((snap) {
    final data = snap.data() ?? <String, dynamic>{};
    return KycVerificationUiSettings.fromMap(data);
  });
});
