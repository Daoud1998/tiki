import 'package:flutter_riverpod/legacy.dart';
import '../storage/local_store.dart';

final recentlyViewedControllerProvider =
    StateNotifierProvider<RecentlyViewedController, List<String>>((ref) {
  final store = ref.watch(localStoreProvider);
  return RecentlyViewedController(store);
});
final recentlyViewedProvider = recentlyViewedControllerProvider;

class RecentlyViewedController extends StateNotifier<List<String>> {
  RecentlyViewedController(this._store) : super(_store.getRecentlyViewedIds());

  final LocalStore _store;
  static const int _max = 40;

  /// Optional manual refresh (rarely needed because we persist on every write).
  void reload() {
    state = _store.getRecentlyViewedIds();
  }

  // ✅ This fixes your ProductDetailsScreen error
  Future<void> markViewed(String id) async {
    await add(id);
  }

  Future<void> add(String id) async {
    final cleaned = id.trim();
    if (cleaned.isEmpty) return;

    final next = <String>[cleaned, ...state.where((e) => e != cleaned)];
    if (next.length > _max) {
      next.removeRange(_max, next.length);
    }
    state = next;
    await _store.setRecentlyViewedIds(next);
  }

  Future<void> clear() async {
    state = const <String>[];
    await _store.setRecentlyViewedIds(const <String>[]);
  }
}
