import 'package:flutter_riverpod/legacy.dart';

import '../storage/local_store.dart';

/// Holds IDs of products reported by the user (local only).
final reportedProductsProvider =
    StateNotifierProvider<ReportedProductsController, Set<String>>((ref) {
  final store = ref.watch(localStoreProvider);
  final c = ReportedProductsController(store);
  c.load();
  return c;
});

class ReportedProductsController extends StateNotifier<Set<String>> {
  ReportedProductsController(this._store) : super(const <String>{});

  final LocalStore _store;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final ids = await _store.getReportedProductIds();
    state = ids.toSet();
  }

  bool isReported(String productId) => state.contains(productId);

  Future<void> add({
    required String productId,
    required String sellerPhone,
    required String reasonId,
    String? note,
  }) async {
    await _store.addProductReport(
      productId: productId,
      sellerPhone: sellerPhone,
      reasonId: reasonId,
      note: note,
    );
    state = {...state, productId};
  }

  Future<void> clear() async {
    await _store.setReportedProductIds(<String>[]);
    state = const <String>{};
  }
}
