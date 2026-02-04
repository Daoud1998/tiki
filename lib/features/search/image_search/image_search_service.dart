import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';

enum ImageSearchBackendType { aiLite, embeddings }

class PreparedImageSearch {
  const PreparedImageSearch({
    required this.backend,
    this.textQuery,
    this.categoryId,
    this.subCategoryId,
    this.candidateProductIds,
    this.debugNote,
  });

  final ImageSearchBackendType backend;

  /// Optional: used to fill the normal text search box
  final String? textQuery;

  final String? categoryId;
  final String? subCategoryId;

  /// For B later: when embeddings backend is wired, it will return ranked ids
  final List<String>? candidateProductIds;

  final String? debugNote;
}

abstract class ImageSearchBackend {
  ImageSearchBackendType get type;

  Future<PreparedImageSearch> prepare({
    required File imageFile,
    required Locale locale,
    String? hintText,
    String? userCategoryId,
    String? userSubCategoryId,
  });
}

/// -------- A: AI-lite backend (free, local, fast) --------
class AiLiteImageSearchBackend implements ImageSearchBackend {
  @override
  ImageSearchBackendType get type => ImageSearchBackendType.aiLite;

  @override
  Future<PreparedImageSearch> prepare({
    required File imageFile,
    required Locale locale,
    String? hintText,
    String? userCategoryId,
    String? userSubCategoryId,
  }) async {
    // Priority:
    // 1) user selection wins
    // 2) if hint text exists, infer a category (very light rules)
    final normalized = (hintText ?? '').trim().toLowerCase();

    String? inferredCategory;
    if (userCategoryId == null || userCategoryId.isEmpty) {
      inferredCategory = _inferCategoryIdFromText(normalized);
    }

    final cat = (userCategoryId != null && userCategoryId.isNotEmpty)
        ? userCategoryId
        : inferredCategory;

    return PreparedImageSearch(
      backend: type,
      textQuery: (normalized.isEmpty) ? null : normalized,
      categoryId: cat,
      subCategoryId: (userSubCategoryId != null && userSubCategoryId.isNotEmpty)
          ? userSubCategoryId
          : null,
      debugNote:
          'AI-lite: category=${cat ?? "-"} sub=${userSubCategoryId ?? "-"}',
    );
  }

  /// NOTE: put YOUR real categoryIds here (the ids you use in maCategories)
  /// These are examples only.
  String? _inferCategoryIdFromText(String t) {
    if (t.isEmpty) return null;

    bool hasAny(List<String> keys) => keys.any((k) => t.contains(k));

    // Real estate
    if (hasAny([
      'شقة',
      'شقق',
      'منزل',
      'دار',
      'ارض',
      'أرض',
      'عقار',
      'ايجار',
      'إيجار',
      'كراء'
    ])) {
      return 'real_estate';
    }

    // Vehicles
    if (hasAny([
      'سيارة',
      'تويوتا',
      'مرسيدس',
      'هيونداي',
      'كيا',
      'هوندا',
      'دراجة',
      'موتو',
      'محرك'
    ])) {
      return 'vehicles';
    }

    // Electronics
    if (hasAny([
      'ايفون',
      'آيفون',
      'iphone',
      'samsung',
      'سامسونغ',
      'هاتف',
      'هاتف',
      'لابتوب',
      'pc',
      'شاحن'
    ])) {
      return 'electronics';
    }

    // Jobs/services
    if (hasAny([
      'وظيفة',
      'عمل',
      'cv',
      'سيرة',
      'خدمة',
      'تصليح',
      'عامل',
      'ممرض',
      'سائق'
    ])) {
      return 'services';
    }

    return null;
  }
}

/// -------- B: Embeddings backend (stub now, wire later) --------
class EmbeddingImageSearchBackendStub implements ImageSearchBackend {
  @override
  ImageSearchBackendType get type => ImageSearchBackendType.embeddings;

  @override
  Future<PreparedImageSearch> prepare({
    required File imageFile,
    required Locale locale,
    String? hintText,
    String? userCategoryId,
    String? userSubCategoryId,
  }) async {
    // Stub: later you will call Cloud Function / API here:
    // - send image bytes
    // - receive ranked productIds
    // - return candidateProductIds
    return PreparedImageSearch(
      backend: type,
      // Keep the UI working: still pass whatever the user typed
      textQuery:
          (hintText ?? '').trim().isEmpty ? null : (hintText ?? '').trim(),
      categoryId: userCategoryId,
      subCategoryId: userSubCategoryId,
      candidateProductIds: const <String>[],
      debugNote: 'Embeddings backend not wired yet (stub).',
    );
  }
}

class ImageSearchService {
  ImageSearchService(this._store);

  final LocalStore _store;

  final ImageSearchBackend _aiLite = AiLiteImageSearchBackend();
  final ImageSearchBackend _embeddings = EmbeddingImageSearchBackendStub();

  Future<PreparedImageSearch> prepare({
    required File imageFile,
    required Locale locale,
    String? hintText,
    String? userCategoryId,
    String? userSubCategoryId,
  }) async {
    final useEmbeddings = await _store.getImageEmbeddingSearchEnabled();

    // If embeddings enabled, try it first, but fallback to AI-lite
    if (useEmbeddings) {
      final emb = await _embeddings.prepare(
        imageFile: imageFile,
        locale: locale,
        hintText: hintText,
        userCategoryId: userCategoryId,
        userSubCategoryId: userSubCategoryId,
      );

      // If it returns ids later, great. For now it’s empty => fallback.
      if (emb.candidateProductIds != null &&
          emb.candidateProductIds!.isNotEmpty) {
        return emb;
      }
      // fallback to AI-lite for now (keeps product results useful today)
    }

    return _aiLite.prepare(
      imageFile: imageFile,
      locale: locale,
      hintText: hintText,
      userCategoryId: userCategoryId,
      userSubCategoryId: userSubCategoryId,
    );
  }
}

final imageSearchServiceProvider = Provider<ImageSearchService>((ref) {
  final store = ref.watch(localStoreProvider);
  return ImageSearchService(store);
});
