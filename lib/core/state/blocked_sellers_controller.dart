import 'package:flutter_riverpod/legacy.dart';

import '../storage/local_store.dart';

/// Holds blocked seller phone numbers (local only for now).
final blockedSellersProvider =
    StateNotifierProvider<BlockedSellersController, Set<String>>((ref) {
  final store = ref.watch(localStoreProvider);
  final c = BlockedSellersController(store);
  c.load();
  return c;
});

class BlockedSellersController extends StateNotifier<Set<String>> {
  BlockedSellersController(this._store) : super(const <String>{});

  final LocalStore _store;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final keys = await _store.getBlockedSellerKeys();
    state = keys.toSet();
  }

  bool isBlocked(String phone) => state.contains(phone.trim());

  Future<void> block(String phone) async {
    final p = phone.trim();
    if (p.isEmpty) return;
    await _store.blockSeller(p);
    state = {...state, p};
  }

  Future<void> unblock(String phone) async {
    final p = phone.trim();
    if (p.isEmpty) return;
    await _store.unblockSeller(p);
    final next = {...state}..remove(p);
    state = next;
  }

  Future<void> clear() async {
    await _store.clearBlockedSellers();
    state = const <String>{};
  }
}
