import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';

/// Global provider for local (device) storage.
/// This must be overridden by [LocalStoreProviderScope] at app start.
final localStoreProvider = Provider<LocalStore>((ref) {
  throw UnimplementedError(
    'LocalStore must be overridden (see LocalStoreProviderScope).',
  );
});

class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalStore(prefs);
  }

  // ---- Theme ----
  static const _kThemeMode = 'theme_mode'; // 0 system, 1 light, 2 dark

  ThemeMode getThemeMode() {
    final v = _prefs.getInt(_kThemeMode) ?? 0;
    if (v == 1) return ThemeMode.light;
    if (v == 2) return ThemeMode.dark;
    return ThemeMode.system;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final v = (mode == ThemeMode.light)
        ? 1
        : (mode == ThemeMode.dark)
            ? 2
            : 0;
    await _prefs.setInt(_kThemeMode, v);
  }

  // ---- Locale ----
  static const _kLocaleOverride = 'locale_override'; // 'ar'/'fr'/'en' or ''

  Locale? getLocaleOverride() {
    final code = _prefs.getString(_kLocaleOverride);
    if (code == null || code.isEmpty) return null;
    return Locale(code);
  }

  Future<void> setLocaleOverride(Locale? locale) async {
    await _prefs.setString(_kLocaleOverride, locale?.languageCode ?? '');
  }

  // ---- Likes ----
  static const _kLikedIds = 'liked_ids';

  Set<String> getLikedIds() {
    final list = _prefs.getStringList(_kLikedIds) ?? const <String>[];
    return list.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
  }

  Future<void> setLikedIds(Set<String> ids) async {
    final list = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await _prefs.setStringList(_kLikedIds, list);
  }

  // ---------------------------------------------------------------------------
  // Auth (local mock until Firebase)
  // ---------------------------------------------------------------------------

  static const String _kAuthSessionJson = 'auth_session_json_v1';
  static const String _kAuthAccountsJson = 'auth_accounts_json_v1';

  String? getAuthSessionJson() => _prefs.getString(_kAuthSessionJson);

  Future<void> setAuthSessionJson(String? json) async {
    final v = (json ?? '').trim();
    if (v.isEmpty) {
      await _prefs.remove(_kAuthSessionJson);
    } else {
      await _prefs.setString(_kAuthSessionJson, v);
    }
  }

  /// JSON map: phoneE164 -> {name, phoneE164, email?, password}
  String? getLocalAccountsJson() => _prefs.getString(_kAuthAccountsJson);

  Future<void> setLocalAccountsJson(String? json) async {
    final v = (json ?? '').trim();
    if (v.isEmpty) {
      await _prefs.remove(_kAuthAccountsJson);
    } else {
      await _prefs.setString(_kAuthAccountsJson, v);
    }
  }

  // ---- User Profile (name + location) ----
  static const _kProfileJson = 'user_profile_json_v1';
  static const _kProfilePrompted = 'user_profile_prompted_v1';

  String? getProfileJson() => _prefs.getString(_kProfileJson);

  Future<void> setProfileJson(String? json) async {
    final v = (json ?? '').trim();
    if (v.isEmpty) {
      await _prefs.remove(_kProfileJson);
    } else {
      await _prefs.setString(_kProfileJson, v);
    }
  }

  bool getProfilePrompted() => _prefs.getBool(_kProfilePrompted) ?? false;

  Future<void> setProfilePrompted(bool v) async {
    await _prefs.setBool(_kProfilePrompted, v);
  }

  // ---- Seller privacy: allow finding my listings by phone ----
  // Default: enabled (true) so users can quickly find sellers via phone search.
  static const String _kSellerPhoneSearchEnabledPrefix =
      'seller_phone_search_enabled_';

  bool getSellerPhoneSearchEnabled(String userId) {
    final id = userId.trim();
    if (id.isEmpty) return true;
    return _prefs.getBool('$_kSellerPhoneSearchEnabledPrefix$id') ?? true;
  }

  Future<void> setSellerPhoneSearchEnabled(String userId, bool enabled) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    await _prefs.setBool('$_kSellerPhoneSearchEnabledPrefix$id', enabled);
  }

  // ---------------------------------------------------------------------------
  // Last visited locations (Temu-like bottom tabs)
  // ---------------------------------------------------------------------------
  static const String _kLastAppLocation = 'last_app_location_v1';
  static const String _kLastHomeLocation = 'last_tab_home_location_v1';
  static const String _kLastCategoriesLocation =
      'last_tab_categories_location_v1';
  static const String _kLastPublishLocation = 'last_tab_publish_location_v1';
  static const String _kLastYouLocation = 'last_tab_you_location_v1';

  String? _getLoc(String key) {
    final v = _prefs.getString(key);
    if (v == null) return null;
    final s = v.trim();
    return s.isEmpty ? null : s;
  }

  Future<void> _setLoc(String key, String? location) async {
    final s = (location ?? '').trim();
    if (s.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, s);
    }
  }

  String? getLastAppLocation() => _getLoc(_kLastAppLocation);
  Future<void> setLastAppLocation(String? location) async =>
      _setLoc(_kLastAppLocation, location);

  String? getLastHomeLocation() => _getLoc(_kLastHomeLocation);
  Future<void> setLastHomeLocation(String? location) async =>
      _setLoc(_kLastHomeLocation, location);

  String? getLastCategoriesLocation() => _getLoc(_kLastCategoriesLocation);
  Future<void> setLastCategoriesLocation(String? location) async =>
      _setLoc(_kLastCategoriesLocation, location);

  String? getLastPublishLocation() => _getLoc(_kLastPublishLocation);
  Future<void> setLastPublishLocation(String? location) async =>
      _setLoc(_kLastPublishLocation, location);

  String? getLastYouLocation() => _getLoc(_kLastYouLocation);
  Future<void> setLastYouLocation(String? location) async =>
      _setLoc(_kLastYouLocation, location);

  // ---- Recently Viewed ----
  static const _kRecentlyViewedIds = 'recently_viewed_ids_v1';

  List<String> getRecentlyViewedIds() {
    final list = _prefs.getStringList(_kRecentlyViewedIds) ?? const <String>[];
    // Keep stable order, no empty strings
    return list.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  Future<void> setRecentlyViewedIds(List<String> ids) async {
    final list = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await _prefs.setStringList(_kRecentlyViewedIds, list);
  }

  // ---- Product view counts (device-local; until Firebase) ----
  // Stored as JSON maps: productId -> count, and productId -> lastSeenMs (throttle)
  static const String _kProductViewCounts = 'product_view_counts_v1';
  static const String _kProductViewLastMs = 'product_view_last_ms_v1';

  Map<String, int> _decodeMapInt(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      final out = <String, int>{};
      for (final e in decoded.entries) {
        final k = (e.key ?? '').toString().trim();
        if (k.isEmpty) continue;
        final v = e.value;
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
        if (n > 0) out[k] = n;
      }
      return out;
    } catch (_) {
      return <String, int>{};
    }
  }

  int getProductViewCount(String productId) {
    final id = productId.trim();
    if (id.isEmpty) return 0;
    final counts = _decodeMapInt(_prefs.getString(_kProductViewCounts));
    return counts[id] ?? 0;
  }

  /// Increment view count for a product.
  ///
  /// Throttled so the same product does not increment repeatedly within
  /// a short time window (default: 25 seconds).
  Future<void> incrementProductView(String productId,
      {Duration minInterval = const Duration(seconds: 25)}) async {
    final id = productId.trim();
    if (id.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    final lastMap = _decodeMapInt(_prefs.getString(_kProductViewLastMs));
    final last = lastMap[id] ?? 0;
    if (last > 0 && (now - last) < minInterval.inMilliseconds) {
      return; // too soon
    }

    final counts = _decodeMapInt(_prefs.getString(_kProductViewCounts));
    counts[id] = (counts[id] ?? 0) + 1;

    // Keep the map bounded (avoid infinite growth)
    if (counts.length > 1200) {
      // If it ever grows too much, drop the oldest by keeping only top counts.
      final entries = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      counts
        ..clear()
        ..addEntries(entries.take(1200));
    }

    lastMap[id] = now;

    await _prefs.setString(_kProductViewCounts, jsonEncode(counts));
    await _prefs.setString(_kProductViewLastMs, jsonEncode(lastMap));
  }

  // ---- Hot searches (device-local) ----
  // Stored per language as a JSON map: term -> count
  static const _kHotSearchPrefix = 'hot_search_counts_';

  Map<String, int> getHotSearchCounts(String lang) {
    final raw = _prefs.getString('$_kHotSearchPrefix$lang');
    if (raw == null || raw.trim().isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      return decoded.map<String, int>((k, v) {
        final key = (k ?? '').toString().trim();
        final val = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
        return MapEntry(key, val);
      })
        ..removeWhere((k, v) => k.isEmpty || v <= 0);
    } catch (_) {
      return <String, int>{};
    }
  }

  // ---------------------------------------------------------------------------
  // Recent search terms (Temu-style, device-local)
  // ---------------------------------------------------------------------------

  static const String _kRecentSearchPrefix = 'recent_search_terms_';
  static const int _kRecentSearchMax = 18;
  static const String _kFfImageEmbeddingSearchEnabled =
      'ff_img_embedding_search_enabled_v1';

  List<String> getRecentSearchTerms(String lang) {
    final code = (lang).trim().toLowerCase();
    final raw = _prefs.getString('$_kRecentSearchPrefix$code');
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      final out = <String>[];
      for (final v in decoded) {
        final s = (v ?? '').toString().trim();
        if (s.isEmpty) continue;
        if (out.any((e) => e.toLowerCase() == s.toLowerCase())) continue;
        out.add(s);
        if (out.length >= _kRecentSearchMax) break;
      }
      return out;
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _setRecentSearchTerms(String lang, List<String> terms) async {
    final code = (lang).trim().toLowerCase();
    final cleaned = <String>[];
    for (final t in terms) {
      final s = (t).trim();
      if (s.isEmpty) continue;
      if (cleaned.any((e) => e.toLowerCase() == s.toLowerCase())) continue;
      cleaned.add(s);
      if (cleaned.length >= _kRecentSearchMax) break;
    }
    if (cleaned.isEmpty) {
      await _prefs.remove('$_kRecentSearchPrefix$code');
      return;
    }
    await _prefs.setString('$_kRecentSearchPrefix$code', jsonEncode(cleaned));
  }

  Future<void> addRecentSearchTerm(String lang, String term) async {
    final t = term.trim();
    if (t.isEmpty) return;

    final safe = (t.length > 64) ? t.substring(0, 64) : t;

    final cur = getRecentSearchTerms(lang).toList(growable: true);
    cur.removeWhere((x) => x.toLowerCase() == safe.toLowerCase());
    cur.insert(0, safe);
    if (cur.length > _kRecentSearchMax)
      cur.removeRange(_kRecentSearchMax, cur.length);
    await _setRecentSearchTerms(lang, cur);
  }

  Future<void> removeRecentSearchTerm(String lang, String term) async {
    final t = term.trim();
    if (t.isEmpty) return;
    final cur = getRecentSearchTerms(lang).toList(growable: true);
    cur.removeWhere((x) => x.toLowerCase() == t.toLowerCase());
    await _setRecentSearchTerms(lang, cur);
  }

  Future<void> clearRecentSearchTerms(String lang) async {
    final code = (lang).trim().toLowerCase();
    await _prefs.remove('$_kRecentSearchPrefix$code');
  }

// ---------------------------------------------------------------------------
  // Publish drafts (multiple drafts for publish/edit)
  // ---------------------------------------------------------------------------

  static const String _kPublishDraftsJson = 'publish_drafts_json_v1';
  static const String _kPublishLastDraftId = 'publish_last_draft_id_v1';

  String? getPublishDraftsJson() => _prefs.getString(_kPublishDraftsJson);

  Future<void> setPublishDraftsJson(String? json) async {
    final v = (json ?? '').trim();
    if (v.isEmpty) {
      await _prefs.remove(_kPublishDraftsJson);
    } else {
      await _prefs.setString(_kPublishDraftsJson, v);
    }
  }

  String? getPublishLastDraftId() => _prefs.getString(_kPublishLastDraftId);

  Future<void> setPublishLastDraftId(String? id) async {
    final v = (id ?? '').trim();
    if (v.isEmpty) {
      await _prefs.remove(_kPublishLastDraftId);
    } else {
      await _prefs.setString(_kPublishLastDraftId, v);
    }
  }

// ---------------------------------------------------------------------------
// Review queue (pre-moderation before publishing)
// ---------------------------------------------------------------------------

  static const String _kReviewQueueJson = 'review_queue_json_v1';

  List<Map<String, dynamic>> _decodeListMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      final out = <Map<String, dynamic>>[];
      for (final v in decoded) {
        if (v is Map) {
          out.add(v.map((k, val) => MapEntry(k.toString(), val)));
        }
      }
      return out;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  List<Map<String, dynamic>> getReviewQueue() {
    return _decodeListMap(_prefs.getString(_kReviewQueueJson));
  }

  Future<List<Map<String, dynamic>>> getReviewQueueAsync() async =>
      getReviewQueue();

  Future<void> _setReviewQueue(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) {
      await _prefs.remove(_kReviewQueueJson);
      return;
    }
    await _prefs.setString(_kReviewQueueJson, jsonEncode(items));
  }

  String _genReviewQueueId() {
    // No external deps: stable-enough unique id for local queue.
    final t = DateTime.now().microsecondsSinceEpoch;
    final r = (t * 2654435761) & 0x7fffffff; // simple mixing
    return 'rq_${t}_$r';
  }

  /// Add a review queue item (pending approval).
  ///
  /// Accepts a Map or any object that exposes `toJson() -> Map`.
  Future<void> addReviewQueueItem(dynamic item) async {
    Map<String, dynamic>? map;

    if (item is Map<String, dynamic>) {
      map = Map<String, dynamic>.from(item);
    } else if (item is Map) {
      map = item.map((k, v) => MapEntry(k.toString(), v));
    } else {
      try {
        // ignore: avoid_dynamic_calls
        final maybe = item.toJson();
        if (maybe is Map) {
          map = maybe.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        map = null;
      }
    }

    if (map == null) return;

    final id = (map['id'] ?? map['queueId'] ?? '').toString().trim();
    if (id.isEmpty) {
      map['id'] = _genReviewQueueId();
    }

    // Defaults
    map['status'] = (map['status'] ?? 'pending').toString().trim().isEmpty
        ? 'pending'
        : map['status'];
    map['createdAt'] = (map['createdAt'] ?? DateTime.now().toIso8601String());

    final items = getReviewQueue();
    final list = items.toList(growable: true);

    // Deduplicate by id
    final newId = (map['id'] ?? '').toString();
    list.removeWhere(
        (e) => (e['id'] ?? e['queueId'] ?? '').toString() == newId);
    list.insert(0, map);

    // Bound growth
    if (list.length > 500) {
      list.removeRange(500, list.length);
    }

    await _setReviewQueue(list);
  }

  /// Returns all review items for a seller (by sellerId or sellerPhone).
  ///
  /// Backward-compatible: also checks nested sellerId/phone inside `payload`.
  List<Map<String, dynamic>> getReviewQueueForSeller(String? sellerKey) {
    final key = (sellerKey ?? '').trim();
    if (key.isEmpty) return <Map<String, dynamic>>[];

    final items = getReviewQueue();
    String _s(dynamic v) => (v ?? '').toString().trim();

    bool matches(Map<String, dynamic> e) {
      final a = _s(e['sellerId']);
      final b = _s(e['sellerPhone']);
      if (a == key || b == key) return true;

      final payload = e['payload'];
      if (payload is Map) {
        final p = <String, dynamic>{};
        for (final entry in payload.entries) {
          final k = (entry.key ?? '').toString();
          if (k.isEmpty) continue;
          p[k] = entry.value;
        }
        final pa = _s(p['sellerId']);
        final pb = _s(p['sellerPhone']);
        final pc = _s(p['phone']);
        if (pa == key || pb == key || pc == key) return true;
      }

      return false;
    }

    return items.where(matches).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getReviewQueueForSellerAsync(
          String? sellerKey) async =>
      getReviewQueueForSeller(sellerKey);

  Future<void> removeReviewQueueItem(String id) async {
    final key = id.trim();
    if (key.isEmpty) return;
    final items = getReviewQueue();
    final list = items.toList(growable: true);
    list.removeWhere(
        (e) => (e['id'] ?? e['queueId'] ?? '').toString().trim() == key);
    await _setReviewQueue(list);
  }

  Future<void> updateReviewQueueItem(
      String id, Map<String, dynamic> patch) async {
    final key = id.trim();
    if (key.isEmpty) return;

    final items = getReviewQueue();
    final list = items.toList(growable: true);

    final i = list.indexWhere(
        (e) => (e['id'] ?? e['queueId'] ?? '').toString().trim() == key);
    if (i < 0) return;

    final current = Map<String, dynamic>.from(list[i]);
    patch.forEach((k, v) {
      final kk = k.toString().trim();
      if (kk.isEmpty) return;
      current[kk] = v;
    });

    list[i] = current;
    await _setReviewQueue(list);
  }

  Future<void> incrementHotSearch(String lang, String term) async {
    final t = term.trim();
    if (t.isEmpty) return;

    final counts = getHotSearchCounts(lang);
    counts[t] = (counts[t] ?? 0) + 1;

    // Keep map from growing forever: keep top 80 by count
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final capped = <String, int>{};
    for (final e in entries.take(80)) {
      capped[e.key] = e.value;
    }

    await _prefs.setString('$_kHotSearchPrefix$lang', jsonEncode(capped));
  }

  List<String> topHotSearchTerms(String lang, {int limit = 10}) {
    final counts = getHotSearchCounts(lang);
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList(growable: false);
  }
  // ---------------------------------------------------------------------------
  // Blocked sellers (local)
  // ---------------------------------------------------------------------------

  static const String _kBlockedSellerPhones = 'blocked_seller_phones_v1';

  /// Backwards-compatible name used by some controllers.
  Future<List<String>> getBlockedSellerKeys() async {
    return _prefs.getStringList(_kBlockedSellerPhones) ?? <String>[];
  }

  /// Backwards-compatible name used by some controllers.
  Future<void> setBlockedSellerKeys(List<String> keys) async {
    await _prefs.setStringList(_kBlockedSellerPhones, keys);
  }

  /// Newer convenience alias.
  Future<List<String>> getBlockedSellerPhones() => getBlockedSellerKeys();

  Future<void> setBlockedSellerPhones(List<String> phones) =>
      setBlockedSellerKeys(phones);

  Future<bool> isSellerBlocked(String phone) async {
    if (phone.trim().isEmpty) return false;
    final keys = await getBlockedSellerKeys();
    return keys.contains(phone.trim());
  }

  Future<void> blockSeller(String phone) async {
    final p = phone.trim();
    if (p.isEmpty) return;
    final keys = await getBlockedSellerKeys();
    if (!keys.contains(p)) {
      keys.add(p);
      await setBlockedSellerKeys(keys);
    }
  }

  Future<void> unblockSeller(String phone) async {
    final p = phone.trim();
    if (p.isEmpty) return;
    final keys = await getBlockedSellerKeys();
    keys.remove(p);
    await setBlockedSellerKeys(keys);
  }

  Future<void> clearBlockedSellers() async {
    await setBlockedSellerKeys(<String>[]);
  }

  // ---------------------------------------------------------------------------
  // Reported products (local)
  // ---------------------------------------------------------------------------

  static const String _kReportedProductIds = 'reported_product_ids_v1';
  static const String _kProductReports = 'product_reports_v1'; // JSON list

  /// Simple list of reported product IDs (used by some controllers).
  Future<List<String>> getReportedProductIds() async {
    return _prefs.getStringList(_kReportedProductIds) ?? <String>[];
  }

  Future<void> setReportedProductIds(List<String> ids) async {
    await _prefs.setStringList(_kReportedProductIds, ids);
  }

  /// Full report objects stored locally.
  Future<List<Map<String, dynamic>>> getProductReports() async {
    final raw = _prefs.getString(_kProductReports);
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
            .toList(growable: false);
      }
      return <Map<String, dynamic>>[];
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> addProductReport({
    required String productId,
    required String sellerPhone,
    required String reasonId,
    String? note,
  }) async {
    final id = productId.trim();
    if (id.isEmpty) return;

    final reports = (await getProductReports()).toList(growable: true);
    reports.add({
      'productId': id,
      'sellerPhone': sellerPhone.trim(),
      'reasonId': reasonId.trim(),
      'note': (note ?? '').trim(),
      'createdAt': DateTime.now().toIso8601String(),
    });

    await _prefs.setString(_kProductReports, jsonEncode(reports));

    final ids = await getReportedProductIds();
    if (!ids.contains(id)) {
      ids.add(id);
      await setReportedProductIds(ids);
    }
  }

  // ---------------------------------------------------------------------------
  // Service receipts (local)
  // ---------------------------------------------------------------------------

  static const String _kServiceReceipts = 'service_receipts_v1';

  String? getServiceReceiptsJson() => _prefs.getString(_kServiceReceipts);

  Future<void> setServiceReceiptsJson(String json) async {
    await _prefs.setString(_kServiceReceipts, json);
  }

  // ---- Verification (KYC) ----
  static const _kKycStatus = 'kyc_status_v1'; // none|pending|approved|rejected
  static const _kKycWaitlist = 'kyc_waitlist_v1';
  static const _kMyPublishCount = 'my_publish_count_v1';

  String getKycStatus() {
    return _prefs.getString(_kKycStatus) ?? 'none';
  }

  Future<void> setKycStatus(String status) async {
    await _prefs.setString(_kKycStatus, status);
  }

  bool getKycWaitlistJoined() {
    return _prefs.getBool(_kKycWaitlist) ?? false;
  }

  Future<void> setKycWaitlistJoined(bool joined) async {
    await _prefs.setBool(_kKycWaitlist, joined);
  }

  int getMyPublishCount() {
    return _prefs.getInt(_kMyPublishCount) ?? 0;
  }

  Future<void> incrementMyPublishCount() async {
    final next = getMyPublishCount() + 1;
    await _prefs.setInt(_kMyPublishCount, next);
  }

  // ---------------------------------------------------------------------------
  // User interests (AI-lite personalization, device-local)
  // ---------------------------------------------------------------------------
  static const String _kInterestCategoryCounts = 'interest_category_counts_v1';
  static const String _kInterestWilayaId = 'interest_wilaya_id_v1';
  static const String _kInterestMoughataaId = 'interest_moughataa_id_v1';

  Map<String, int> getInterestCategoryCounts() {
    final raw = _prefs.getString(_kInterestCategoryCounts);
    if (raw == null || raw.trim().isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      final out = <String, int>{};
      decoded.forEach((k, v) {
        final key = (k ?? '').toString().trim();
        if (key.isEmpty) return;
        final val = (v is num) ? v.toInt() : int.tryParse(v.toString()) ?? 0;
        if (val <= 0) return;
        out[key] = val;
      });
      return out;
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<void> bumpInterestCategory(String categoryId, {int by = 1}) async {
    final id = categoryId.trim();
    if (id.isEmpty) return;

    final counts = getInterestCategoryCounts();
    counts[id] = (counts[id] ?? 0) + (by <= 0 ? 1 : by);

    // Keep map bounded: keep top 60 categories by count.
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final capped = <String, int>{};
    for (final e in entries.take(60)) {
      capped[e.key] = e.value;
    }

    await _prefs.setString(_kInterestCategoryCounts, jsonEncode(capped));
  }

  List<String> getTopInterestCategories({int limit = 6}) {
    final counts = getInterestCategoryCounts();
    if (counts.isEmpty) return const <String>[];
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final out = <String>[];
    for (final e in entries.take(limit <= 0 ? 6 : limit)) {
      if (e.key.trim().isEmpty) continue;
      out.add(e.key);
    }
    return out;
  }

  String? getInterestWilayaId() {
    final v = _prefs.getString(_kInterestWilayaId);
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }

  String? getInterestMoughataaId() {
    final v = _prefs.getString(_kInterestMoughataaId);
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }

  Future<void> setInterestLocation(
      {String? wilayaId, String? moughataaId}) async {
    final w = (wilayaId ?? '').trim();
    final m = (moughataaId ?? '').trim();

    if (w.isEmpty) {
      await _prefs.remove(_kInterestWilayaId);
      await _prefs.remove(_kInterestMoughataaId);
      return;
    }

    await _prefs.setString(_kInterestWilayaId, w);
    if (m.isEmpty) {
      await _prefs.remove(_kInterestMoughataaId);
    } else {
      await _prefs.setString(_kInterestMoughataaId, m);
    }
  }

  /// Clears only the “For you” personalization suggestions for the given language.
  /// - Keeps recent search history (Temu-style “بحثك الأخير”)
  /// - Clears interest categories + saved interest location + hot search counts (used for “بحثك الأكثر”)
  Future<void> clearForYouSuggestions(String lang) async {
    final code = lang.trim().toLowerCase();
    await _prefs.remove(_kInterestCategoryCounts);
    await _prefs.remove(_kInterestWilayaId);
    await _prefs.remove(_kInterestMoughataaId);

    if (code.isNotEmpty) {
      await _prefs.remove('$_kHotSearchPrefix$code');
    }
  }

  Future<void> clearInterestSignals({String? lang}) async {
    // Optional lang clears hot searches and recent terms too.
    await _prefs.remove(_kInterestCategoryCounts);
    await _prefs.remove(_kInterestWilayaId);
    await _prefs.remove(_kInterestMoughataaId);

    if (lang != null) {
      final code = lang.trim().toLowerCase();
      if (code.isNotEmpty) {
        await _prefs.remove('$_kHotSearchPrefix$code');
        await _prefs.remove('$_kRecentSearchPrefix$code');
      }
    }
  }

  // ------------------------------------------------------------------------
  // Feature flags (local, can be overridden by Admin later)
  // ------------------------------------------------------------------------

  bool getImageEmbeddingSearchEnabled() {
    return _prefs.getBool(_kFfImageEmbeddingSearchEnabled) ?? false;
  }

  Future<void> setImageEmbeddingSearchEnabled(bool value) async {
    await _prefs.setBool(_kFfImageEmbeddingSearchEnabled, value);
  }

// ---- Device identity (for guest view uniqueness, etc.) ----
static const String _kDeviceId = 'device_id_v1';

String? _cachedDeviceId;

/// Stable device id stored in SharedPreferences.
Future<String> getOrCreateDeviceId() async {
  if (_cachedDeviceId != null && _cachedDeviceId!.trim().isNotEmpty) {
    return _cachedDeviceId!;
  }
  final existing = (_prefs.getString(_kDeviceId) ?? '').trim();
  if (existing.isNotEmpty) {
    _cachedDeviceId = existing;
    return existing;
  }
  final r = Random.secure();
  final now = DateTime.now().microsecondsSinceEpoch;
  final id =
      'd${now.toRadixString(36)}${r.nextInt(1 << 32).toRadixString(36)}';
  await _prefs.setString(_kDeviceId, id);
  _cachedDeviceId = id;
  return id;
}

// ---- Unique views per day (device-local cache) ----
// Map key: "<productId>__<viewerKey>" -> "YYYYMMDD"
static const String _kViewedPerDayV1 = 'viewed_per_day_v1';

Map<String, String> _decodeMapString(String? raw) {
  if (raw == null || raw.trim().isEmpty) return <String, String>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, String>{};
    final out = <String, String>{};
    for (final e in decoded.entries) {
      final k = (e.key ?? '').toString().trim();
      if (k.isEmpty) continue;
      final v = (e.value ?? '').toString().trim();
      if (v.isEmpty) continue;
      out[k] = v;
    }
    return out;
  } catch (_) {
    return <String, String>{};
  }
}

String _dayKeyUtcNow() {
  final now = DateTime.now().toUtc();
  return '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
}

Future<bool> markProductViewedToday(String productId,
    {required String viewerKey}) async {
  final pid = productId.trim();
  final vk = viewerKey.trim();
  if (pid.isEmpty || vk.isEmpty) return false;

  final dayKey = _dayKeyUtcNow();
  final key = '${pid}__${vk.replaceAll('/', '_')}';

  final map = _decodeMapString(_prefs.getString(_kViewedPerDayV1));
  final last = map[key] ?? '';
  if (last == dayKey) return false;

  map[key] = dayKey;

  // Keep it bounded
  if (map.length > 2500) {
    // Drop random ~25% to keep writes cheap
    final keys = map.keys.toList()..shuffle();
    final drop = (map.length * 0.25).floor();
    for (var i = 0; i < drop && i < keys.length; i++) {
      map.remove(keys[i]);
    }
  }

  await _prefs.setString(_kViewedPerDayV1, jsonEncode(map));
  return true;
}

}

/// Wraps the app in a ProviderScope that overrides [localStoreProvider].
class LocalStoreProviderScope extends StatefulWidget {
  const LocalStoreProviderScope({super.key, required this.child});
  final Widget child;

  @override
  State<LocalStoreProviderScope> createState() =>
      _LocalStoreProviderScopeState();
}

class _LocalStoreProviderScopeState extends State<LocalStoreProviderScope> {
  LocalStore? _store;

  @override
  void initState() {
    super.initState();
    LocalStore.create().then((s) {
      if (!mounted) return;
      setState(() => _store = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    if (store == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
      ],
      child: widget.child,
    );
  }
}
