import 'dart:math';

import 'package:flutter_riverpod/legacy.dart';
import 'package:tiki/features/publish/presentation/data/publish_drafts_repository.dart';
import 'package:tiki/features/publish/presentation/domain/publish_draft.dart';
import 'package:tiki/features/product/domain/app_product.dart';


final publishDraftsControllerProvider =
    StateNotifierProvider<PublishDraftsController, List<PublishDraft>>((ref) {
  final repo = ref.watch(publishDraftsRepositoryProvider);
  return PublishDraftsController(repo)..load();
});

class PublishDraftsController extends StateNotifier<List<PublishDraft>> {
  PublishDraftsController(this._repo) : super(const <PublishDraft>[]);

  final PublishDraftsRepository _repo;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final items = await _repo.fetchAll();
    state = items;
  }

  PublishDraft? byId(String id) {
    final did = id.trim();
    if (did.isEmpty) return null;
    for (final d in state) {
      if (d.id == did) return d;
    }
    return null;
  }

  String? get lastDraftId => _repo.getLastDraftId();

  Future<void> setLastDraftId(String? id) async {
    await _repo.setLastDraftId(id);
  }

  Future<void> _persist() async {
    await _repo.saveAll(state);
  }

  String _newId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'd_${now}_${Random().nextInt(999999)}';
  }

  Future<String> createBlank({String kind = 'product'}) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final id = _newId();
    final d = PublishDraft(
      id: id,
      kind: kind,
      mode: 'create',
      targetId: null,
      name: null,
      step: 0,
      createdAtMs: nowMs,
      updatedAtMs: nowMs,
      schemaVersion: 1,
      data: <String, dynamic>{},
    );
    state = [d, ...state];
    await _persist();
    await _repo.setLastDraftId(id);
    return id;
  }


  /// Creates an edit-mode draft from a Firestore-backed [AppProduct].
  ///
  /// Used when the user taps "Edit" from seller listings.
  Future<String> createEditFromAppProduct(AppProduct p) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final id = _newId();

    final attrs = Map<String, String>.from(p.attrs);

    final details = (p.details ?? p.description ?? '').trim();
    final data = <String, dynamic>{
      'title': p.title,
      'details': details,
      'price': p.price,
      if (p.oldPrice != null) 'oldPrice': p.oldPrice,
      'neighborhood': p.neighborhood,
      'phone': (p.phone ?? '').trim(),
      'allowWhatsApp': p.allowWhatsApp,
      'allowCall': p.allowCall,
      'categoryId': (p.category ?? '').trim(),
      'subCategoryId': (p.subCategory ?? '').trim(),
      'images': List<String>.from(p.images),
      'attrs': attrs,
      'hasWarranty': p.hasWarranty,
      'warrantyValue': (p.warrantyValue ?? 0),
      'warrantyUnit': (p.warrantyUnit ?? 'months'),
      'warrantyType': (p.warrantyType ?? 'seller'),
    };

    // Location: keep both stable IDs (if present in attrs) and fallback labels.
    final outsideMa = (attrs['outside_ma'] ?? '').toLowerCase() == 'true';
    data['outsideMa'] = outsideMa;

    if (outsideMa) {
      data['outsideCountryIso2'] = (attrs['outside_country_iso2'] ?? '').trim();
      data['outsideCity'] = (attrs['outside_city'] ?? '').trim();
    } else {
      data['wilayaId'] = (attrs['wilaya_id'] ?? '').trim();
      data['moughataaId'] = (attrs['moughataa_id'] ?? '').trim();
      data['wilayaName'] = p.wilaya;
      data['moughataaName'] = p.moughataa;
    }

    final d = PublishDraft(
      id: id,
      kind: 'product',
      mode: 'edit',
      targetId: p.id,
      name: null,
      step: 1,
      createdAtMs: nowMs,
      updatedAtMs: nowMs,
      schemaVersion: 1,
      data: data,
    );

    state = [d, ...state];
    await _persist();
    await _repo.setLastDraftId(id);
    return id;
  }

  Future<void> upsert(PublishDraft draft) async {
    final i = state.indexWhere((e) => e.id == draft.id);
    if (i < 0) {
      state = [draft, ...state]
        ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    } else {
      final next = [...state];
      next[i] = draft;
      next.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      state = next;
    }
    await _persist();
    await _repo.setLastDraftId(draft.id);
  }

  Future<void> delete(String id) async {
    final did = id.trim();
    if (did.isEmpty) return;
    state = state.where((e) => e.id != did).toList(growable: false);
    await _persist();
    if ((_repo.getLastDraftId() ?? '') == did) {
      await _repo.setLastDraftId(null);
    }
  }

  Future<void> deleteMany(Iterable<String> ids) async {
    final set = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (set.isEmpty) return;

    state = state.where((e) => !set.contains(e.id)).toList(growable: false);
    await _persist();

    final last = _repo.getLastDraftId();
    if (last != null && set.contains(last)) {
      await _repo.setLastDraftId(null);
    }
  }

  Future<void> deleteAll() async {
    if (state.isEmpty) return;
    state = const <PublishDraft>[];
    await _persist();
    await _repo.setLastDraftId(null);
  }

  Future<String> duplicate(String id) async {
    final src = byId(id);
    if (src == null) return createBlank(kind: 'product');

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final nid = _newId();
    final next = src.copyWith(
      // keep kind/mode, but it's a new draft instance
      targetId: src.targetId,
      step: src.step,
      createdAtMs: nowMs,
      updatedAtMs: nowMs,
      schemaVersion: src.schemaVersion,
      data: Map<String, dynamic>.from(src.data),
    );

    final d = PublishDraft(
      id: nid,
      kind: next.kind,
      mode: 'create',
      targetId: null,
      name: (src.name ?? '').trim().isEmpty ? null : src.name,
      step: next.step,
      createdAtMs: nowMs,
      updatedAtMs: nowMs,
      schemaVersion: next.schemaVersion,
      data: next.data,
    );

    state = [d, ...state]
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    await _persist();
    await _repo.setLastDraftId(nid);
    return nid;
  }

  Future<void> rename(String id, String name) async {
    final did = id.trim();
    final n = name.trim();
    if (did.isEmpty) return;

    final i = state.indexWhere((e) => e.id == did);
    if (i < 0) return;

    final d = state[i];
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final next = d.copyWith(name: n.isEmpty ? null : n, updatedAtMs: nowMs);

    final list = [...state];
    list[i] = next;
    list.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    state = list;
    await _persist();
  }
}
