import 'package:flutter_riverpod/legacy.dart';

import '../storage/local_store.dart';
import 'auth_state.dart';

/// Per-seller preference: allow other users to find this seller's listings
/// by typing the seller phone number in Search.
///
/// In mock mode, this is stored locally per account (userId).
class SellerPhoneSearchController extends StateNotifier<bool> {
  SellerPhoneSearchController(this._store, this._userId)
      : super(_initial(_store, _userId));

  final LocalStore _store;
  final String? _userId;

  static bool _initial(LocalStore store, String? userId) {
    final id = (userId ?? '').trim();
    if (id.isEmpty) return true;
    return store.getSellerPhoneSearchEnabled(id);
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    final id = (_userId ?? '').trim();
    if (id.isEmpty) return;
    await _store.setSellerPhoneSearchEnabled(id, enabled);
  }
}

final sellerPhoneSearchEnabledProvider =
    StateNotifierProvider<SellerPhoneSearchController, bool>((ref) {
  final store = ref.watch(localStoreProvider);
  final auth = ref.watch(authControllerProvider);
  return SellerPhoneSearchController(store, auth.userId);
});
