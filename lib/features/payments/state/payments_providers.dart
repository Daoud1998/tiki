import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/payments_settings_repository.dart';

final paymentsSettingsRepositoryProvider =
    Provider<PaymentsSettingsRepository>((ref) {
  return PaymentsSettingsRepository(FirebaseFirestore.instance);
});

/// Enabled payment wallets configured by admin in app_settings/payments.
final paymentWalletsProvider =
    StreamProvider.autoDispose<List<PaymentWallet>>((ref) {
  return ref.watch(paymentsSettingsRepositoryProvider).watchEnabledWallets();
});
