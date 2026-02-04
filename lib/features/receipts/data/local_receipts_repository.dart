import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';
import '../domain/service_receipt.dart';

abstract class ReceiptsRepository {
  Future<List<ServiceReceipt>> fetchAll();
  Future<void> saveAll(List<ServiceReceipt> receipts);
}

final receiptsRepositoryProvider = Provider<ReceiptsRepository>((ref) {
  final store = ref.watch(localStoreProvider);
  return LocalReceiptsRepository(store);
});

class LocalReceiptsRepository implements ReceiptsRepository {
  LocalReceiptsRepository(this._store);

  final LocalStore _store;

  @override
  Future<List<ServiceReceipt>> fetchAll() async {
    final raw = _store.getServiceReceiptsJson();
    if (raw == null || raw.trim().isEmpty) return <ServiceReceipt>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <ServiceReceipt>[];

      final out = <ServiceReceipt>[];
      for (final item in decoded) {
        final r = ServiceReceipt.tryFromJson(item);
        if (r != null) out.add(r);
      }

      // Newest first.
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    } catch (_) {
      return <ServiceReceipt>[];
    }
  }

  @override
  Future<void> saveAll(List<ServiceReceipt> receipts) async {
    final list = receipts.map((e) => e.toJson()).toList(growable: false);
    await _store.setServiceReceiptsJson(jsonEncode(list));
  }
}
