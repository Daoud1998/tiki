import 'package:flutter_riverpod/legacy.dart';

import '../data/local_receipts_repository.dart';
import '../domain/service_receipt.dart';

final receiptsControllerProvider =
    StateNotifierProvider<ReceiptsController, List<ServiceReceipt>>((ref) {
  final repo = ref.watch(receiptsRepositoryProvider);
  return ReceiptsController(repo)..load();
});

class ReceiptsController extends StateNotifier<List<ServiceReceipt>> {
  ReceiptsController(this._repo) : super(const <ServiceReceipt>[]);

  final ReceiptsRepository _repo;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final items = await _repo.fetchAll();
    state = items;
  }

  Future<void> _persist() async {
    await _repo.saveAll(state);
  }

  ServiceReceipt? byId(String id) {
    final rid = id.trim();
    if (rid.isEmpty) return null;
    for (final r in state) {
      if (r.id == rid) return r;
    }
    return null;
  }

  Future<void> delete(String receiptId) async {
    final id = receiptId.trim();
    if (id.isEmpty) return;
    state = state.where((e) => e.id != id).toList(growable: false);
    await _persist();
  }

  Future<void> deleteMany(Iterable<String> ids) async {
    final set = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (set.isEmpty) return;
    state = state.where((e) => !set.contains(e.id)).toList(growable: false);
    await _persist();
  }

  Future<void> deleteAll() async {
    if (state.isEmpty) return;
    state = const <ServiceReceipt>[];
    await _persist();
  }

  Future<void> upsert(ServiceReceipt r) async {
    final i = state.indexWhere((e) => e.id == r.id);
    if (i < 0) {
      state = [r, ...state]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } else {
      final next = [...state];
      next[i] = r;
      next.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = next;
    }
    await _persist();
  }

  Future<void> addProductVipRequest({
    Map<String, dynamic>? metaExtra,
    required String productId,
    required String productTitle,
    required String pkgId,
    required int priceMru,
    required Duration duration,
    required String txId,
  }) async {
    final now = DateTime.now();
    final id = 'r_${now.millisecondsSinceEpoch}_vip_prod';
    final r = ServiceReceipt(
      id: id,
      kind: ServiceReceiptKind.productVip,
      status: ServiceReceiptStatus.pending,
      amountMru: priceMru,
      transactionId: txId.trim(),
      subjectId: productId.trim(),
      subjectTitleAr: productTitle.trim(),
      subjectTitleFr: productTitle.trim(),
      subjectTitleEn: productTitle.trim(),
      // Pending: we keep window empty until approved.
      createdAt: now,
      meta: <String, dynamic>{
        'pkgId': pkgId.trim(),
        'durationMs': duration.inMilliseconds,
        if (metaExtra != null) ...metaExtra,
      },
    );
    await upsert(r);
  }

  Future<void> activateLatestPendingProductVip({
    required String productId,
    required DateTime approvedAt,
  }) async {
    final pid = productId.trim();
    if (pid.isEmpty) return;

    final pending = state
        .where((r) =>
            r.kind == ServiceReceiptKind.productVip &&
            (r.subjectId ?? '') == pid &&
            r.status == ServiceReceiptStatus.pending)
        .toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (pending.isEmpty) return;
    final latest = pending.first;

    final dMs = (latest.meta['durationMs'] is num)
        ? (latest.meta['durationMs'] as num).toInt()
        : int.tryParse('${latest.meta['durationMs']}') ?? 0;
    final dur = Duration(milliseconds: dMs > 0 ? dMs : 0);

    final next = latest.copyWith(
      status: ServiceReceiptStatus.active,
      startsAt: approvedAt,
      endsAt: dur.inMilliseconds > 0 ? approvedAt.add(dur) : null,
    );

    await upsert(next);
  }

  Future<void> cancelLatestActiveProductVip({
    required String productId,
  }) async {
    final pid = productId.trim();
    if (pid.isEmpty) return;

    final active = state
        .where((r) =>
            r.kind == ServiceReceiptKind.productVip &&
            (r.subjectId ?? '') == pid &&
            r.status == ServiceReceiptStatus.active)
        .toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (active.isEmpty) return;
    final latest = active.first;
    await upsert(latest.copyWith(status: ServiceReceiptStatus.cancelled));
  }

  Future<void> expireIfNeeded() async {
    final now = DateTime.now();
    final next = <ServiceReceipt>[];
    bool changed = false;

    for (final r in state) {
      if (r.status == ServiceReceiptStatus.active) {
        final e = r.endsAt;
        if (e != null && now.isAfter(e)) {
          next.add(r.copyWith(status: ServiceReceiptStatus.expired));
          changed = true;
          continue;
        }
      }
      next.add(r);
    }

    if (!changed) return;
    next.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    state = next;
    await _persist();
  }

  
  Future<void> activateLatestPendingPromoAdVip({
    required String adId,
    required DateTime approvedAt,
  }) async {
    final aid = adId.trim();
    if (aid.isEmpty) return;

    final pending = state
        .where((r) =>
            r.kind == ServiceReceiptKind.promoAdVip &&
            (r.subjectId ?? '') == aid &&
            r.status == ServiceReceiptStatus.pending)
        .toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (pending.isEmpty) return;
    final latest = pending.first;

    final dMs = (latest.meta['durationMs'] is num)
        ? (latest.meta['durationMs'] as num).toInt()
        : int.tryParse('${latest.meta['durationMs']}') ?? 0;
    final dur = Duration(milliseconds: dMs > 0 ? dMs : 0);

    final next = latest.copyWith(
      status: ServiceReceiptStatus.active,
      startsAt: approvedAt,
      endsAt: dur.inMilliseconds > 0 ? approvedAt.add(dur) : null,
    );

    await upsert(next);
  }

Future<void> addPromoAdVipRequest({
    Map<String, dynamic>? metaExtra,
    required String adId,
    required String arTitle,
    required String frTitle,
    required String enTitle,
    required String pkgId,
    required int priceMru,
    required Duration duration,
    required String txId,
  }) async {
    final now = DateTime.now();
    final id = 'r_${now.millisecondsSinceEpoch}_vip_ad';
    final r = ServiceReceipt(
      id: id,
      kind: ServiceReceiptKind.promoAdVip,
      status: ServiceReceiptStatus.pending,
      amountMru: priceMru,
      transactionId: txId.trim(),
      subjectId: adId.trim(),
      subjectTitleAr: arTitle.trim(),
      subjectTitleFr: frTitle.trim(),
      subjectTitleEn: enTitle.trim(),
      createdAt: now,
      meta: <String, dynamic>{
        'pkgId': pkgId.trim(),
        'durationMs': duration.inMilliseconds,
        if (metaExtra != null) ...metaExtra,
      },
    );
    await upsert(r);
  }
}
