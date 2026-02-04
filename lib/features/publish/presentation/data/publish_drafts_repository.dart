import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiki/core/storage/local_store.dart';

import '../domain/publish_draft.dart';

abstract class PublishDraftsRepository {
  Future<List<PublishDraft>> fetchAll();
  Future<void> saveAll(List<PublishDraft> drafts);

  String? getLastDraftId();
  Future<void> setLastDraftId(String? id);
}

final publishDraftsRepositoryProvider =
    Provider<PublishDraftsRepository>((ref) {
  final store = ref.watch(localStoreProvider);
  return LocalPublishDraftsRepository(store);
});

class LocalPublishDraftsRepository implements PublishDraftsRepository {
  LocalPublishDraftsRepository(this._store);

  final LocalStore _store;

  @override
  Future<List<PublishDraft>> fetchAll() async {
    return PublishDraft.decodeList(_store.getPublishDraftsJson());
  }

  @override
  Future<void> saveAll(List<PublishDraft> drafts) async {
    final json = PublishDraft.encodeList(drafts);
    await _store.setPublishDraftsJson(json);
  }

  @override
  String? getLastDraftId() => _store.getPublishLastDraftId();

  @override
  Future<void> setLastDraftId(String? id) async {
    await _store.setPublishLastDraftId(id);
  }
}
