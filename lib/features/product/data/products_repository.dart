import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'package:tiki/core/search/ma_search_tokens.dart';
import 'package:tiki/features/product/domain/app_product.dart';

final productsRepositoryProvider =
    Provider<ProductsRepository>((ref) => ProductsRepository());

/// Firestore collection: `products`
/// Storage paths:
/// - Recommended: `products/<uid>/<productId>/<file>` (matches strict rules)
/// - Legacy:      `products/<productId>/<file>` (older builds)
class ProductsRepository {
  ProductsRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    this.preferIndexedQueries = false,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  /// If true, use Firestore composite-index queries (faster).
  /// If false (default), prefer index-free queries + client-side sorting/filtering
  /// to avoid missing-index issues in production.
  final bool preferIndexedQueries;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('products');

  bool _looksLikeMissingIndex(Object e) {
    // Firestore missing composite index typically surfaces as:
    // FirebaseException(code: failed-precondition, message: ... requires an index ...)
    if (e is FirebaseException) {
      final code = e.code.toLowerCase();
      if (code == 'failed-precondition' || code == 'failed_precondition') {
        return true;
      }
      // Some platforms stringify the code rather than setting it exactly.
      final msg = (e.message ?? '').toLowerCase();
      if (msg.contains('requires an index') || msg.contains('create it here')) {
        return true;
      }
    }

    final s = e.toString().toLowerCase();
    // Android/iOS/Web variations.
    return s.contains('requires an index') ||
        s.contains('create it here') ||
        s.contains('failed-precondition') ||
        s.contains('failed_precondition');
  }

  int _tsToMs(dynamic v) {
    if (v == null) return 0;
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is DateTime) return v.millisecondsSinceEpoch;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  /// Normalize a phone-like input and return the **last 8 digits** (Mauritania-friendly).
  ///
  /// Examples:
  /// - "36566606" -> "36566606"
  /// - "+222 36 56 66 06" -> "36566606"
  /// Returns null if we can't get at least 8 digits.
  String? phoneTail8(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8) return null;
    return digits.substring(digits.length - 8);
  }

  bool _looksLikePhoneQuery(String input) {
    // Allow digits plus spaces and common phone punctuation.
    return RegExp(r'^\s*[0-9\+\-\(\)\s]+\s*$').hasMatch(input);
  }

  Stream<List<AppProduct>> _watchWithFallback({
    required Query<Map<String, dynamic>> primary,
    required Query<Map<String, dynamic>> fallback,
    required List<AppProduct> Function(QuerySnapshot<Map<String, dynamic>>)
        mapper,

    /// Keep the stream alive and retry on transient errors (network/startup races).
    /// This prevents Riverpod StreamProvider from getting stuck in AsyncError until
    /// the user manually refreshes.
    bool retryOnErrors = true,

    /// If true, forward errors to the UI (AsyncError).
    /// Default is false because feeds should self-heal.
    bool forwardErrors = false,
    Duration retryBaseDelay = const Duration(milliseconds: 900),
    Duration retryMaxDelay = const Duration(seconds: 8),
    int maxRetries = 6,

    /// Rarely needed, but can help when you want cache/server transitions.
    bool includeMetadataChanges = false,
  }) {
    final controller = StreamController<List<AppProduct>>();

    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;
    Timer? retryTimer;
    int retryCount = 0;

    void cancelRetry() {
      retryTimer?.cancel();
      retryTimer = null;
    }

    void listen(Query<Map<String, dynamic>> q, {required bool isFallback}) {
      cancelRetry();
      sub?.cancel();

      sub = q.snapshots(includeMetadataChanges: includeMetadataChanges).listen(
        (snap) {
          // Any successful event resets retries.
          retryCount = 0;
          controller.add(mapper(snap));
        },
        onError: (e, st) {
          // Missing-index: switch to index-free fallback immediately.
          if (!isFallback && _looksLikeMissingIndex(e)) {
            if (kDebugMode) {
              debugPrint(
                  '[ProductsRepository] Missing index; switching to fallback. $e');
            }
            listen(fallback, isFallback: true);
            return;
          }

          if (kDebugMode) {
            debugPrint(
                '[ProductsRepository] stream error (${isFallback ? 'fallback' : 'primary'}): $e');
          }

          if (!retryOnErrors) {
            if (forwardErrors) controller.addError(e, st);
            return;
          }

          // Retry with exponential backoff.
          if (retryCount >= maxRetries) {
            if (forwardErrors) controller.addError(e, st);
            return;
          }

          final nextMs = (retryBaseDelay.inMilliseconds * (1 << retryCount))
              .clamp(
                  retryBaseDelay.inMilliseconds, retryMaxDelay.inMilliseconds);
          retryCount += 1;

          cancelRetry();
          retryTimer = Timer(Duration(milliseconds: nextMs), () {
            listen(q, isFallback: isFallback);
          });
        },
      );
    }

    listen(primary, isFallback: false);

    controller.onCancel = () async {
      cancelRetry();
      await sub?.cancel();
    };

    return controller.stream;
  }

  // ---------- CRUD ----------

  /// Supports both `id:` and `productId:` to avoid breaking older call sites.
  Future<void> upsertProduct({
    String? id,
    String? productId,
    required Map<String, dynamic> data,
    bool merge = true,
  }) async {
    final pid = id ?? productId;
    if (pid == null || pid.trim().isEmpty) {
      throw ArgumentError('upsertProduct: id/productId is required');
    }
    await _col.doc(pid).set(data, SetOptions(merge: merge));
  }

  Stream<AppProduct?> watchById(String id) {
    return _col.doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppProduct.fromDoc(doc);
    });
  }

  Future<AppProduct?> getById(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return AppProduct.fromDoc(doc);
  }

  Future<void> setStatus(String id, String status) async {
    await _col.doc(id).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> pauseProduct(String id) => setStatus(id, 'paused');
  Future<void> resumeProduct(String id) => setStatus(id, 'active');

  Future<void> updateAttrs(String id, Map<String, dynamic> patch) async {
    if (patch.isEmpty) return;
    final updates = <String, dynamic>{};
    patch.forEach((k, v) {
      updates['attrs.$k'] = v;
    });
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _col.doc(id).update(updates);
  }

  Future<void> incrementViewCount(String id) async {
    await _col.doc(id).update({'viewCount': FieldValue.increment(1)});
  }

  /// Increment view count **once per viewer per day**.
  ///
  /// - Signed-in user: viewerKey = "u:<uid>"
  /// - Guest device:   viewerKey = "d:<deviceId>"
  ///
  /// Writes a marker doc under:
  /// `products/<productId>/views_daily/<YYYYMMDD>__<viewerKey>`
  ///
  /// Returns `true` if this call incremented the counter, otherwise `false`.
  Future<bool> incrementUniqueViewPerDay(
    String productId, {
    required String viewerKey,
  }) async {
    final pid = productId.trim();
    final vk = viewerKey.trim();
    if (pid.isEmpty || vk.isEmpty) return false;

    // Use UTC day to keep consistent across devices/timezones.
    final now = DateTime.now().toUtc();
    final dayKey =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    // Compatibility: some older edits referenced `day_` by mistake.
    // Keeping this alias prevents "Undefined name 'day_'" regressions.
    // ignore: unused_local_variable
    final day_ = dayKey;

    final safeViewer = vk.replaceAll('/', '_').replaceAll(' ', '_');
    final markerId = '${dayKey}__${safeViewer}';

    final productRef = _col.doc(pid);
    final markerRef = productRef.collection('views_daily').doc(markerId);

    return _db.runTransaction<bool>((tx) async {
      final markerSnap = await tx.get(markerRef);
      if (markerSnap.exists) return false;

      tx.set(markerRef, <String, dynamic>{
        'day': dayKey,
        'viewerKey': vk,
        'createdAt': FieldValue.serverTimestamp(),
      });

      tx.update(productRef, <String, dynamic>{
        'viewCount': FieldValue.increment(1),
        'viewCountUpdatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    });
  }

  Future<void> deleteProductForever(AppProduct product) async {
    // Best effort delete storage assets
    Future<void> tryDeleteUrl(String url) async {
      try {
        if (url.trim().isEmpty) return;
        await _storage.refFromURL(url).delete();
      } catch (_) {
        // ignore
      }
    }

    for (final u in product.images) {
      await tryDeleteUrl(u);
    }
    if ((product.videoUrl ?? '').trim().isNotEmpty) {
      await tryDeleteUrl(product.videoUrl!);
    }

    await _col.doc(product.id).delete();
  }

  // ---------- Uploads ----------

  Future<List<String>> uploadProductImages({
    required String productId,
    required List<String> imagePathsOrUrls,
    String? sellerId,
  }) async {
    // Keep URLs as-is; upload local files and return URLs.
    final out = <String>[];
    final uid = sellerId ?? _auth.currentUser?.uid ?? 'unknown';
    final rand = Random();

    for (var i = 0; i < imagePathsOrUrls.length; i++) {
      final p = imagePathsOrUrls[i].trim();
      if (p.isEmpty) continue;

      if (p.startsWith('http')) {
        out.add(p);
        continue;
      }

      if (kIsWeb) {
        // Web local files need special handling; keep as-is.
        out.add(p);
        continue;
      }

      final file = File(p);
      if (!await file.exists()) continue;

      final ext = p.contains('.') ? p.split('.').last : 'jpg';
      final name =
          'img_${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(9999)}.$ext';

      final contentType = _contentTypeFromExt(ext, isVideo: false);

      // Try the strict path first (uid/productId). If the project still uses
      // legacy rules, fall back to products/<productId>/<file>.
      final strictRef = _storage.ref('products/$uid/$productId/$name');
      final legacyRef = _storage.ref('products/$productId/$name');

      final url = await _putFileWithFallback(
        file: file,
        strictRef: strictRef,
        legacyRef: legacyRef,
        contentType: contentType,
      );
      out.add(url);
    }
    return out;
  }

  Future<String?> uploadProductVideo({
    required String productId,
    required String videoPath,
    String? sellerId,
  }) async {
    final p = videoPath.trim();
    if (p.isEmpty) return null;
    if (p.startsWith('http')) return p;
    if (kIsWeb) return p;

    final file = File(p);
    if (!await file.exists()) return null;

    final uid = sellerId ?? _auth.currentUser?.uid ?? 'unknown';
    final rand = Random();
    final ext = p.contains('.') ? p.split('.').last : 'mp4';
    final name =
        'vid_${DateTime.now().millisecondsSinceEpoch}_${rand.nextInt(9999)}.$ext';

    final contentType = _contentTypeFromExt(ext, isVideo: true);

    final strictRef = _storage.ref('products/$uid/$productId/$name');
    final legacyRef = _storage.ref('products/$productId/$name');

    return _putFileWithFallback(
      file: file,
      strictRef: strictRef,
      legacyRef: legacyRef,
      contentType: contentType,
    );
  }

  String _contentTypeFromExt(String ext, {required bool isVideo}) {
    final e = ext.toLowerCase();
    if (isVideo) {
      if (e == 'mov') return 'video/quicktime';
      if (e == 'mkv') return 'video/x-matroska';
      if (e == 'webm') return 'video/webm';
      return 'video/mp4';
    }
    if (e == 'png') return 'image/png';
    if (e == 'webp') return 'image/webp';
    if (e == 'gif') return 'image/gif';
    return 'image/jpeg';
  }

  Future<String> _putFileWithFallback({
    required File file,
    required Reference strictRef,
    required Reference legacyRef,
    required String contentType,
  }) async {
    final meta = SettableMetadata(contentType: contentType);
    try {
      await strictRef.putFile(file, meta);
      return await strictRef.getDownloadURL();
    } on FirebaseException catch (e) {
      // If strict path is not allowed by rules, try the legacy path.
      final code = e.code.toLowerCase();
      final denied = code.contains('unauthorized') ||
          code.contains('permission-denied') ||
          code.contains('permission_denied');
      if (!denied) rethrow;

      if (kDebugMode) {
        debugPrint(
            '[ProductsRepository] Strict upload denied, trying legacy. code=${e.code}');
      }
      await legacyRef.putFile(file, meta);
      return await legacyRef.getDownloadURL();
    }
  }

  // ---------- Queries ----------

  Stream<List<AppProduct>> watchMyProducts({required String sellerId}) {
    final primary = _col
        .where('sellerId', isEqualTo: sellerId)
        .orderBy('updatedAt', descending: true);
    final fallback = _col.where('sellerId', isEqualTo: sellerId);

    List<AppProduct> mapSnap(QuerySnapshot<Map<String, dynamic>> s) {
      // Prefer updatedAt ordering when present (same as the primary query).
      final pairs = s.docs.map((d) {
        final ms = _tsToMs(d.data()['updatedAt']);
        return MapEntry(AppProduct.fromDoc(d), ms);
      }).toList();
      pairs.sort((a, b) {
        final ra = a.value;
        final rb = b.value;
        if (ra != rb) return rb.compareTo(ra);
        return b.key.publishedAt.compareTo(a.key.publishedAt);
      });
      return pairs.map((e) => e.key).toList(growable: false);
    }

    final effectivePrimary = preferIndexedQueries ? primary : fallback;

    return _watchWithFallback(
        primary: effectivePrimary, fallback: fallback, mapper: mapSnap);
  }

  /// Seller products view.
  ///
  /// - If the current user is the seller, show all their products (any status).
  /// - Otherwise (guest/other user), show only public listings:
  ///   status==active AND isHidden==false.
  Stream<List<AppProduct>> watchSellerProducts(String sellerId) {
    final me = _auth.currentUser?.uid;
    if (me != null && me == sellerId) {
      return watchMyProducts(sellerId: sellerId);
    }
    return watchPublicSellerProducts(sellerId: sellerId);
  }

  Stream<List<AppProduct>> watchPublicSellerProducts({
    required String sellerId,
    int limit = 200,
  }) {
    final primary = _col
        .where('sellerId', isEqualTo: sellerId)
        .where('status', isEqualTo: 'active')
        .where('isHidden', isEqualTo: false)
        .orderBy('publishedAt', descending: true)
        .limit(limit);

    // Fallback avoids composite index requirements (sorting is done client-side).
    final fallback = _col
        .where('sellerId', isEqualTo: sellerId)
        .where('status', isEqualTo: 'active')
        .where('isHidden', isEqualTo: false)
        .limit(limit);

    return _watchWithFallback(
      primary: preferIndexedQueries ? primary : fallback,
      fallback: fallback,
      mapper: (s) {
        final items = s.docs.map(AppProduct.fromDoc).toList();
        items.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
        return items;
      },
    );
  }

  Stream<List<AppProduct>> watchActiveFeed({int limit = 50}) {
    // Legacy support:
    // - Some older products may not have `isHidden` set at all.
    //   Firestore allows querying `isHidden == null` which matches documents where
    //   the field is missing or explicitly null.
    //
    // We therefore merge:
    //   1) status=active AND isHidden=false
    //   2) status=active AND isHidden==null (missing)
    final visibleFalse = _watchActiveByHiddenValue(isHiddenValue: false, limit: limit);
    final visibleMissing =
        _watchActiveByHiddenValue(isHiddenValue: null, limit: limit);

    return _mergeTwoProductStreams(
      a: visibleFalse,
      b: visibleMissing,
      limit: limit,
    );
  }

  Stream<List<AppProduct>> _watchActiveByHiddenValue({
    required Object? isHiddenValue,
    required int limit,
  }) {
    final primary = _col
        .where('status', isEqualTo: 'active')
        .where('isHidden', isEqualTo: isHiddenValue)
        .orderBy('publishedAt', descending: true)
        .limit(limit);

    final fallback = _col
        .where('status', isEqualTo: 'active')
        .where('isHidden', isEqualTo: isHiddenValue)
        .limit(limit);

    return _watchWithFallback(
      primary: preferIndexedQueries ? primary : fallback,
      fallback: fallback,
      mapper: (s) {
        final items = s.docs.map(AppProduct.fromDoc).toList();
        // _applyVipSorting also sorts newest first within rank.
        return _applyVipSorting(items);
      },
    );
  }

  Stream<List<AppProduct>> _mergeTwoProductStreams({
    required Stream<List<AppProduct>> a,
    required Stream<List<AppProduct>> b,
    required int limit,
  }) {
    final controller = StreamController<List<AppProduct>>();

    List<AppProduct> lastA = const <AppProduct>[];
    List<AppProduct> lastB = const <AppProduct>[];

    void emit() {
      final byId = <String, AppProduct>{};
      for (final p in lastA) {
        byId[p.id] = p;
      }
      for (final p in lastB) {
        byId[p.id] = p;
      }

      final merged = byId.values.toList();
      final sorted = _applyVipSorting(merged);
      controller.add(sorted.take(limit).toList());
    }

    StreamSubscription<List<AppProduct>>? subA;
    StreamSubscription<List<AppProduct>>? subB;

    subA = a.listen(
      (v) {
        lastA = v;
        emit();
      },
      onError: (e, st) => controller.addError(e, st),
    );

    subB = b.listen(
      (v) {
        lastB = v;
        emit();
      },
      onError: (e, st) => controller.addError(e, st),
    );

    controller.onCancel = () async {
      await subA?.cancel();
      await subB?.cancel();
    };

    return controller.stream;
  }


  Stream<List<AppProduct>> watchSearch(
    String query, {
    String? categoryId,
    int limit = 50,
  }) {
    final q = query.trim();
    if (q.isEmpty) return watchActiveFeed(limit: limit);

    // Phone mode (last 8 digits). Example: 36566606 or +222 36 56 66 06
    final tail8 = phoneTail8(q);
    final isPhoneQuery = tail8 != null && _looksLikePhoneQuery(q);

    if (isPhoneQuery) {
      Query<Map<String, dynamic>> ref = _col
          .where('status', isEqualTo: 'active')
          .where('isHidden', isEqualTo: false);

      if (categoryId != null && categoryId.trim().isNotEmpty) {
        // Optional: keep category filter even for phone search.
        // May require an extra composite index; fallback will still work.
        ref = ref.where('category', isEqualTo: categoryId.trim());
      }

      final primary = ref
          .where('phoneTail8', isEqualTo: tail8)
          .orderBy('publishedAt', descending: true)
          .limit(limit);

      // Fallback: scan a slice of active listings and filter locally by phone tail.
      final fallback = _col
          .where('status', isEqualTo: 'active')
          .where('isHidden', isEqualTo: false)
          .limit(limit * 5);

      return _watchWithFallback(
        primary: preferIndexedQueries ? primary : fallback,
        fallback: fallback,
        mapper: (s) {
          var items = s.docs.map(AppProduct.fromDoc).toList();

          if (categoryId != null && categoryId.trim().isNotEmpty) {
            final c = categoryId.trim();
            items = items
                .where((p) => (p.category ?? '').trim() == c)
                .toList(growable: false);
          }

          items = items
              .where((p) => phoneTail8(p.phone ?? '') == tail8)
              .toList(growable: false);

          items = items.toList()
            ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
          return _applyVipSorting(items);
        },
      );
    }

    // Normal text mode: query tokens (AR/FR/EN + joins like iphone 13 -> iphone13).
    // Firestore arrayContainsAny supports up to 10 values.
    final tokens = maQueryTokens(q, maxTokens: 10);

    Query<Map<String, dynamic>> ref = _col
        .where('status', isEqualTo: 'active')
        .where('isHidden', isEqualTo: false);

    if (categoryId != null && categoryId.trim().isNotEmpty) {
      // Stored field name is `category` in this project.
      ref = ref.where('category', isEqualTo: categoryId.trim());
    }

    // Primary: server-side token search (may require composite indexes).
    final primary = (tokens.isNotEmpty)
        ? ref
            .where('searchTokens', arrayContainsAny: tokens)
            .orderBy('publishedAt', descending: true)
            .limit(limit)
        : ref.orderBy('publishedAt', descending: true).limit(limit);

    // Fallback: fetch a slice of active feed and filter locally.
    // (This avoids missing-index errors, at the cost of precision/perf.)
    final fallback = _col
        .where('status', isEqualTo: 'active')
        .where('isHidden', isEqualTo: false)
        .limit(limit * 3);

    return _watchWithFallback(
      primary: preferIndexedQueries ? primary : fallback,
      fallback: fallback,
      mapper: (s) {
        var items = s.docs.map(AppProduct.fromDoc).toList();

        if (categoryId != null && categoryId.trim().isNotEmpty) {
          final c = categoryId.trim();
          items = items
              .where((p) => (p.category ?? '').trim() == c)
              .toList(growable: false);
        }

        if (tokens.isNotEmpty) {
          final tset = tokens.toSet();
          items = items
              .where((p) => p.searchTokens.any(tset.contains))
              .toList(growable: false);
        }

        items = items.toList()
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
        return _applyVipSorting(items);
      },
    );
  }

// ---------- Search tokens ----------

  /// Listing tokens stored on the product document.
  ///
  /// We build these once at publish/update time.
  /// - Arabic normalization (أ/إ/آ -> ا, remove tashkeel)
  /// - French accents normalization (é -> e, etc.)
  /// - Prefix tokens (type-ahead: "سبور" matches "سبورتاج")
  /// - Simple dictionary expansion (popular brands/synonyms)
  List<String> buildSearchTokens(String text) =>
      maBuildSearchTokens(fields: [text], maxTokens: 80);

  // ---------- VIP sorting ----------

  List<AppProduct> _applyVipSorting(List<AppProduct> items) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    int vipRank(AppProduct p) {
      final a = p.attrs;
      final status = (a['promo_status'] ?? '').toString();
      if (status != 'approved') return 0;
      final untilMs = int.tryParse((a['promo_until_ms'] ?? '').toString()) ?? 0;
      if (untilMs > 0 && untilMs < nowMs) return 0;

      final r = int.tryParse((a['promo_rank'] ?? '').toString());
      if (r != null) return r;

      final tier = (a['promo_tier'] ?? '').toString().toLowerCase();
      if (tier == 'top') return 3;
      if (tier == 'featured') return 2;
      if (tier == 'boost') return 1;
      return 0;
    }

    items.sort((a, b) {
      final ra = vipRank(a);
      final rb = vipRank(b);
      if (ra != rb) return rb.compareTo(ra);
      // newest first
      return b.publishedAt.compareTo(a.publishedAt);
    });
    return items;
  }
}
