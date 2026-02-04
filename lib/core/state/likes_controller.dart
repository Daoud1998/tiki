import 'package:flutter_riverpod/legacy.dart';
import '../storage/local_store.dart';

/// Holds liked product IDs for the current device (guest) or user (later).
final likesProvider =
    StateNotifierProvider<LikesController, Set<String>>((ref) {
  final store = ref.read(localStoreProvider);
  return LikesController(store);
});

class LikesController extends StateNotifier<Set<String>> {
  LikesController(this._store) : super(_store.getLikedIds());

  final LocalStore _store;

  bool isLiked(String id) => state.contains(id);

  Future<void> toggle(String id) async {
    final next = Set<String>.from(state);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = next;
    await _store.setLikedIds(next);
  }

  Future<void> clear() async {
    state = <String>{};
    await _store.setLikedIds(state);
  }
}
