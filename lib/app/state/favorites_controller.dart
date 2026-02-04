import 'package:flutter_riverpod/legacy.dart';

/// Simple favorites controller for mock mode.
///
/// Stores product IDs in-memory (Set{String}).
/// Later you can persist to Firestore / local storage.
final favoritesControllerProvider =
    StateNotifierProvider<FavoritesController, Set<String>>(
  (ref) => FavoritesController(),
);

class FavoritesController extends StateNotifier<Set<String>> {
  FavoritesController() : super(<String>{});

  bool isFavorite(String id) => state.contains(id);

  void toggle(String id) {
    final next = <String>{...state};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    state = next;
  }

  void clear() => state = <String>{};
}
