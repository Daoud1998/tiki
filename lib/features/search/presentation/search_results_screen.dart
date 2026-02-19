import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/state/app_setings.dart';
import '../../../core/data/ma_catalog.dart';
import '../../../core/search/trending_search_chips_provider.dart';
import '../../product/domain/app_product.dart';
import '../../product/state/products_providers.dart';
import '../../../core/storage/local_store.dart';
import '../../../core/widgets/product_card.dart';
import 'filters_sheet.dart';
import '../../../core/state/profile_state.dart';
import '../../../core/state/blocked_sellers_controller.dart';
import '../../../core/state/reported_products_controller.dart';
import '../../../core/widgets/profile_setup_sheet.dart';

String _tr(BuildContext c,
    {required String ar, required String fr, required String en}) {
  final code = Localizations.localeOf(c).languageCode.toLowerCase();
  if (code == 'fr') return fr;
  if (code == 'en') return en;
  return ar;
}

class _SearchKey {
  const _SearchKey({
    required this.query,
    this.categoryId,
    this.limit = 240,
  });

  final String query;
  final String? categoryId;
  final int limit;

  @override
  bool operator ==(Object other) {
    return other is _SearchKey &&
        other.query == query &&
        other.categoryId == categoryId &&
        other.limit == limit;
  }

  @override
  int get hashCode => Object.hash(query, categoryId, limit);
}

final _searchResultsProvider =
    StreamProvider.autoDispose.family<List<AppProduct>, _SearchKey>((ref, key) {
  final repo = ref.watch(productsRepositoryProvider);
  final q = key.query.trim();

  // If query is empty, show active feed (category filtering happens locally in this screen).
  if (q.isEmpty) {
    return repo.watchActiveFeed(limit: key.limit);
  }

  return repo.watchSearch(q, categoryId: key.categoryId, limit: key.limit);
});

final _activeFeedBigProvider =
    StreamProvider.autoDispose.family<List<AppProduct>, int>((ref, limit) {
  return ref.watch(productsRepositoryProvider).watchActiveFeed(limit: limit);
});

/// Search results page:
/// - Stable AppBar (no sliver-geometry issues)
/// - Smart suggestions + popular chips
/// - Mini product strip with images (overflow-safe for AR/FR/EN)
class SearchResultsScreen extends ConsumerStatefulWidget {
  const SearchResultsScreen({
    super.key,
    this.wilaya,
    this.moughataa,
    this.excludedId,
    this.initialQuery,
    this.phone,
    this.categoryId,
    this.subCategoryId,
  });

  final String? wilaya;
  final String? moughataa;
  final String? excludedId;
  final String? initialQuery;
  final String? phone;
  final String? categoryId;
  final String? subCategoryId;

  @override
  ConsumerState<SearchResultsScreen> createState() =>
      _SearchResultsScreenState();
}

class _SearchResultsScreenState extends ConsumerState<SearchResultsScreen> {
  String _canonAny(String? v) => _normalizeQuery(v ?? '');

  String _normalizeQuery(String input) {
    var s = input.trim().toLowerCase();
    s = s.replaceAll(RegExp(r'[\u200f\u200e]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s;
  }

  // Phone search helpers ----------------------------------------------------
  // In Mauritania, local phone numbers are commonly 8 digits, sometimes
  // stored/pasted with +222 or 00222.
  String _digitsOnly(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

  String _strip00Prefix(String digits) {
    // Handle common international prefix "00".
    if (digits.startsWith('00') && digits.length > 2)
      return digits.substring(2);
    return digits;
  }

  String _tail8(String digits) {
    if (digits.length <= 8) return digits;
    return digits.substring(digits.length - 8);
  }

  bool _looksLikePhoneQuery(String raw) {
    final r = raw.trim();
    if (r.isEmpty) return false;
    // Only digits + separators.
    if (!RegExp(r'^[0-9\s\-\+\(\)]+$').hasMatch(r)) return false;
    final d = _strip00Prefix(_digitsOnly(r));
    return d.length >= 6; // allow partial but not too short
  }

  bool _phoneMatches(String? phone, String rawQueryOrPhone) {
    final qd = _strip00Prefix(_digitsOnly(rawQueryOrPhone));
    if (qd.isEmpty) return false;
    final pd = _strip00Prefix(_digitsOnly(phone ?? ''));
    if (pd.isEmpty) return false;

    // If user typed a local number (<= 8 digits), compare against the local tail.
    final pt = _tail8(pd);
    if (qd.length <= 8) return pt.contains(qd);

    // If user typed with country code, accept contains; also allow tail match.
    final qt = _tail8(qd);
    return pd.contains(qd) || pt.contains(qt);
  }

  bool _isPhoneSearchEnabledFor(AppProduct p) {
    final v = (p.attrs['__phone_search_enabled'] ?? '').trim().toLowerCase();
    if (v.isEmpty) return true; // legacy products (before the flag existed)
    return v == '1' || v == 'true' || v == 'yes' || v == 'on';
  }

  String? _resolveCategoryId(String? any) {
    final v = _canonAny(any);
    if (v.isEmpty) return null;
    for (final c in maCategories) {
      if (_canonAny(c.id) == v) return c.id;
      if (_canonAny(c.name.ar) == v ||
          _canonAny(c.name.fr) == v ||
          _canonAny(c.name.en) == v) {
        return c.id;
      }
    }
    return any?.trim();
  }

  String? _resolveSubCategoryId(String? any) {
    final v = _canonAny(any);
    if (v.isEmpty) return null;
    for (final c in maCategories) {
      for (final s in withOtherSubcategory(c.sub)) {
        if (_canonAny(s.id) == v) return s.id;
        if (_canonAny(s.name.ar) == v ||
            _canonAny(s.name.fr) == v ||
            _canonAny(s.name.en) == v) {
          return s.id;
        }
      }
    }
    return any?.trim();
  }

  final _qCtl = TextEditingController();
  Timer? _debounce;

  late SearchFilters _filters;

  // Last image-search context (for future Embeddings backend)
  String? _imageSearchPath;
  String _imageSearchBackend = 'ai_lite';
  List<String>? _imageSearchCandidateIds;

  static final List<String> _history = <String>[];

  bool _editingHistory = false;

  final GlobalKey _resultsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _filters = _initialFiltersFromRoute();

    final iq = widget.initialQuery?.trim();
    final ph = widget.phone?.trim();

    // Priority: explicit q, then phone.
    final seed = (iq != null && iq.isNotEmpty)
        ? iq
        : ((ph != null && ph.isNotEmpty) ? ph : null);

    if (seed != null && seed.isNotEmpty) {
      _qCtl.text = seed;
      _qCtl.selection = TextSelection.collapsed(offset: seed.length);
    }

    // Load Temu-style recent searches for this locale.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHistory();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _qCtl.dispose();
    super.dispose();
  }

  String _langCode(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase();

  Future<void> _loadHistory() async {
    final store = ref.read(localStoreProvider);
    final lang = _langCode(context);
    final list = store.getRecentSearchTerms(lang);
    if (!mounted) return;
    setState(() {
      _history
        ..clear()
        ..addAll(list);
    });
  }

  SearchFilters _initialFiltersFromRoute() {
    String? wilayaId;
    String? moughataaId;

    final w = _resolveWilaya(widget.wilaya);
    if (w != null) {
      wilayaId = w.id;
      final m = _resolveMoughataa(w, widget.moughataa);
      if (m != null) moughataaId = m.id;
    }

    final catId = _resolveCategoryId(widget.categoryId);
    final subId = _resolveSubCategoryId(widget.subCategoryId);

    return SearchFilters(
      wilayaId: wilayaId,
      moughataaId: moughataaId,
      categoryId: (catId == null || catId.trim().isEmpty) ? null : catId.trim(),
      subCategoryId:
          (subId == null || subId.trim().isEmpty) ? null : subId.trim(),
      sort: SearchSort.newest,
    );
  }

  Wilaya? _resolveWilaya(String? input) {
    if (input == null || input.trim().isEmpty) return null;
    final v = input.trim();

    final byId = findWilayaById(v);
    if (byId != null) return byId;

    for (final w in maWilayas) {
      final n = w.name;
      if (n.ar == v || n.fr == v || n.en == v) return w;
    }
    return null;
  }

  Moughataa? _resolveMoughataa(Wilaya w, String? input) {
    if (input == null || input.trim().isEmpty) return null;
    final v = input.trim();

    for (final m in w.moughataas) {
      if (m.id == v) return m;
    }
    for (final m in w.moughataas) {
      final n = m.name;
      if (n.ar == v || n.fr == v || n.en == v) return m;
    }
    return null;
  }

  bool _matchWilaya(AppProduct p, String wilayaId) {
    final w = findWilayaById(wilayaId);
    if (w == null) return false;
    return p.wilaya == w.name.ar ||
        p.wilaya == w.name.fr ||
        p.wilaya == w.name.en;
  }

  bool _matchMoughataa(AppProduct p, String wilayaId, String moughataaId) {
    final w = findWilayaById(wilayaId);
    if (w == null) return false;
    final m = w.moughataas.firstWhere(
      (x) => x.id == moughataaId,
      orElse: () => w.moughataas.first,
    );
    // If not found, treat as no match.
    if (m.id != moughataaId) return false;
    return p.moughataa == m.name.ar ||
        p.moughataa == m.name.fr ||
        p.moughataa == m.name.en;
  }

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _commitQuery(String q) {
    final cleaned = q.trim();
    if (cleaned.isEmpty) return;

    final isPhone = _looksLikePhoneQuery(cleaned);

    // Persist Temu-style recent searches (device-local).
    final store = ref.read(localStoreProvider);
    final lang = _langCode(context);
    if (!isPhone) {
      store.addRecentSearchTerm(lang, cleaned);
      store.incrementHotSearch(lang, cleaned);
      _history.removeWhere((x) => x.toLowerCase() == cleaned.toLowerCase());
      _history.insert(0, cleaned);
      if (_history.length > 18) _history.removeRange(18, _history.length);
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _qCtl.text = cleaned;
      _qCtl.selection = TextSelection.collapsed(offset: cleaned.length);
    });
  }

  Future<void> _openFilters() async {
    // Dynamic hint for the price slider, based on current catalog.
    // (Keeps the filter UI feeling “connected” to real products.)
    var maxPrice = 0;
    // Keep a local alias to prevent regressions where `source` was referenced
    // without being declared.
    final source =
        ref.read(productsFeedProvider).asData?.value ?? const <AppProduct>[];
    for (final p in source) {
      if (p.price > maxPrice) maxPrice = p.price;
      if (p.oldPrice != null && p.oldPrice! > maxPrice) maxPrice = p.oldPrice!;
    }
    // Round up a bit so the slider has a comfy top.
    maxPrice = (math.max(1, (maxPrice / 5000).ceil()) * 5000);

    final res = await showSearchFiltersSheet(
      context,
      initial: _filters,
      maxPriceHint: maxPrice,
    );
    if (!mounted || res == null) return;
    setState(() => _filters = res);

    // AI-lite personalization (device-local)
    final store = ref.read(localStoreProvider);
    final cat = (res.categoryId ?? '').trim();
    if (cat.isNotEmpty) {
      store.bumpInterestCategory(cat);
    }
    final w = (res.wilayaId ?? '').trim();
    if (w.isNotEmpty) {
      store.setInterestLocation(
          wilayaId: res.wilayaId, moughataaId: res.moughataaId);
    }
  }

  String? _inferCategoryFromText(String raw) {
    final q = _normalizeQuery(raw);
    if (q.isEmpty) return null;

    // 1) Direct match against category names (AR/FR/EN) and ids.
    for (final c in maCategories) {
      final id = _canonAny(c.id);
      final ar = _canonAny(c.name.ar);
      final fr = _canonAny(c.name.fr);
      final en = _canonAny(c.name.en);

      if (id.isNotEmpty && q.contains(id)) return c.id;
      if (ar.isNotEmpty && q.contains(ar)) return c.id;
      if (fr.isNotEmpty && q.contains(fr)) return c.id;
      if (en.isNotEmpty && q.contains(en)) return c.id;
    }

    // 2) Lightweight keyword heuristics (AI-lite).
    // Keep this tiny and safe: only broad buckets.
    bool hasAny(List<String> keys) => keys.any((k) => q.contains(_canonAny(k)));

    if (hasAny([
      'سيارة',
      'سيارات',
      'مركبة',
      'مركبات',
      'تويوتا',
      'مرسيدس',
      'هيونداي',
      'kia',
      'toyota',
    ])) {
      return 'vehicles';
    }
    if (hasAny([
      'شقة',
      'منزل',
      'بيت',
      'أرض',
      'قطعة',
      'عقار',
      'عقارات',
      'ايجار',
      'إيجار',
      'كراء',
    ])) {
      return 'real_estate';
    }
    if (hasAny([
      'هاتف',
      'موبايل',
      'ايفون',
      'آيفون',
      'iphone',
      'samsung',
      'سامسونج',
      'laptop',
      'حاسوب',
      'كمبيوتر',
    ])) {
      return 'electronics';
    }
    if (hasAny(['وظيفة', 'عمل', 'سيرة', 'cv', 'مطلوب', 'توظيف'])) {
      return 'jobs';
    }

    return null;
  }

  Future<void> _openImageSearch() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_tr(context,
            ar: 'ميزة البحث بالصورة قريباً',
            fr: 'Recherche par image bientôt',
            en: 'Image search coming soon')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openSmartAssistant() async {
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context);

    // -----------------------------------------------------------------------
    // AI-lite personalization (device-local)
    // -----------------------------------------------------------------------
    final store = ref.read(localStoreProvider);
    final lang = _langCode(context);

    final forYouCategoryIds = store.getTopInterestCategories(limit: 6);

    final hot = store.getHotSearchCounts(lang);
    final hotEntries = hot.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final forYouQueryTerms = <String>[];
    for (final e in hotEntries.take(6)) {
      final t = (e.key).trim();
      if (t.isEmpty) continue;
      if (forYouQueryTerms.any((x) => x.toLowerCase() == t.toLowerCase()))
        continue;
      forYouQueryTerms.add(t);
    }

    // Snapshot current state.
    final initialQuery = _qCtl.text.trim();
    final qCtl = TextEditingController(text: initialQuery);
    qCtl.selection = TextSelection.collapsed(offset: qCtl.text.length);

    var draftFilters = _filters;

    String? catName(String? id) {
      if (id == null || id.trim().isEmpty) return null;
      for (final c in maCategories) {
        if (c.id == id) {
          final code = locale.languageCode.toLowerCase();
          if (code == 'fr') return c.name.fr;
          if (code == 'en') return c.name.en;
          return c.name.ar;
        }
      }
      return id;
    }

    // Helpers ---------------------------------------------------------------
    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      IconData? icon,
    }) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8, bottom: 8),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) => onTap(),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16),
                const SizedBox(width: 6),
              ],
              Text(label),
            ],
          ),
        ),
      );
    }

    Future<void> applyAndClose(BuildContext sheetContext) async {
      if (!mounted) return;

      // Apply filters first.
      setState(() {
        _filters = draftFilters;
      });

      // Apply query (this method also does setState + saves history).
      final q = qCtl.text.trim();
      if (q.isNotEmpty) {
        _commitQuery(q);
      } else {
        setState(() {
          _qCtl.text = '';
          _qCtl.selection = const TextSelection.collapsed(offset: 0);
        });
      }

      if (!sheetContext.mounted) return;
      Navigator.of(sheetContext).pop();
    }

    Future<void> useNearMe() async {
      var p = ref.read(profileProvider).profile;
      if (p == null || !p.hasLocation) {
        await _editProfile();
        p = ref.read(profileProvider).profile;
      }
      if (p == null || !p.hasLocation) return;

      draftFilters = draftFilters.copyWith(
        wilayaId: p.wilayaId,
        moughataaId: p.moughataaId,
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final appliedCat = draftFilters.categoryId;
            final appliedSort = draftFilters.sort;
            final suggestedCat =
                (appliedCat == null || appliedCat.trim().isEmpty)
                    ? _inferCategoryFromText(qCtl.text)
                    : null;
            final hasLocation = (draftFilters.wilayaId != null &&
                draftFilters.wilayaId!.trim().isNotEmpty);

            final bottomPadding = MediaQuery.of(ctx).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: cs.outlineVariant,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _tr(ctx,
                                ar: 'بحث ذكي',
                                fr: 'Recherche intelligente',
                                en: 'Smart search'),
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          tooltip:
                              _tr(ctx, ar: 'إغلاق', fr: 'Fermer', en: 'Close'),
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    Text(
                      _tr(
                        ctx,
                        ar: 'اختصر الطريق: سأقترح لك فلاتر مناسبة حسب ما تكتب.',
                        fr: 'Raccourci: je propose des filtres selon votre recherche.',
                        en: 'Shortcut: I suggest filters based on what you type.',
                      ),
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: qCtl,
                      onChanged: (_) {
                        // Auto-suggest category from text (AI-lite)
                        final inf = _inferCategoryFromText(qCtl.text);
                        final infCat = inf?[0];
                        final infSub = inf?[1];
                        final curCat = (draftFilters.categoryId ?? '').trim();
                        if (curCat.isEmpty && infCat != null) {
                          draftFilters = draftFilters.copyWith(
                            categoryId: infCat,
                            subCategoryId: infSub,
                          );
                        }
                        setLocal(() {});
                      },
                      onSubmitted: (_) => applyAndClose(ctx),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: _tr(ctx,
                            ar: 'اكتب ما تبحث عنه…',
                            fr: 'Écrivez ce que vous cherchez…',
                            en: 'Type what you need…'),
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (suggestedCat != null &&
                        (appliedCat == null || appliedCat.trim().isEmpty)) ...[
                      Text(
                        _tr(ctx,
                            ar: 'اقتراح سريع',
                            fr: 'Suggestion',
                            en: 'Suggestion'),
                        style: Theme.of(ctx).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        children: [
                          chip(
                            label: catName(suggestedCat) ?? suggestedCat!,
                            selected: false,
                            icon: Icons.category_outlined,
                            onTap: () => setLocal(() {
                              draftFilters = draftFilters.copyWith(
                                  categoryId: suggestedCat,
                                  subCategoryId: null);
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      _tr(ctx,
                          ar: 'اختصارات', fr: 'Raccourcis', en: 'Shortcuts'),
                      style: Theme.of(ctx).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      children: [
                        chip(
                          label: _tr(ctx,
                              ar: 'قريب مني', fr: 'Près de moi', en: 'Near me'),
                          selected: hasLocation,
                          icon: Icons.near_me_outlined,
                          onTap: () async {
                            await useNearMe();
                            setLocal(() {});
                          },
                        ),
                        chip(
                          label: _tr(ctx,
                              ar: 'إعداد الموقع',
                              fr: 'Profil / lieu',
                              en: 'Profile / location'),
                          selected: false,
                          icon: Icons.person_outline,
                          onTap: () async {
                            await _editProfile();
                            final p = ref.read(profileProvider).profile;
                            if (p != null && p.hasLocation) {
                              setLocal(() {
                                draftFilters = draftFilters.copyWith(
                                  wilayaId: p.wilayaId,
                                  moughataaId: p.moughataaId,
                                );
                              });
                            }
                          },
                        ),
                        chip(
                          label: _tr(ctx,
                              ar: 'مسح الفلاتر', fr: 'Effacer', en: 'Clear'),
                          selected: false,
                          icon: Icons.cleaning_services_outlined,
                          onTap: () => setLocal(() {
                            draftFilters = draftFilters.cleared();
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _tr(ctx, ar: 'رتّب النتائج', fr: 'Trier', en: 'Sort'),
                      style: Theme.of(ctx).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      children: [
                        chip(
                          label: _tr(ctx,
                              ar: 'الأحدث', fr: 'Nouveaux', en: 'Newest'),
                          selected: appliedSort == SearchSort.newest,
                          icon: Icons.schedule,
                          onTap: () => setLocal(() {
                            draftFilters =
                                draftFilters.copyWith(sort: SearchSort.newest);
                          }),
                        ),
                        chip(
                          label: _tr(ctx,
                              ar: 'الأقل سعراً',
                              fr: 'Prix bas',
                              en: 'Lowest price'),
                          selected: appliedSort == SearchSort.priceLow,
                          icon: Icons.south,
                          onTap: () => setLocal(() {
                            draftFilters = draftFilters.copyWith(
                                sort: SearchSort.priceLow);
                          }),
                        ),
                        chip(
                          label: _tr(ctx,
                              ar: 'الأعلى سعراً',
                              fr: 'Prix haut',
                              en: 'Highest price'),
                          selected: appliedSort == SearchSort.priceHigh,
                          icon: Icons.north,
                          onTap: () => setLocal(() {
                            draftFilters = draftFilters.copyWith(
                                sort: SearchSort.priceHigh);
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _tr(ctx, ar: 'الفئة', fr: 'Catégorie', en: 'Category'),
                      style: Theme.of(ctx).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      children: [
                        chip(
                          label: _tr(ctx, ar: 'الكل', fr: 'Tout', en: 'All'),
                          selected:
                              appliedCat == null || appliedCat.trim().isEmpty,
                          icon: Icons.all_inclusive,
                          onTap: () => setLocal(() {
                            draftFilters = draftFilters.copyWith(
                                categoryId: null, subCategoryId: null);
                          }),
                        ),
                        for (final c in maCategories.take(8))
                          chip(
                            label: catName(c.id) ?? c.id,
                            selected: appliedCat == c.id,
                            icon: Icons.category_outlined,
                            onTap: () => setLocal(() {
                              draftFilters = draftFilters.copyWith(
                                  categoryId: c.id, subCategoryId: null);
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => applyAndClose(ctx),
                            icon: const Icon(Icons.check),
                            label: Text(_tr(ctx,
                                ar: 'تطبيق', fr: 'Appliquer', en: 'Apply')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text(_tr(ctx,
                                ar: 'إلغاء', fr: 'Annuler', en: 'Cancel')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<AppProduct> _applyFilters(List<AppProduct> source) {
    final raw = _qCtl.text.trim();
    final routePhone = widget.phone?.trim();
    final phoneFilter = (routePhone != null && routePhone.isNotEmpty)
        ? routePhone
        : (_looksLikePhoneQuery(raw) ? raw : null);

    final q = _normalizeQuery(raw);
    final blocked = ref.watch(blockedSellersProvider);
    final reported = ref.watch(reportedProductsProvider);
    final minP = _filters.minPrice;
    final maxP = _filters.maxPrice;

    var list = source.where((p) {
      if (widget.excludedId != null && p.id == widget.excludedId) return false;
      if (_isBlockedSeller(p, blocked)) return false;
      if (reported.contains(p.id)) return false;

      final effCat = _filters.categoryId;
      if (effCat != null && effCat.trim().isNotEmpty) {
        final pcAny = resolveCategoryIdAny(p.category);
        final pc =
            (pcAny == null || pcAny.trim().isEmpty) ? 'other' : pcAny.trim();
        if (pc != effCat.trim()) return false;
      }

      final effSub = _filters.subCategoryId;
      if (effSub != null && effSub.trim().isNotEmpty) {
        final ps = _resolveSubCategoryId(p.subCategory);
        if (effSub.trim() == kOtherSubcategoryId) {
          if (!isOtherSubcategoryValue(ps)) return false;
        } else {
          if ((ps ?? '').trim() != effSub.trim()) return false;
        }
      }

      // Search behavior:
      // - If user entered a phone number (or route specifies ?phone=...), show
      //   all products matching that phone.
      // - Otherwise do the normal text token search.
      if (phoneFilter != null && phoneFilter.isNotEmpty) {
        if (!_phoneMatches(p.phone, phoneFilter)) return false;
        // Respect seller privacy toggle.
        if (!_isPhoneSearchEnabledFor(p)) return false;
      } else if (q.isNotEmpty) {
        final hay = _normalizeQuery(
            '${p.title} ${p.neighborhood} ${p.moughataa} ${p.wilaya}');
        final tokens = q
            .split(' ')
            .where((t) => t.trim().isNotEmpty)
            .toList(growable: false);
        for (final t in tokens) {
          if (!hay.contains(t)) return false;
        }
      }

      if (_filters.wilayaId != null) {
        if (!_matchWilaya(p, _filters.wilayaId!)) return false;
      }

      if (_filters.wilayaId != null && _filters.moughataaId != null) {
        if (!_matchMoughataa(p, _filters.wilayaId!, _filters.moughataaId!))
          return false;
      }

      // Neighborhood filter (prefer stable id stored in attrs['neighborhood_id']).
      final nId = (_filters.neighborhoodId ?? '').trim();
      final nLabel = (_filters.neighborhood ?? '').trim();
      if (nId.isNotEmpty || nLabel.isNotEmpty) {
        final pid = (p.attrs['neighborhood_id'] ?? '').trim();
        if (nId.isNotEmpty) {
          if (pid.isNotEmpty) {
            if (pid != nId) return false;
          } else {
            // Fallback for old products that don't have neighborhood_id yet.
            if (nLabel.isEmpty) return false;
            final pn = _normalizeQuery(p.neighborhood);
            final nn = _normalizeQuery(nLabel);
            if (nn.isNotEmpty && !pn.contains(nn)) return false;
          }
        } else {
          // Label-only filter (manual/legacy).
          final pn = _normalizeQuery(p.neighborhood);
          final nn = _normalizeQuery(nLabel);
          if (nn.isNotEmpty && !pn.contains(nn)) return false;
        }
      }

      if (minP != null && p.price < minP) return false;
      if (maxP != null && p.price > maxP) return false;

      return true;
    }).toList(growable: false);

    switch (_filters.sort) {
      case SearchSort.newest:
        list.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
        break;
      case SearchSort.oldest:
        list.sort((a, b) => a.publishedAt.compareTo(b.publishedAt));
        break;
      case SearchSort.priceLow:
        list.sort((a, b) => a.price.compareTo(b.price));
        break;
      case SearchSort.priceHigh:
        list.sort((a, b) => b.price.compareTo(a.price));
        break;
    }

    return list.take(80).toList(growable: false);
  }

  bool _filtersActive() {
    if (_filters.wilayaId != null) return true;
    if (_filters.moughataaId != null) return true;
    if ((_filters.neighborhoodId ?? '').trim().isNotEmpty) return true;
    if ((_filters.neighborhood ?? '').trim().isNotEmpty) return true;
    if (_filters.minPrice != null) return true;
    if (_filters.maxPrice != null) return true;
    if (_filters.categoryId != null) return true;
    if (_filters.subCategoryId != null) return true;
    if (_filters.sort != SearchSort.newest) return true;
    return false;
  }

  List<_SuggestionItem> _buildSuggestions(
      BuildContext context, List<AppProduct> pool) {
    final raw = _qCtl.text.trim();

    if (raw.isEmpty) {
      return const [];
    }

    // Phone: if query looks like a phone number, keep suggestions simple and
    // focused.
    if (_looksLikePhoneQuery(raw)) {
      return [
        _SuggestionItem(label: raw, kind: _SuggestionKind.phone),
      ];
    }

    final q = raw.toLowerCase();
    final out = <_SuggestionItem>[];
    final seen = <String>{};

    void add(String label, _SuggestionKind kind) {
      final key = label.toLowerCase();
      if (seen.contains(key)) return;
      seen.add(key);
      out.add(_SuggestionItem(label: label, kind: kind));
    }

    // Recent searches first.
    for (final r in _history) {
      final rl = r.toLowerCase();
      if (rl.startsWith(q) || rl.contains(q)) {
        add(r, _SuggestionKind.recent);
        if (out.length >= 6) return out;
      }
    }

    for (final p in pool) {
      final title = p.title;
      if (title.toLowerCase().contains(q)) {
        if (title.toLowerCase().startsWith(q)) {
          add(title, _SuggestionKind.product);
        } else {
          for (final w in _words(title)) {
            final wl = w.toLowerCase();
            if (wl.startsWith(q) && wl.length >= 2) {
              add(w, _SuggestionKind.keyword);
              if (out.length >= 6) return out;
            }
          }
        }
      }
    }

    final loc = Localizations.localeOf(context);

    for (final c in maCategories) {
      final name = c.name.ofLocale(loc);
      if (name.toLowerCase().startsWith(q) || name.toLowerCase().contains(q)) {
        add(name, _SuggestionKind.category);
        if (out.length >= 6) return out;
      }
      for (final s in withOtherSubcategory(c.sub)) {
        final sn = s.name.ofLocale(loc);
        if (sn.toLowerCase().startsWith(q) || sn.toLowerCase().contains(q)) {
          add(sn, _SuggestionKind.category);
          if (out.length >= 6) return out;
        }
      }
    }

    for (final w in maWilayas) {
      final wn = w.name.ofLocale(loc);
      if (wn.toLowerCase().startsWith(q) || wn.toLowerCase().contains(q)) {
        add(wn, _SuggestionKind.place);
        if (out.length >= 6) return out;
      }
      for (final m in w.moughataas) {
        final mn = m.name.ofLocale(loc);
        if (mn.toLowerCase().startsWith(q) || mn.toLowerCase().contains(q)) {
          add(mn, _SuggestionKind.place);
          if (out.length >= 6) return out;
        }
      }
    }

    return out.take(6).toList(growable: false);
  }

  static Iterable<String> _words(String text) sync* {
    final cleaned = text
        .replaceAll(RegExp(r'[\u200f\u200e]'), ' ')
        .replaceAll(RegExp(r'[^0-9A-Za-z\u0600-\u06FF]+'), ' ');
    for (final w in cleaned.split(RegExp(r'\s+'))) {
      final t = w.trim();
      if (t.isEmpty) continue;
      if (RegExp(r'^\d+$').hasMatch(t)) continue;
      yield t;
    }
  }

  Future<void> _promptProfileIfNeeded() async {
    final s = ref.read(profileProvider);
    if (s.isLoading) return;
    if (s.prompted) return;

    final res = await showProfileSetupSheet(context, initial: s.profile);
    if (!mounted) return;

    if (res != null) {
      await ref.read(profileProvider.notifier).saveProfile(res);
    } else {
      await ref.read(profileProvider.notifier).markPrompted();
    }
  }

  Future<void> _editProfile() async {
    final s = ref.read(profileProvider);
    final res = await showProfileSetupSheet(context, initial: s.profile);
    if (!mounted) return;

    if (res != null) {
      await ref.read(profileProvider.notifier).saveProfile(res);
    } else if (!s.prompted) {
      await ref.read(profileProvider.notifier).markPrompted();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context);

    // Firestore-backed results (no mock)
    final rawQuery = _qCtl.text.trim();

    // Phone-search UI (seller store shortcut)
    final routePhone = (widget.phone ?? '').trim();
    final phoneFilterUi = routePhone.isNotEmpty
        ? routePhone
        : (_looksLikePhoneQuery(rawQuery) ? rawQuery : '');
    final isPhoneMode = phoneFilterUi.isNotEmpty;

    // For instant type-ahead search (even 1 character), we keep a bigger
    // local pool from Firestore and filter it locally with `contains`.
    // This avoids depending purely on searchTokens prefixes for every keystroke.
    final baseAsync = ref.watch(_activeFeedBigProvider(600));

    // Still watch the Firestore-token search as a fallback when the local pool
    // hasn't arrived yet (helps perceived speed on slow networks).
    final fastAsync = isPhoneMode
        ? null
        : ref.watch(_searchResultsProvider(_SearchKey(
            query: rawQuery,
            categoryId: _filters.categoryId,
            limit: 240,
          )));

    final sourceAsync = (fastAsync != null &&
            rawQuery.isNotEmpty &&
            (baseAsync.asData?.value.isEmpty ?? true))
        ? fastAsync
        : baseAsync;

    // Pool used for suggestions (prefer the main feed).
    final feedAsync = ref.watch(productsFeedProvider);
    final pool = feedAsync.asData?.value ??
        sourceAsync.asData?.value ??
        const <AppProduct>[];

    final items =
        _applyFilters(sourceAsync.asData?.value ?? const <AppProduct>[]);
    final suggestions = _buildSuggestions(context, pool);

    final sellerFromPhone =
        (isPhoneMode && items.isNotEmpty) ? items.first : null;

    // Device-local personalization (AI-lite)
    final store = ref.read(localStoreProvider);
    final lang = _langCode(context);
    final forYouCategoryIds = store.getTopInterestCategories(limit: 6);
    final forYouQueryTerms = store.topHotSearchTerms(lang, limit: 6);

    final adminChipsAsync = ref.watch(trendingSearchChipsProvider(locale));
    final quickChips = adminChipsAsync.maybeWhen(
      data: (v) => v,
      orElse: () => const <String>[],
    );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 72,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        leadingWidth: 104,
        leading: Row(
          children: [
            IconButton(
              tooltip: _tr(context, ar: 'رجوع', fr: 'Retour', en: 'Back'),
              icon: const BackButtonIcon(),
              onPressed: () {
                final r = GoRouter.of(context);
                if (r.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              },
            ),
            IconButton(
              onPressed: _openFilters,
              tooltip: _tr(context, ar: 'فلتر', fr: 'Filtres', en: 'Filters'),
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.tune_rounded),
                  if (_filtersActive())
                    PositionedDirectional(
                      top: -1,
                      end: -1,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        title: Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: TextField(
            controller: _qCtl,
            onChanged: _onQueryChanged,
            onSubmitted: _commitQuery,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: _tr(
                context,
                ar: 'ابحث عن منتج أو رقم هاتف...',
                fr: 'Rechercher (produit ou téléphone)...',
                en: 'Search (product or phone)...',
              ),
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: cs.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: Consumer(
              builder: (context, ref, _) => _LangPill(ref: ref),
            ),
          ),
          IconButton(
            tooltip: _tr(context,
                ar: 'بحث بالصورة',
                fr: 'Recherche par image',
                en: 'Image search'),
            onPressed: _openImageSearch,
            icon: const Icon(Icons.camera_alt_outlined),
          ),
          IconButton(
            tooltip: _tr(context,
                ar: 'بحث ذكي',
                fr: 'Recherche intelligente',
                en: 'Smart search'),
            onPressed: _openSmartAssistant,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
              child: _QuickFilterChipsBar(
                filters: _filters,
                onOpenAll: _openFilters,
                onUpdate: (next) => setState(() => _filters = next),
              ),
            ),
          ),

          if (suggestions.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                child: _SuggestionsPanel(
                  suggestions: suggestions,
                  onTap: (s) => _commitQuery(s.label),
                  onClearRecent: () async {
                    final store = ref.read(localStoreProvider);
                    final lang = _langCode(context);
                    await store.clearRecentSearchTerms(lang);
                    if (!mounted) return;
                    setState(() {
                      _history.clear();
                      _editingHistory = false;
                    });
                  },
                ),
              ),
            ),

          if (_qCtl.text.trim().isEmpty &&
              (forYouCategoryIds.isNotEmpty || forYouQueryTerms.isNotEmpty))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                child: _ForYouPanel(
                  categoryIds: forYouCategoryIds,
                  queryTerms: forYouQueryTerms,
                  onTapCategory: (id) {
                    store.bumpInterestCategory(id);
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _filters = _filters.copyWith(
                        categoryId: id,
                        subCategoryId: null,
                      );
                    });

                    // Jump to results so the user immediately sees the effect (Temu-style).
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final c = _resultsKey.currentContext;
                      if (c != null) {
                        Scrollable.ensureVisible(
                          c,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                  },
                  onTapQuery: (q) => _commitQuery(q),
                  onReset: () async {
                    await store.clearForYouSuggestions(lang);
                    if (!mounted) return;
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _tr(
                            context,
                            ar: 'تمت إعادة ضبط الاقتراحات ✅',
                            fr: 'Suggestions réinitialisées ✅',
                            en: 'Suggestions reset ✅',
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          if (_qCtl.text.trim().isEmpty && _history.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: _RecentSearchesPanel(
                  items: _history,
                  editing: _editingHistory,
                  onToggleEdit: () =>
                      setState(() => _editingHistory = !_editingHistory),
                  onTap: (s) => _commitQuery(s),
                  onDelete: (s) async {
                    final store = ref.read(localStoreProvider);
                    final lang = _langCode(context);
                    await store.removeRecentSearchTerm(lang, s);
                    if (!mounted) return;
                    setState(() {
                      _history.removeWhere(
                          (x) => x.toLowerCase() == s.toLowerCase());
                      if (_history.isEmpty) _editingHistory = false;
                    });
                  },
                  onClearAll: () async {
                    final store = ref.read(localStoreProvider);
                    final lang = _langCode(context);
                    await store.clearRecentSearchTerms(lang);
                    if (!mounted) return;
                    setState(() {
                      _history.clear();
                      _editingHistory = false;
                    });
                  },
                ),
              ),
            ),

          if (_qCtl.text.trim().isEmpty && quickChips.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: _QuickChipsPanel(
                  chips: quickChips,
                  onTap: (s) => _commitQuery(s),
                ),
              ),
            ),

          if (isPhoneMode)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: _SellerByPhoneCard(
                  phone: phoneFilterUi,
                  sample: sellerFromPhone,
                  resultsCount: items.length,
                  onOpenStore: sellerFromPhone == null
                      ? null
                      : () {
                          final sid = sellerFromPhone!.sellerId.trim();
                          if (sid.isEmpty) return;
                          final name = sellerFromPhone!.sellerName.trim();
                          final qp = name.isNotEmpty
                              ? '?name=${Uri.encodeComponent(name)}'
                              : '';
                          context.push('/seller/$sid$qp');
                        },
                ),
              ),
            ),

          // Result counter + “clear filters” shortcut.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                key: _resultsKey,
                children: [
                  Text(
                    _tr(
                      context,
                      ar: 'النتائج: ${items.length}',
                      fr: 'Résultats: ${items.length}',
                      en: 'Results: ${items.length}',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  if (_filtersActive())
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _filters = _filters.cleared()),
                      icon: const Icon(Icons.clear_all_rounded, size: 18),
                      label: Text(
                        _tr(context,
                            ar: 'مسح الفلاتر', fr: 'Effacer', en: 'Clear'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_qCtl.text.trim().isNotEmpty && items.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: _MiniProductStrip(
                  title: _tr(context,
                      ar: 'منتجات مطابقة',
                      fr: 'Produits',
                      en: 'Matching products'),
                  items: items.take(10).toList(growable: false),
                  onTap: (p) => context.push('/product/${p.id}'),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final p = items[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ProductCard(
                      product: p,
                      onTap: () => context.push('/product/${p.id}'),
                    ),
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
          if (baseAsync.isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!baseAsync.isLoading && baseAsync.hasError)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _tr(context,
                        ar: 'حدث خطأ أثناء جلب النتائج',
                        fr: 'Erreur lors du chargement',
                        en: 'Failed to load results'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          if (!baseAsync.isLoading && !baseAsync.hasError && items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  isPhoneMode
                      ? _tr(context,
                          ar: 'لا توجد نتائج لهذا الرقم',
                          fr: 'Aucun résultat pour ce numéro',
                          en: 'No results for this number')
                      : _tr(context,
                          ar: 'لا توجد نتائج',
                          fr: 'Aucun résultat',
                          en: 'No results'),
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.7),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LangPill extends ConsumerWidget {
  const _LangPill({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final override = ref.watch(localeOverrideProvider);
    final device = Localizations.localeOf(context);
    final current = (override ?? device).languageCode.toLowerCase();

    String label;
    switch (current) {
      case 'fr':
        label = 'FR';
        break;
      case 'en':
        label = 'EN';
        break;
      default:
        label = 'AR';
        break;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        final next = switch (current) {
          'ar' => const Locale('fr'),
          'fr' => const Locale('en'),
          _ => const Locale('ar'),
        };
        await ref.read(localeOverrideProvider.notifier).setLocaleOverride(next);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.primary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style:
                    TextStyle(color: cs.primary, fontWeight: FontWeight.w900)),
            const SizedBox(width: 6),
            Icon(Icons.public, size: 16, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

enum _SuggestionKind {
  recent,
  popular,
  phone,
  keyword,
  product,
  category,
  place
}

class _SuggestionItem {
  const _SuggestionItem({
    required this.label,
    required this.kind,
  });

  final String label;
  final _SuggestionKind kind;
}

class _SuggestionsPanel extends StatelessWidget {
  const _SuggestionsPanel({
    required this.suggestions,
    required this.onTap,
    required this.onClearRecent,
  });

  final List<_SuggestionItem> suggestions;
  final ValueChanged<_SuggestionItem> onTap;
  final VoidCallback onClearRecent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final hasRecent = suggestions.any((s) => s.kind == _SuggestionKind.recent);
    final title =
        _tr(context, ar: 'اقتراحات', fr: 'Suggestions', en: 'Suggestions');
    final clear = _tr(context, ar: 'مسح', fr: 'Effacer', en: 'Clear');

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const Spacer(),
                if (hasRecent)
                  TextButton(
                    onPressed: onClearRecent,
                    child: Text(clear),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: suggestions.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = suggestions[i];
              return ListTile(
                dense: true,
                leading: Icon(_iconFor(s.kind), size: 18),
                title: Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14.5),
                ),
                onTap: () => onTap(s),
              );
            },
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(_SuggestionKind k) {
    switch (k) {
      case _SuggestionKind.recent:
        return Icons.history_rounded;
      case _SuggestionKind.popular:
        return Icons.local_fire_department_outlined;
      case _SuggestionKind.phone:
        return Icons.phone_rounded;
      case _SuggestionKind.keyword:
        return Icons.search_rounded;
      case _SuggestionKind.product:
        return Icons.shopping_bag_outlined;
      case _SuggestionKind.category:
        return Icons.grid_view_rounded;
      case _SuggestionKind.place:
        return Icons.place_outlined;
    }
  }
}

class _QuickChipsPanel extends StatelessWidget {
  const _QuickChipsPanel({required this.chips, required this.onTap});

  final List<String> chips;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Mint tint (requested): subtle, modern, and consistent with the Support tiles.
    const mint = Color(0xFF2ED3B7);
    final panelTint = mint.withOpacity(isDark ? 0.06 : 0.05);
    final chipBg = mint.withOpacity(isDark ? 0.16 : 0.11);
    final chipInk = mint.withOpacity(isDark ? 0.22 : 0.18);

    final title = _tt(
      context,
      ar: 'الأكثر بحثاً',
      fr: 'Les plus recherchés',
      en: 'Popular searches',
    );

    if (chips.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(panelTint, cs.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department_outlined, size: 18, color: mint),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in chips)
                Ink(
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color:
                          cs.outlineVariant.withOpacity(isDark ? 0.55 : 0.45),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    splashColor: chipInk,
                    highlightColor: chipInk.withOpacity(0.65),
                    onTap: () => onTap(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: Text(
                          c,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _tt(BuildContext c,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'fr') return fr;
    if (code == 'en') return en;
    return ar;
  }
}

class _SellerByPhoneCard extends StatelessWidget {
  const _SellerByPhoneCard({
    required this.phone,
    required this.sample,
    required this.resultsCount,
    this.onOpenStore,
  });

  final String phone;
  final AppProduct? sample;
  final int resultsCount;
  final VoidCallback? onOpenStore;

  String _maskPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 4) return digits;
    final tail = digits.substring(digits.length - 4);
    return '•••• $tail';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final masked = _maskPhone(phone);
    final hasSeller = sample != null;

    final title = hasSeller
        ? _tr(context,
            ar: 'متجر البائع', fr: 'Magasin du vendeur', en: 'Seller store')
        : _tr(context,
            ar: 'بحث برقم الهاتف',
            fr: 'Recherche par téléphone',
            en: 'Phone search');

    final sellerName = (sample?.sellerName ?? '').trim();

    final line1 = hasSeller
        ? (sellerName.isEmpty
            ? _tr(context, ar: 'بائع', fr: 'Vendeur', en: 'Seller')
            : sellerName)
        : _tr(context,
            ar: 'لا توجد نتائج لهذا الرقم',
            fr: 'Aucun résultat pour ce numéro',
            en: 'No results for this number');

    final line2 = hasSeller
        ? _tr(context,
            ar: 'النتائج: $resultsCount  •  $masked',
            fr: 'Résultats: $resultsCount  •  $masked',
            en: 'Results: $resultsCount  •  $masked')
        : _tr(context,
            ar: 'قد يكون البائع أوقف الظهور بالبحث برقم الهاتف  •  $masked',
            fr: 'Le vendeur a peut-être désactivé la recherche  •  $masked',
            en: 'Seller may have disabled phone search  •  $masked');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              hasSeller ? Icons.storefront_outlined : Icons.phone_iphone,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    )),
                const SizedBox(height: 4),
                Text(
                  line1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  line2,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.68),
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          if (hasSeller) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onOpenStore,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(
                  _tr(context, ar: 'فتح المتجر', fr: 'Ouvrir', en: 'Open')),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniProductStrip extends StatelessWidget {
  const _MiniProductStrip({
    required this.title,
    required this.items,
    required this.onTap,
  });

  final String title;
  final List<AppProduct> items;
  final ValueChanged<AppProduct> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Heights are fixed by design to prevent ANY overflow across languages or textScale.
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.35);
    final stripH = (176.0 * scale).clamp(176.0, 230.0);
    final infoH = (64.0 * scale).clamp(64.0, 86.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: stripH,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final p = items[i];
                final priceText = (p.price <= 0)
                    ? _tr(context,
                        ar: 'حسب الاتفاق', fr: 'À négocier', en: 'Negotiable')
                    : '${p.price} MRU';

                return SizedBox(
                  width: 132,
                  height: stripH,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onTap(p),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: cs.outlineVariant.withOpacity(0.6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ✅ Image takes EXACT remaining space. No clamp, no guesswork.
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(14)),
                              child: p.imageUrl.trim().isEmpty
                                  ? Container(
                                      color: cs.surfaceContainerHighest
                                          .withOpacity(0.55),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.image_outlined,
                                        color: cs.onSurface.withOpacity(0.45),
                                      ),
                                    )
                                  : Image.network(
                                      p.imageUrl,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: cs.surfaceContainerHighest
                                            .withOpacity(0.55),
                                        alignment: Alignment.center,
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                          color: cs.onSurface.withOpacity(0.45),
                                        ),
                                      ),
                                    ),
                            ),
                          ),

                          // ✅ Bottom info has fixed height => never overflows.
                          SizedBox(
                            height: infoH,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    p.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    strutStyle: const StrutStyle(
                                      fontSize: 12,
                                      height: 1.0,
                                      forceStrutHeight: true,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      priceText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      strutStyle: const StrutStyle(
                                        fontSize: 12,
                                        height: 1.0,
                                        forceStrutHeight: true,
                                      ),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

bool _isBlockedSeller(AppProduct p, Set<String> blocked) {
  final sid = (p.sellerId ?? '').trim();
  if (sid.isNotEmpty && blocked.contains(sid)) return true;
  return _isBlockedPhone(p.phone, blocked);
}

bool _isBlockedPhone(String? phone, Set<String> blocked) {
  if (phone == null) return false;
  final cleaned = phone.trim().replaceAll(RegExp(r'[^0-9\+]'), '');
  if (cleaned.isEmpty) return false;
  return blocked.contains(cleaned);
}

class _ForYouPanel extends StatelessWidget {
  const _ForYouPanel({
    super.key,
    required this.categoryIds,
    required this.queryTerms,
    required this.onTapCategory,
    required this.onTapQuery,
    required this.onReset,
  });

  final List<String> categoryIds;
  final List<String> queryTerms;
  final ValueChanged<String> onTapCategory;
  final ValueChanged<String> onTapQuery;
  final Future<void> Function() onReset;

  CategoryNode? _findCategory(String id) {
    final v = id.trim();
    if (v.isEmpty) return null;
    for (final c in maCategories) {
      if (c.id == v) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final catChips = <Widget>[];
    for (final id in categoryIds) {
      final c = _findCategory(id);
      if (c == null) continue;
      catChips.add(
        ActionChip(
          onPressed: () => onTapCategory(id),
          label: Text(c.name.of(context)),
        ),
      );
    }

    final termChips = <Widget>[];
    for (final q in queryTerms) {
      final t = q.trim();
      if (t.isEmpty) continue;
      termChips.add(
        ActionChip(
          onPressed: () => onTapQuery(t),
          label: Text(t),
        ),
      );
    }

    // If we couldn't resolve category labels, hide the whole panel.
    final hasAny = catChips.isNotEmpty || termChips.isNotEmpty;
    if (!hasAny) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _tr(context, ar: 'مقترح لك', fr: 'Pour vous', en: 'For you'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: () {
                  onReset();
                },
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: Text(
                  _tr(context,
                      ar: 'إعادة ضبط', fr: 'Réinitialiser', en: 'Reset'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (catChips.isNotEmpty) ...[
            Text(
              _tr(context, ar: 'فئات', fr: 'Catégories', en: 'Categories'),
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: catChips),
            const SizedBox(height: 10),
          ],
          if (termChips.isNotEmpty) ...[
            Text(
              _tr(context,
                  ar: 'بحثك الأكثر', fr: 'Vos recherches', en: 'Your searches'),
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: termChips),
          ],
        ],
      ),
    );
  }
}

class _RecentSearchesPanel extends StatelessWidget {
  const _RecentSearchesPanel({
    required this.items,
    required this.editing,
    required this.onToggleEdit,
    required this.onTap,
    required this.onDelete,
    required this.onClearAll,
  });

  final List<String> items;
  final bool editing;
  final VoidCallback onToggleEdit;
  final void Function(String) onTap;
  final Future<void> Function(String) onDelete;
  final Future<void> Function() onClearAll;

  String _tr(BuildContext c,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'fr') return fr;
    if (code == 'en') return en;
    return ar;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _tr(context, ar: 'بحثك الأخير', fr: 'Récents', en: 'Recent'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              TextButton(
                onPressed: onToggleEdit,
                child: Text(
                  editing
                      ? _tr(context, ar: 'تم', fr: 'OK', en: 'Done')
                      : _tr(context, ar: 'تعديل', fr: 'Modifier', en: 'Edit'),
                ),
              ),
              if (editing)
                TextButton(
                  onPressed: () async => onClearAll(),
                  child:
                      Text(_tr(context, ar: 'مسح', fr: 'Effacer', en: 'Clear')),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in items.take(18))
                InputChip(
                  label: Text(s),
                  onPressed: () => onTap(s),
                  deleteIcon: editing
                      ? const Icon(Icons.close_rounded, size: 18)
                      : null,
                  onDeleted: editing ? () async => onDelete(s) : null,
                  side: BorderSide(color: cs.outlineVariant),
                  backgroundColor: cs.surface,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Temu-style quick filter chips (compact, under the search box)
// ---------------------------------------------------------------------------

class _QuickFilterChipsBar extends StatelessWidget {
  const _QuickFilterChipsBar({
    required this.filters,
    required this.onOpenAll,
    required this.onUpdate,
  });

  final SearchFilters filters;
  final VoidCallback onOpenAll;
  final ValueChanged<SearchFilters> onUpdate;

  String _l10n3(BuildContext c, L10n3 n) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'fr') return n.fr;
    if (code == 'en') return n.en;
    return n.ar;
  }

  String _fmtNum(int v) {
    // Group digits with spaces: 260000 -> "260 000"
    final s = v.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final left = s.length - i;
      buf.write(s[i]);
      if (left > 1 && left % 3 == 1) buf.write(' ');
    }
    return (v < 0) ? '-${buf.toString()}' : buf.toString();
  }

  String _categoryLabel(BuildContext c) {
    final id = (filters.categoryId ?? '').trim();
    if (id.isEmpty) {
      return _tr(c,
          ar: 'الفئة: الكل', fr: 'Catégorie: Tout', en: 'Category: All');
    }
    final cat = maCategories.cast<dynamic>().firstWhere(
          (x) => (x.id ?? '').toString() == id,
          orElse: () => null,
        );
    if (cat == null) {
      return _tr(c,
          ar: 'الفئة: $id', fr: 'Catégorie: $id', en: 'Category: $id');
    }
    final name = _l10n3(c, cat.name as L10n3);
    return _tr(c,
        ar: 'الفئة: $name', fr: 'Catégorie: $name', en: 'Category: $name');
  }

  String _locationLabel(BuildContext c) {
    final wId = (filters.wilayaId ?? '').trim();
    final mId = (filters.moughataaId ?? '').trim();
    if (wId.isEmpty) {
      return _tr(c, ar: 'المكان: الكل', fr: 'Lieu: Tout', en: 'Location: All');
    }
    final w = findWilayaById(wId);
    final wName = (w == null) ? wId : _l10n3(c, w.name);
    if (mId.isEmpty || w == null) {
      return _tr(c,
          ar: 'المكان: $wName', fr: 'Lieu: $wName', en: 'Location: $wName');
    }
    Moughataa? m;
    for (final x in w.moughataas) {
      if (x.id == mId) {
        m = x;
        break;
      }
    }
    if (m == null) {
      return _tr(c,
          ar: 'المكان: $wName', fr: 'Lieu: $wName', en: 'Location: $wName');
    }
    final mName = _l10n3(c, m.name);
    return _tr(c,
        ar: 'المكان: $wName · $mName',
        fr: 'Lieu: $wName · $mName',
        en: 'Location: $wName · $mName');
  }

  String _priceLabel(BuildContext c) {
    final minP = filters.minPrice;
    final maxP = filters.maxPrice;
    if (minP == null && maxP == null) {
      return _tr(c, ar: 'السعر: الكل', fr: 'Prix: Tous', en: 'Price: Any');
    }
    final a = (minP ?? 0);
    final b = (maxP ?? 0);
    final range = (minP != null && maxP != null)
        ? '${_fmtNum(a)}–${_fmtNum(b)}'
        : (minP != null ? '≥ ${_fmtNum(a)}' : '≤ ${_fmtNum(b)}');
    return _tr(c, ar: 'السعر: $range', fr: 'Prix: $range', en: 'Price: $range');
  }

  String _sortLabel(BuildContext c) {
    switch (filters.sort) {
      case SearchSort.newest:
        return _tr(c,
            ar: 'الترتيب: الأحدث', fr: 'Tri: Récent', en: 'Sort: Newest');
      case SearchSort.oldest:
        return _tr(c,
            ar: 'الترتيب: الأقدم', fr: 'Tri: Ancien', en: 'Sort: Oldest');
      case SearchSort.priceLow:
        return _tr(c,
            ar: 'الترتيب: الأرخص', fr: 'Tri: Moins cher', en: 'Sort: Lowest');
      case SearchSort.priceHigh:
        return _tr(c,
            ar: 'الترتيب: الأعلى', fr: 'Tri: Plus cher', en: 'Sort: Highest');
    }
  }

  bool _hasPrice() => filters.minPrice != null || filters.maxPrice != null;
  bool _hasLocation() => (filters.wilayaId ?? '').trim().isNotEmpty;
  bool _hasCategory() => (filters.categoryId ?? '').trim().isNotEmpty;
  bool _hasSort() => filters.sort != SearchSort.newest;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget chip({
      required String label,
      required VoidCallback onTap,
      VoidCallback? onClear,
      IconData? icon,
      bool emphasized = false,
    }) {
      final baseStyle = Theme.of(context).textTheme.labelLarge;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: InputChip(
          label: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: baseStyle),
          avatar: icon == null ? null : Icon(icon, size: 18),
          onPressed: onTap,
          onDeleted: onClear,
          deleteIcon: const Icon(Icons.close_rounded, size: 18),
          showCheckmark: false,
          side: BorderSide(
            color: emphasized
                ? cs.primary.withOpacity(0.35)
                : cs.outlineVariant.withOpacity(0.7),
          ),
          backgroundColor:
              emphasized ? cs.primary.withOpacity(0.08) : cs.surface,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(
            label: _locationLabel(context),
            icon: Icons.place_outlined,
            emphasized: _hasLocation(),
            onTap: () async {
              final next = await _pickLocation(context, filters);
              if (next != null) onUpdate(next);
            },
            onClear: _hasLocation()
                ? () => onUpdate(
                    filters.copyWith(wilayaId: null, moughataaId: null))
                : null,
          ),
          chip(
            label: _priceLabel(context),
            icon: Icons.payments_outlined,
            emphasized: _hasPrice(),
            onTap: () async {
              final next = await _pickPrice(context, filters);
              if (next != null) onUpdate(next);
            },
            onClear: _hasPrice()
                ? () =>
                    onUpdate(filters.copyWith(minPrice: null, maxPrice: null))
                : null,
          ),
          chip(
            label: _sortLabel(context),
            icon: Icons.sort_rounded,
            emphasized: _hasSort(),
            onTap: () async {
              final next = await _pickSort(context, filters);
              if (next != null) onUpdate(next);
            },
            onClear: _hasSort()
                ? () => onUpdate(filters.copyWith(sort: SearchSort.newest))
                : null,
          ),
          chip(
            label: _categoryLabel(context),
            icon: Icons.category_outlined,
            emphasized: _hasCategory(),
            onTap: () async {
              final next = await _pickCategory(context, filters);
              if (next != null) onUpdate(next);
            },
            onClear: _hasCategory()
                ? () => onUpdate(
                    filters.copyWith(categoryId: null, subCategoryId: null))
                : null,
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 2),
            child: TextButton.icon(
              onPressed: onOpenAll,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(_tr(context, ar: 'المزيد', fr: 'Plus', en: 'More')),
              style: TextButton.styleFrom(
                foregroundColor: cs.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<SearchFilters?> _pickSort(
      BuildContext context, SearchFilters cur) async {
    final res = await showModalBottomSheet<SearchSort>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        var selected = cur.sort;
        return StatefulBuilder(
          builder: (context, setState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      _tr(context, ar: 'الترتيب', fr: 'Tri', en: 'Sort'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _sortRadio(context, SearchSort.newest, selected,
                      (v) => setState(() => selected = v)),
                  _sortRadio(context, SearchSort.oldest, selected,
                      (v) => setState(() => selected = v)),
                  _sortRadio(context, SearchSort.priceLow, selected,
                      (v) => setState(() => selected = v)),
                  _sortRadio(context, SearchSort.priceHigh, selected,
                      (v) => setState(() => selected = v)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, selected),
                      child: Text(_tr(context,
                          ar: 'تطبيق', fr: 'Appliquer', en: 'Apply')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (res == null) return null;
    return cur.copyWith(sort: res);
  }

  Widget _sortRadio(
    BuildContext context,
    SearchSort value,
    SearchSort group,
    ValueChanged<SearchSort> onChanged,
  ) {
    String label;
    switch (value) {
      case SearchSort.newest:
        label = _tr(context, ar: 'الأحدث', fr: 'Récent', en: 'Newest');
        break;
      case SearchSort.oldest:
        label = _tr(context, ar: 'الأقدم', fr: 'Ancien', en: 'Oldest');
        break;
      case SearchSort.priceLow:
        label = _tr(context, ar: 'الأرخص', fr: 'Moins cher', en: 'Lowest');
        break;
      case SearchSort.priceHigh:
        label = _tr(context, ar: 'الأعلى', fr: 'Plus cher', en: 'Highest');
        break;
    }
    return RadioListTile<SearchSort>(
      value: value,
      groupValue: group,
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
      title: Text(label),
      dense: true,
    );
  }

  Future<SearchFilters?> _pickCategory(
      BuildContext context, SearchFilters cur) async {
    final res = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            children: [
              ListTile(
                title: Text(_tr(context,
                    ar: 'كل الفئات',
                    fr: 'Toutes les catégories',
                    en: 'All categories')),
                onTap: () => Navigator.pop(context, ''),
              ),
              const Divider(height: 1),
              ...maCategories.map((c) {
                final name = _l10n3(context, c.name);
                return ListTile(
                  title: Text(name),
                  trailing: (cur.categoryId == c.id)
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, c.id),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
    if (res == null) return null;
    final id = res.trim().isEmpty ? null : res.trim();
    return cur.copyWith(categoryId: id, subCategoryId: null);
  }

  Future<SearchFilters?> _pickLocation(
      BuildContext context, SearchFilters cur) async {
    final res = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        String? wId = (cur.wilayaId ?? '').trim().isEmpty ? null : cur.wilayaId;
        String? mId =
            (cur.moughataaId ?? '').trim().isEmpty ? null : cur.moughataaId;

        return StatefulBuilder(
          builder: (context, setState) {
            final w = (wId == null) ? null : findWilayaById(wId!);
            final moughataa = (w == null) ? const <Moughataa>[] : w.moughataas;

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 14,
                  right: 14,
                  top: 8,
                  bottom: 14 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        _tr(context, ar: 'المكان', fr: 'Lieu', en: 'Location'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: wId,
                      decoration: InputDecoration(
                        labelText: _tr(context,
                            ar: 'الولاية', fr: 'Wilaya', en: 'Wilaya'),
                        filled: true,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                              _tr(context, ar: 'الكل', fr: 'Tout', en: 'All')),
                        ),
                        ...maWilayas.map((w) => DropdownMenuItem(
                              value: w.id,
                              child: Text(_l10n3(context, w.name)),
                            )),
                      ],
                      onChanged: (v) {
                        setState(() {
                          wId = v;
                          mId = null;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: mId,
                      decoration: InputDecoration(
                        labelText: _tr(context,
                            ar: 'المقاطعة', fr: 'Moughataa', en: 'Moughataa'),
                        filled: true,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                              _tr(context, ar: 'الكل', fr: 'Tout', en: 'All')),
                        ),
                        ...moughataa.map((m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(_l10n3(context, m.name)),
                            )),
                      ],
                      onChanged: (v) => setState(() => mId = v),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, <String, String?>{
                          'wilayaId': wId,
                          'moughataaId': mId,
                        }),
                        child: Text(_tr(context,
                            ar: 'تطبيق', fr: 'Appliquer', en: 'Apply')),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (res == null) return null;
    final wId = (res?['wilayaId'] ?? '').trim();
    final mId = (res?['moughataaId'] ?? '').trim();
    return cur.copyWith(
      wilayaId: wId.isEmpty ? null : wId,
      moughataaId: mId.isEmpty ? null : mId,
    );
  }

  Future<SearchFilters?> _pickPrice(
      BuildContext context, SearchFilters cur) async {
    // Compute a reasonable max price for the slider.
    // NOTE: We intentionally do not read providers here, so this method
    // can be used safely from any widget scope.
    var maxPrice = math.max(cur.maxPrice ?? 0, cur.minPrice ?? 0);
    if (maxPrice <= 0) maxPrice = 2000000; // fallback
    maxPrice = (math.max(1, (maxPrice / 5000).ceil()) * 5000);
    maxPrice = math.min(maxPrice, 100000000); // hard cap

    final res = await showModalBottomSheet<List<int?>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var start = (cur.minPrice ?? 0).clamp(0, maxPrice);
        var end = (cur.maxPrice ?? maxPrice).clamp(0, maxPrice);
        if (end < start) end = start;

        final minCtl =
            TextEditingController(text: (cur.minPrice ?? '').toString());
        final maxCtl =
            TextEditingController(text: (cur.maxPrice ?? '').toString());

        return StatefulBuilder(
          builder: (context, setState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 14,
                right: 14,
                top: 8,
                bottom: 14 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      _tr(context,
                          ar: 'السعر (MRU)',
                          fr: 'Prix (MRU)',
                          en: 'Price (MRU)'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minCtl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText:
                                _tr(context, ar: 'أدنى', fr: 'Min', en: 'Min'),
                            filled: true,
                          ),
                          onChanged: (v) {
                            final n = int.tryParse(v.replaceAll(' ', ''));
                            setState(() {
                              start = (n ?? 0).clamp(0, maxPrice);
                              if (end < start) end = start;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: maxCtl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText:
                                _tr(context, ar: 'أقصى', fr: 'Max', en: 'Max'),
                            filled: true,
                          ),
                          onChanged: (v) {
                            final n = int.tryParse(v.replaceAll(' ', ''));
                            setState(() {
                              end = (n ?? maxPrice).clamp(0, maxPrice);
                              if (end < start) start = end;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  RangeSlider(
                    values: RangeValues(start.toDouble(), end.toDouble()),
                    min: 0,
                    max: maxPrice.toDouble(),
                    onChanged: (r) {
                      setState(() {
                        start = r.start.round();
                        end = r.end.round();
                        minCtl.text = start == 0 ? '' : start.toString();
                        maxCtl.text = end == maxPrice ? '' : end.toString();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.pop(context, <int?>[null, null]),
                          child: Text(_tr(context,
                              ar: 'مسح', fr: 'Effacer', en: 'Clear')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final minV = (start <= 0) ? null : start;
                            final maxV = (end >= maxPrice) ? null : end;
                            Navigator.pop(context, <int?>[minV, maxV]);
                          },
                          child: Text(_tr(context,
                              ar: 'تطبيق', fr: 'Appliquer', en: 'Apply')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (res == null) return null;
    return cur.copyWith(minPrice: res[0], maxPrice: res[1]);
  }
}
