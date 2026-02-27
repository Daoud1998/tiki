import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/support_contacts.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_storage/firebase_storage.dart';

import '../../../app/localization/l10n.dart';
import '../../../core/data/ma_catalog.dart';
import '../../../core/i18n/tikki_tr.dart';
import '../../../core/mocks/promo_moderation.dart';

import '../../../core/storage/local_store.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/state/profile_state.dart';
import '../../../core/search/ma_search_dictionary.dart';
import '../../../core/widgets/product_card.dart';
import '../../../core/widgets/search_lang_bar.dart' as slb;
import '../../notifications/domain/app_notification.dart';
import '../../notifications/presentation/notifications_controller.dart';
import '../../payments/data/payments_settings_repository.dart';
import '../../payments/state/payments_providers.dart';
import '../../product/data/products_repository.dart';
import '../../product/domain/app_product.dart';
import '../../promo_ads/data/promo_ads_plans_repository.dart';
import '../../promo_ads/state/promo_ads_plans_providers.dart';
import '../../receipts/presentation/receipts_controller.dart';
import '../state/home_offers_provider.dart';

/// A small "refresh bus" used in mock mode.
///
/// - Tapping the Home icon triggers a refresh.
/// - Pull-to-refresh at the top triggers a refresh.
final homeRefreshTickProvider = StateProvider<int>((ref) => 0);

/// Scroll controller shared between HomeScreen and the bottom-nav Home tap.
final homeScrollControllerProvider = Provider<ScrollController>((ref) {
  final c = ScrollController();
  ref.onDispose(c.dispose);
  return c;
});

/// Public products feed shown on Home.
/// NOTE: This feed is intentionally NOT tied to the signed-in user.
/// Guests should see the same marketplace feed.
final homeProductsFeedProvider =
    StreamProvider.autoDispose<List<AppProduct>>((ref) {
  final repo = ref.read(productsRepositoryProvider);
  return repo.watchActiveFeed(limit: 50);
});

// --- Promo Ads (Firestore) ---
//
// Only a limited number of ads show in the moving ticker.
// مميّز ads are shown first (paid placement).
const int kPromoTickerMaxItems = 4;

final promoAdsProvider =
    StateNotifierProvider<PromoAdsController, List<_PromoItem>>((ref) {
  final c = PromoAdsController(seed: List<_PromoItem>.from(_demoPromos));

  // Keep the controller's "My Ads" listener in sync with auth.
  final auth = ref.read(authControllerProvider);
  c.bindMineOwner(fb.FirebaseAuth.instance.currentUser?.uid ?? '');
  ref.listen<AuthState>(authControllerProvider, (prev, next) {
    c.bindMineOwner(fb.FirebaseAuth.instance.currentUser?.uid ?? '');
  });

  return c;
});

/// Firestore collection: `promo_ads`
///
/// Public view (Home): loads only approved (مميّز) ads.
/// My Ads view: additionally loads my own ads (any status).
///
/// This controller keeps the UI API the same as the previous mock controller,
/// but the source of truth becomes Firestore.
class PromoAdsController extends StateNotifier<List<_PromoItem>> {
  PromoAdsController({List<_PromoItem>? seed})
      : _db = FirebaseFirestore.instance,
        _storage = FirebaseStorage.instance,
        super(seed ?? const []) {
    _listenPublic();
  }
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('promo_ads');

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _publicSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _mineSub;

  // We keep two maps so removing from one query doesn't accidentally remove
  // an item that is still present in the other.
  Map<String, _PromoItem> _public = <String, _PromoItem>{};
  Map<String, _PromoItem> _mine = <String, _PromoItem>{};
  String _mineOwnerKey = '';

  int _tsToMs(dynamic v) {
    if (v == null) return 0;
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is DateTime) return v.millisecondsSinceEpoch;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  void _emitMerged() {
    final merged = <String, _PromoItem>{..._public, ..._mine};
    final list = merged.values.toList(growable: false);
    list.sort((a, b) {
      final aa = a.promoApprAtMs ?? a.promoReqAtMs ?? 0;
      final bb = b.promoApprAtMs ?? b.promoReqAtMs ?? 0;
      return bb.compareTo(aa);
    });
    state = list;
  }

  void _listenPublic() {
    _publicSub?.cancel();

    // Keep the query index-free: equality filter only; sort on the client.
    final q = _col.where('promoStatus', isEqualTo: 'approved');

    _publicSub = q.snapshots().listen(
      (snap) {
        final next = <String, _PromoItem>{};
        for (final d in snap.docs) {
          next[d.id] = _PromoItem.fromFirestore(d);
        }
        _public = next;
        _emitMerged();
      },
      onError: (e, st) {
        // Keep the seed (demo) if Firestore isn't available.
        if (kDebugMode) {
          debugPrint('[PromoAdsController] public listener error: $e');
        }
      },
    );
  }

  void _listenMine(String meKey) {
    final key = meKey.trim();
    if (key == _mineOwnerKey) return;

    _mineOwnerKey = key;
    _mineSub?.cancel();
    _mine = <String, _PromoItem>{};

    if (key.isEmpty) {
      _emitMerged();
      return;
    }

    // Also keep this query index-free (single equality filter).
    final q = _col.where('ownerUserId', isEqualTo: key);
    _mineSub = q.snapshots().listen(
      (snap) {
        final next = <String, _PromoItem>{};
        for (final d in snap.docs) {
          next[d.id] = _PromoItem.fromFirestore(d);
        }
        _mine = next;
        _emitMerged();
      },
      onError: (e, st) {
        if (kDebugMode) {
          debugPrint('[PromoAdsController] mine listener error: $e');
        }
      },
    );
  }

  @override
  void dispose() {
    _publicSub?.cancel();
    _mineSub?.cancel();
    super.dispose();
  }

  // ----------------- Write helpers -----------------

  String _contentTypeFromExt(String ext) {
    final e = ext.toLowerCase();
    if (e == 'png') return 'image/png';
    if (e == 'webp') return 'image/webp';
    if (e == 'gif') return 'image/gif';
    return 'image/jpeg';
  }

  Future<String> _uploadPromoImageIfNeeded(_PromoItem item) async {
    final raw = item.imageUrl.trim();
    if (raw.isEmpty) return raw;
    if (_isNetworkUrl(raw)) return raw;
    if (kIsWeb) return raw;

    final path = _asFilePath(raw);
    final file = File(path);
    if (!await file.exists()) return raw;

    final uid = fb.FirebaseAuth.instance.currentUser?.uid ??
        (item.ownerUserId ?? 'unknown');
    final ext = path.contains('.') ? path.split('.').last : 'jpg';
    final name =
        'img_${DateTime.now().millisecondsSinceEpoch}.${ext.isEmpty ? 'jpg' : ext}';

    final ref = _storage.ref('promo_ads/$uid/${item.id}/$name');
    await ref.putFile(
      file,
      SettableMetadata(contentType: _contentTypeFromExt(ext)),
    );
    return await ref.getDownloadURL();
  }

  Future<void> _saveToFirestore(
    _PromoItem item, {
    required bool isNew,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    final normalized = item.copyWith(
      // Ensure we always have a stable "created" timestamp.
      promoReqAtMs: item.promoReqAtMs ?? now,
    );

    final img = await _uploadPromoImageIfNeeded(normalized);
    final withImg = img == normalized.imageUrl
        ? normalized
        : normalized.copyWith(imageUrl: img);

    final data = withImg.toFirestoreJson();
    data['updatedAt'] = FieldValue.serverTimestamp();
    data['updatedAtMs'] = now;
    if (isNew) {
      data['createdAt'] = FieldValue.serverTimestamp();
      data['createdAtMs'] = now;
    }

    await _col.doc(withImg.id).set(data, SetOptions(merge: true));
  }

  // ----------------- Public API (used by UI) -----------------

  /// Bind/rebind the current user for the "My Ads" Firestore stream.
  void bindMineOwner(String ownerUserId) {
    _listenMine(ownerUserId);
  }

  Future<void> add(_PromoItem item) async {
    await _saveToFirestore(item, isNew: true);
  }

  Future<void> upsert(_PromoItem item) async {
    await _saveToFirestore(item, isNew: false);
  }

  void removeById(String id) {
    final did = id.trim();
    if (did.isEmpty) return;
    unawaited(_col.doc(did).delete());
  }

  _VipPkg? _pkgById(String? id) {
    final pid = (id ?? '').trim();
    if (pid.isEmpty) return null;
    for (final p in _kAdVipPkgs) {
      if (p.id == pid) return p;
    }
    return null;
  }

  /// Admin approves a مميّز ad request.
  void approveVip(String id) {
    final did = id.trim();
    if (did.isEmpty) return;
    final cur =
        state.firstWhere((e) => e.id == did, orElse: () => _demoPromos.first);
    final pkg = _pkgById(cur.promoPkgId) ?? _kAdVipPkgs.first;
    final now = DateTime.now().millisecondsSinceEpoch;
    final until = now + Duration(days: pkg.days).inMilliseconds;

    unawaited(
      _col.doc(did).set(
        <String, dynamic>{
          'isVip': true,
          'promoStatus': 'approved',
          'promoReqAtMs': cur.promoReqAtMs ?? now,
          'promoApprAtMs': now,
          'promoUntilMs': until,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      ),
    );
  }

  /// Admin rejects a مميّز ad request.
  void rejectVip(String id) {
    final did = id.trim();
    if (did.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    unawaited(
      _col.doc(did).set(
        <String, dynamic>{
          'isVip': false,
          'promoStatus': 'rejected',
          'promoApprAtMs': now,
          'promoUntilMs': null,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedAtMs': now,
        },
        SetOptions(merge: true),
      ),
    );
  }
}

/// A product is considered a "deal" when it has an oldPrice higher than price.
bool _isDeal(AppProduct p) {
  final oldP = p.oldPrice;
  return p.price > 0 && oldP != null && oldP > p.price;
}

double _dealPct(AppProduct p) {
  final oldP = (p.oldPrice ?? 0).toDouble();
  if (oldP <= 0) return 0.0;
  final newP = p.price.toDouble();
  return ((oldP - newP) / oldP).clamp(0.0, 0.95);
}

String _dealPctLabel(AppProduct p) => '-${(_dealPct(p) * 100).round()}%';

// --- Promo image helpers (support network + local picked images) ---
bool _isNetworkUrl(String s) {
  final t = s.trim().toLowerCase();
  return t.startsWith('http://') || t.startsWith('https://');
}

String _asFilePath(String s) {
  final t = s.trim();
  return t.startsWith('file://') ? t.substring(7) : t;
}

Widget _promoImage(
  BuildContext context,
  String url, {
  required double width,
  required double height,
  BorderRadius? radius,
  BoxFit fit = BoxFit.cover,
  IconData fallbackIcon = Icons.image_rounded,
}) {
  final cs = Theme.of(context).colorScheme;

  Widget inner;
  if (url.trim().isEmpty) {
    inner = Container(
      color: cs.primary.withAlpha(22),
      alignment: Alignment.center,
      child: Icon(fallbackIcon, color: cs.primary),
    );
  } else if (_isNetworkUrl(url)) {
    inner = Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        color: cs.primary.withAlpha(22),
        alignment: Alignment.center,
        child: Icon(fallbackIcon, color: cs.primary),
      ),
    );
  } else {
    inner = Image.file(
      File(_asFilePath(url)),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        color: cs.primary.withAlpha(22),
        alignment: Alignment.center,
        child: Icon(fallbackIcon, color: cs.primary),
      ),
    );
  }

  final box = SizedBox(width: width, height: height, child: inner);
  if (radius == null) return box;
  return ClipRRect(borderRadius: radius, child: box);
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.refreshToken, this.focusId});

  /// When set (via /home?r=...), triggers a refresh and scroll-to-top.
  final String? refreshToken;

  /// Optional product id to hint that something specific was updated.
  final String? focusId;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Future<void> _openFeatureWhatsApp(BuildContext context) async {
    final message = tikkiTr(context,
        ar: 'السلام عليكم، أريد تمييز إعلان/عرض.\nمن فضلك أرسل لك رابط الإعلان أو رقمه والمدة المطلوبة.',
        fr: "Bonjour, je veux mettre en vedette une annonce/offre.\nMerci de m'envoyer le lien ou le numéro et la durée souhaitée.",
        en: 'Hi, I want to feature an ad/offer.\nPlease send the ad link or ID and the desired duration.');
    final phone = kSupportWhatsApp.replaceAll('+', '').replaceAll(' ', '');
    final uri =
        Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tikkiTr(context,
                ar: 'تعذر فتح واتساب',
                fr: "Impossible d’ouvrir WhatsApp",
                en: 'Could not open WhatsApp'))),
      );
    }
  }

  String? _handledToken;
  final GlobalKey _focusKey = GlobalKey();
  String? _handledFocusId;

  late final int _bootAtMs;
  Timer? _bootTimer;
  bool _didWarmBootFetch = false;

  final TextEditingController _qCtl = TextEditingController();
  Timer? _debounce;

  /// null = All
  String? _selectedCategoryId;

  /// Tiny inline i18n helper used inside Home.
  ///
  /// Usage:
  /// - `_tr(ar:..., fr:..., en:...)`
  /// - `_tr(c: context, ar:..., fr:..., en:...)`
  String _tr({
    BuildContext? c,
    required String ar,
    required String fr,
    required String en,
  }) {
    final ctx = c ?? context;
    final code = Localizations.localeOf(ctx).languageCode.toLowerCase();
    if (code == 'fr') return fr;
    if (code == 'en') return en;
    return ar;
  }

  @override
  void initState() {
    super.initState();
    _bootAtMs = DateTime.now().millisecondsSinceEpoch;

    // Ensure we leave the boot loader even if the feed stream is slow to emit.
    _bootTimer?.cancel();
    _bootTimer = Timer(const Duration(milliseconds: 2600), () {
      if (!mounted) return;
      setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleExternalRefresh();
      _warmBootFetch();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _bootTimer?.cancel();
    _qCtl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.focusId != widget.focusId) {
      if (oldWidget.focusId != widget.focusId) _handledFocusId = null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleExternalRefresh(),
      );
    }
  }

  void _handleExternalRefresh() {
    final token = (widget.refreshToken ?? '').trim();
    if (token.isEmpty) return;
    if (token == _handledToken) return;
    _handledToken = token;

    _refresh(showHint: true, scrollToTop: true);
  }

  void _warmBootFetch() {
    if (_didWarmBootFetch) return;
    _didWarmBootFetch = true;

    // Mimic a first "Home tap" so the feed attaches & refreshes on cold start.
    _refresh(showHint: false, scrollToTop: false);
  }

  void _snack(String msg, [Color? bg]) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 900),
        backgroundColor: bg,
      ),
    );
  }

  void _selectCategory(String? id) {
    setState(() => _selectedCategoryId = id);
    final c = ref.read(homeScrollControllerProvider);
    if (c.hasClients) {
      c.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _refresh({
    bool showHint = false,
    bool scrollToTop = false,
  }) async {
    // Force re-fetch (stream re-subscribe)
    ref.invalidate(homeProductsFeedProvider);

    // A tiny delay gives a "real fetch" feel, even in mock mode.
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    ref.read(homeRefreshTickProvider.notifier).state++;

    if (scrollToTop) {
      final c = ref.read(homeScrollControllerProvider);
      if (c.hasClients) {
        await c.animateTo(
          0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    }

    if (showHint) {
      _snack(
        widget.focusId != null
            ? _tr(
                c: context,
                ar: 'تم تحديث المنتج ✅',
                fr: 'Produit mis à jour ✅',
                en: 'Product updated ✅',
              )
            : _tr(
                c: context,
                ar: 'تم تحديث المنتجات ✅',
                fr: 'Produits mis à jour ✅',
                en: 'Products refreshed ✅',
              ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // React to external Home-refresh taps.
    ref.listen<int>(homeRefreshTickProvider, (prev, next) {
      if (prev == next) return;
      ref.invalidate(homeProductsFeedProvider);
    });
    // Rebuild when refresh tick changes.
    ref.watch(homeRefreshTickProvider);

    // Used by various UI bits.
    final cs = Theme.of(context).colorScheme;
    final store = ref.watch(localStoreProvider);

    final s = AppStrings.of(context);
    final locale = Localizations.localeOf(context);

    // Firestore feed (A2)
    final feedAsync = ref.watch(
        homeProductsFeedProvider); // --- Boot/loading gate (Temu-style) ---
    // Keep the user on a lightweight loader until the feed emits its first value.
    final data = feedAsync.asData?.value;
    final hasData = data != null;
    final first = data ?? const <AppProduct>[];

    final bootAgeMs = DateTime.now().millisecondsSinceEpoch - _bootAtMs;
    // Grace period to avoid showing an "empty home" flicker on cold start / slow cache.
    final inBootGrace = bootAgeMs < 2400;

    final hasErrorNoData = feedAsync.hasError && !hasData;
    if (hasErrorNoData) {
      return Scaffold(
        backgroundColor: const Color(0xFFFFF7F2),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded, size: 46),
                  const SizedBox(height: 10),
                  Text(
                    _tr(
                      c: context,
                      ar: 'تعذر تحميل المنتجات',
                      fr: 'Impossible de charger les produits',
                      en: 'Failed to load products',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: () =>
                        _refresh(showHint: false, scrollToTop: false),
                    child: Text(
                      _tr(
                        c: context,
                        ar: 'إعادة المحاولة',
                        fr: 'Réessayer',
                        en: 'Retry',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final showBootLoader = !hasData ||
        (first.isEmpty &&
            (feedAsync.isLoading || inBootGrace) &&
            !feedAsync.hasError);
    if (showBootLoader) {
      return Scaffold(
        backgroundColor: const Color(0xFFFFF7F2),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/branding/tiki_lockup_nogap.png',
                  width: 200,
                  errorBuilder: (_, __, ___) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_bag_rounded,
                          color: cs.primary, size: 32),
                      const SizedBox(width: 0),
                      Text(
                        'TIKI',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          color: cs.primary,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      cs.primary.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Always show newest first.
    final all = List<AppProduct>.from(first)
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    final qNorm = maNormalizeQuery(_qCtl.text);
    final isSearching = qNorm.isNotEmpty;

    final catById = <String, CategoryNode>{
      for (final c in maCategories) c.id: c,
    };

    final subById = <String, SubCategory>{
      for (final c in maCategories)
        for (final s in withOtherSubcategory(c.sub)) s.id: s,
    };

    bool containsQ(String any) => maNormalizeQuery(any).contains(qNorm);

    bool matchQuery(AppProduct p) {
      if (qNorm.isEmpty) return true;

      // Basic fields
      if (containsQ(p.title)) return true;
      if (p.subtitle != null && containsQ(p.subtitle!)) return true;
      if (p.description != null && containsQ(p.description!)) return true;
      if (p.details != null && containsQ(p.details!)) return true;
      if (containsQ(p.wilaya)) return true;
      if (containsQ(p.moughataa)) return true;
      if (containsQ(p.neighborhood)) return true;

      // Category/subcategory labels
      final catId = resolveCategoryIdAny(p.category);
      if (catId != null) {
        final cat = catById[catId];
        if (cat != null && containsQ(cat.name.ofLocale(locale))) return true;
      }

      final subId = resolveSubCategoryIdAny(p.subCategory);
      if (subId != null) {
        final sub = subById[subId];
        if (sub != null && containsQ(sub.name.ofLocale(locale))) return true;
      }

      return false;
    }

    bool matchCategory(AppProduct p) {
      final sel = _selectedCategoryId;
      if (sel == null || sel.trim().isEmpty) return true;
      final catIdAny = resolveCategoryIdAny(p.category);
      final catId = (catIdAny == null || catIdAny.trim().isEmpty)
          ? 'other'
          : catIdAny.trim();
      return catId == sel;
    }

    final filtered = all
        .where((p) => matchCategory(p) && matchQuery(p))
        .toList(growable: false);
    final vipTopProducts = filtered
        .where((p) => PromoModeration.isVipTopActive(p))
        .toList(growable: false);
    final topIds = vipTopProducts.map((p) => p.id).toSet();

    final vipFeaturedProducts = filtered
        .where((p) => PromoModeration.isVipFeaturedActive(p))
        .where((p) => !topIds.contains(p.id))
        .toList(growable: false);
    final featuredIds = vipFeaturedProducts.map((p) => p.id).toSet();

    final vipBoostProducts = filtered
        .where((p) => PromoModeration.isVipBoostActive(p))
        .where((p) => !topIds.contains(p.id) && !featuredIds.contains(p.id))
        .toList(growable: false);

    final vipProducts = <AppProduct>[
      ...vipTopProducts,
      ...vipFeaturedProducts,
      ...vipBoostProducts,
    ];

    final restProducts = filtered
        .where((p) => !PromoModeration.isVipActive(p))
        .toList(growable: false);

    // Featured shelf under the header (Top is handled by the ticker).
    final vipFeaturedShelf =
        vipFeaturedProducts.take(10).toList(growable: false);

    // Boost shelf under Featured (third tier).
    final vipBoostShelf = vipBoostProducts.take(10).toList(growable: false);

    // "Trending" excludes مميّز (Top/Featured/Boost).
    final trending = restProducts.take(20).toList(growable: false);

    // Deals (discounts): oldPrice > price
    final deals = filtered.where(_isDeal).toList(growable: false)
      ..sort((a, b) => _dealPct(b).compareTo(_dealPct(a)));

    final dealBubbles = List<AppProduct?>.generate(
      8,
      (i) => i < deals.length ? deals[i] : null,
      growable: false,
    );

    // Most viewed (local counts). We keep it independent from the search query,
    // but it still respects the selected category.
    int viewsOf(AppProduct p) => store.getProductViewCount(p.id);
    final mvSource = all.where(matchCategory).toList(growable: false)
      ..sort((a, b) => viewsOf(b).compareTo(viewsOf(a)));
    final mvNonZero =
        mvSource.where((p) => viewsOf(p) > 0).toList(growable: false);
    final mostViewed = (mvNonZero.isEmpty ? mvSource : mvNonZero);
    final mostViewedTiles = List<AppProduct?>.generate(
      8,
      (i) => i < mostViewed.length ? mostViewed[i] : null,
      growable: false,
    );

    // Main feed: include focused item even if it is older than the first batch.
    final focusId = (widget.focusId ?? '').trim();
    final isCleanHome = !isSearching &&
        (_selectedCategoryId == null || _selectedCategoryId!.trim().isEmpty);

    final feedSource = isSearching
        ? <AppProduct>[
            ...vipTopProducts,
            ...vipFeaturedProducts,
            ...vipBoostProducts,
            ...restProducts,
          ]
        // Home feed: مميّز is handled by the ticker + Featured shelf.
        : <AppProduct>[
            ...restProducts,
          ];
    final baseFeed = (isSearching ? feedSource.take(60) : feedSource.take(30))
        .toList(growable: false);

    AppProduct? focused;
    if (focusId.isNotEmpty) {
      for (final p in all) {
        if (p.id == focusId) {
          focused = p;
          break;
        }
      }
    }

    final feed = (isCleanHome &&
            focused != null &&
            !baseFeed.any((p) => p.id == focusId))
        ? <AppProduct>[focused!, ...baseFeed]
        : baseFeed;

    final controller = ref.watch(homeScrollControllerProvider);

    // If a specific product was updated, gently scroll it into view once.
    final fid = (widget.focusId ?? '').trim();
    if (fid.isNotEmpty &&
        _handledFocusId != fid &&
        feed.any((p) => p.id == fid)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _focusKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            alignment: 0.15,
          );
          _handledFocusId = fid;
        }
      });
    }

    final selCatLabel = (_selectedCategoryId == null)
        ? null
        : (catById[_selectedCategoryId!]?.name.of(context) ??
            _selectedCategoryId!);

    final trendingTitle = (selCatLabel == null || selCatLabel.trim().isEmpty)
        ? s.trending
        : '${s.trending} • $selCatLabel';

    // مميّز ads ticker (paid promo ads).
    // Option A: target by wilaya only (or country-wide).
    final myWilayaId = ref.watch(profileProvider).profile?.wilayaId;
    final allPromoAds = ref.watch(promoAdsProvider);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final promoTickerItems = () {
      final list = allPromoAds
          .where((a) => a.isPromoApproved)
          .where((a) => a.promoUntilMs == null || a.promoUntilMs! > nowMs)
          .where((a) => _targetsUserWilaya(a.targetWilayaId, myWilayaId))
          .toList(growable: false);

      list.sort((a, b) {
        final aa = a.promoApprAtMs ?? a.promoReqAtMs ?? 0;
        final ba = b.promoApprAtMs ?? b.promoReqAtMs ?? 0;
        return ba.compareTo(aa);
      });

      return list.length <= kPromoTickerMaxItems
          ? list
          : list.sublist(0, kPromoTickerMaxItems);
    }();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refresh(showHint: false, scrollToTop: false),
          child: CustomScrollView(
            controller: controller,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyHomeHeader(
                  hint: s.searchHint,
                  showKeywords: !isSearching,
                  categories: maCategories,
                  selectedCategoryId: _selectedCategoryId,
                  onCameraTap: () {
                    final cat = (_selectedCategoryId ?? '').trim();
                    final uri = cat.isEmpty
                        ? '/search?img=1'
                        : '/search?img=1&cat=$cat';
                    context.push(uri);
                  },
                  onCategoryTap: _selectCategory,
                  promos: promoTickerItems,
                  onOpenPromo: (item) {
                    final pid = (item.productId ?? '').trim();
                    if (pid.isNotEmpty) {
                      context.push('/product/$pid');
                      return;
                    }
                    _showPromoDetails(context, item);
                  },
                  onOpenAllPromos: () => _openFeatureWhatsApp(context),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 0)),

              // مميّز sections (Temu-style shelves)
              if (!isSearching && vipTopProducts.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _tr(
                              c: context,
                              ar: 'إعلانات مميزة',
                              fr: 'Top',
                              en: 'Top',
                            ),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              _showVipTopList(context, vipTopProducts),
                          child: Text(
                            _tr(
                              c: context,
                              ar: 'عرض الكل',
                              fr: 'Tout voir',
                              en: 'See all',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 96,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      scrollDirection: Axis.horizontal,
                      itemCount: vipTopProducts.length > 10
                          ? 10
                          : vipTopProducts.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final p = vipTopProducts[i];
                        return _VipMiniCard(
                          product: p,
                          onTap: () => context.push('/product/${p.id}'),
                        );
                      },
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 6)),
              ],
              if (isSearching)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _tr(
                              c: context,
                              ar: 'نتائج البحث',
                              fr: 'Résultats',
                              en: 'Results',
                            ),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          '${filtered.length}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.70),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!isSearching && vipFeaturedShelf.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.local_fire_department_rounded,
                            size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _tr(
                              c: context,
                              ar: 'مميز',
                              fr: 'En vedette',
                              en: 'Featured',
                            ),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _showVipFeaturedList(
                              context, vipFeaturedProducts),
                          child: Text(
                            _tr(
                              c: context,
                              ar: 'عرض الكل',
                              fr: 'Tout voir',
                              en: 'See all',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 220,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      scrollDirection: Axis.horizontal,
                      itemCount: vipFeaturedShelf.length > 10
                          ? 10
                          : vipFeaturedShelf.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final p = vipFeaturedShelf[i];
                        return SizedBox(
                          width: 220,
                          child: ProductCard(
                            product: p,
                            onTap: () => context.push('/product/${p.id}'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 6)),
              ],
              if (!isSearching && vipBoostShelf.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.bolt_rounded, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _tr(
                              c: context,
                              ar: 'تعزيز',
                              fr: 'Boost',
                              en: 'Boost',
                            ),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              _showVipBoostList(context, vipBoostProducts),
                          child: Text(
                            _tr(
                              c: context,
                              ar: 'عرض الكل',
                              fr: 'Tout voir',
                              en: 'See all',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 220,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      scrollDirection: Axis.horizontal,
                      itemCount:
                          vipBoostShelf.length > 10 ? 10 : vipBoostShelf.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final p = vipBoostShelf[i];
                        return SizedBox(
                          width: 220,
                          child: ProductCard(
                            product: p,
                            onTap: () => context.push('/product/${p.id}'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 6)),
              ],
              if (!isSearching && trending.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                    child: Text(
                      trendingTitle,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              if (!isSearching && trending.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 210,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      scrollDirection: Axis.horizontal,
                      itemCount: trending.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final p = trending[i];
                        return SizedBox(
                          width: 240,
                          child: ProductCard(
                            product: p,
                            onTap: () => context.push('/product/${p.id}'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (!isSearching) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _tr(
                              c: context,
                              ar: 'تخفيضات اليوم',
                              fr: 'Promos du jour',
                              en: "Today's deals",
                            ),
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/discounts'),
                          child: Text(
                            _tr(
                              c: context,
                              ar: 'عرض الكل',
                              fr: 'Voir tout',
                              en: 'See all',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _DealBubblesRow(
                    items: dealBubbles,
                    onOpenAll: () => context.push('/discounts'),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _tr(
                              c: context,
                              ar: 'الأكثر مشاهدة',
                              fr: 'Les plus vus',
                              en: 'Most viewed',
                            ),
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.push('/most-viewed'),
                          child: Text(
                            _tr(
                              c: context,
                              ar: 'عرض الكل',
                              fr: 'Voir tout',
                              en: 'See all',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _MostViewedTilesRow(
                    items: mostViewedTiles,
                    viewsOf: viewsOf,
                    onOpenAll: () => context.push('/most-viewed'),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              if (feed.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 24, 14, 24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 44,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.50),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isSearching
                              ? _tr(
                                  c: context,
                                  ar: 'لا توجد نتائج مطابقة',
                                  fr: 'Aucun résultat',
                                  en: 'No matching results',
                                )
                              : _tr(
                                  c: context,
                                  ar: 'لا توجد منتجات في هذه الفئة',
                                  fr: 'Aucun produit dans cette catégorie',
                                  en: 'No products in this category',
                                ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isSearching
                              ? _tr(
                                  c: context,
                                  ar: 'جرّب كلمة مختلفة أو امسح البحث.',
                                  fr: 'Essayez un autre mot ou effacez.',
                                  en: 'Try a different word or clear search.',
                                )
                              : _tr(
                                  c: context,
                                  ar: 'جرّب اختيار فئة أخرى.',
                                  fr: 'Essayez une autre catégorie.',
                                  en: 'Try another category.',
                                ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.70),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, i) {
                      final p = feed[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SizedBox(
                          height: 330,
                          child: (p.id == (widget.focusId ?? '').trim())
                              ? KeyedSubtree(
                                  key: _focusKey,
                                  child: ProductCard(
                                    product: p,
                                    onTap: () =>
                                        context.push('/product/${p.id}'),
                                  ),
                                )
                              : ProductCard(
                                  product: p,
                                  onTap: () => context.push('/product/${p.id}'),
                                ),
                        ),
                      );
                    }, childCount: feed.length),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickyHomeHeader extends SliverPersistentHeaderDelegate {
  _StickyHomeHeader({
    required this.hint,
    required this.showKeywords,
    required this.categories,
    required this.selectedCategoryId,
    required this.onCameraTap,
    required this.onCategoryTap,
    required this.promos,
    required this.onOpenPromo,
    required this.onOpenAllPromos,
  });

  final String hint;
  final bool showKeywords;
  final List<CategoryNode> categories;
  final String? selectedCategoryId;
  final VoidCallback onCameraTap;
  final ValueChanged<String?> onCategoryTap;

  final List<_PromoItem> promos;
  final void Function(_PromoItem item) onOpenPromo;
  final VoidCallback onOpenAllPromos;

  // Tuned for the existing widgets' natural sizes in this project.
  static const double _searchBlock = 56; // search row
  static const double _tabsExtra = 36; // keyword tabs area
  static const double _promoBlock = 56; // ticker height + padding
  static const double _splitBlock = 78; // split banner height + padding
  static const double _guard = 16; // safety pixels to avoid tiny overflows

  @override
  double get minExtent => (_searchBlock) + _guard;

  @override
  double get maxExtent {
    final extras = (showKeywords ? _tabsExtra : 0) + _promoBlock + _splitBlock;
    return minExtent + extras;
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final bg = Theme.of(context).scaffoldBackgroundColor;

    final range = (maxExtent - minExtent);
    final t = (range <= 0.0) ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);

    // "Temu-ish" small fold while scrolling.
    final topPad = _lerp(6, 2, t);
    double _remap(double v, double a, double b) {
      final d = (b - a);
      if (d.abs() < 1e-9) return 1.0;
      return ((v - a) / d).clamp(0.0, 1.0);
    }

    final keywordFactor = showKeywords ? (1.0 - _remap(t, 0.0, 0.35)) : 0.0;
    // Keep the Ads entry visible even if there are no مميّز ads yet.
    // (This restores the old "Ads" button behavior on Home.)
    final promoFactor = 1.0 - _remap(t, 0.10, 0.70);
    final splitFactor = 1.0 - _remap(t, 0.15, 0.80);

    final promoHeight = _lerp(46, 40, t);
    final promoScale = _lerp(1.0, 0.985, t);

    final splitHeight = _lerp(68, 58, t);
    final splitScale = _lerp(1.0, 0.985, t);

    return ColoredBox(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: topPad),

          // Search (always pinned)
          slb.TikkiSearchLangBar(
            hint: hint,
            padding: EdgeInsetsDirectional.fromSTEB(
              14,
              _lerp(6, 4, t),
              14,
              _lerp(4, 2, t),
            ),
            onSearchTap: () => context.go('/search'),
            onCameraTap: onCameraTap,
          ),

          // Keywords tabs (collapse away as you scroll)
          if (showKeywords)
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: keywordFactor,
                child: Opacity(
                  opacity: keywordFactor.clamp(0.0, 1.0),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: _CategoryKeywordTabs(
                      categories: categories,
                      selectedCategoryId: selectedCategoryId,
                      onTap: onCategoryTap,
                    ),
                  ),
                ),
              ),
            ),

          // Promo ticker / Ads button (collapsible)
          ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: promoFactor.clamp(0.0, 1.0),
              child: Opacity(
                opacity: promoFactor.clamp(0.0, 1.0),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(14, 0, 14, _lerp(8, 6, t)),
                  child: Transform.scale(
                    scale: promoScale,
                    alignment: Alignment.topCenter,
                    child: _PromoTicker(
                      items: promos,
                      height: promoHeight,
                      onOpen: onOpenPromo,
                      onOpenAll: onOpenAllPromos,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Support + offers bar (collapsible)
          ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: splitFactor.clamp(0.0, 1.0),
              child: Opacity(
                opacity: splitFactor.clamp(0.0, 1.0),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      14, _lerp(2, 1, t), 14, _lerp(8, 6, t)),
                  child: Transform.scale(
                    scale: splitScale,
                    alignment: Alignment.topCenter,
                    child: _TikkiSplitBanner(height: splitHeight, collapseT: t),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyHomeHeader oldDelegate) {
    return oldDelegate.hint != hint ||
        oldDelegate.showKeywords != showKeywords ||
        oldDelegate.selectedCategoryId != selectedCategoryId ||
        oldDelegate.promos.length != promos.length;
  }
}

class _CategoryKeywordTabs extends StatelessWidget {
  const _CategoryKeywordTabs({
    required this.categories,
    required this.selectedCategoryId,
    required this.onTap,
  });

  final List<CategoryNode> categories;
  final String? selectedCategoryId;
  final ValueChanged<String?> onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final items = <_KwItem>[
      _KwItem(
        id: null,
        label: tikkiTr(context, ar: 'الكل', fr: 'Tout', en: 'All'),
      ),
      ...categories.map(
        (c) => _KwItem(id: c.id, label: c.name.of(context)),
      ),
    ];

    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = items[i];
          final selected = (item.id == null)
              ? (selectedCategoryId == null || selectedCategoryId!.isEmpty)
              : (selectedCategoryId == item.id);

          final textStyle = TextStyle(
            fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
            fontSize: 12.5,
            height: 1.0,
            color: selected
                ? cs.onSurface
                : cs.onSurface.withValues(alpha: isDark ? 0.70 : 0.60),
          );

          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => onTap(item.id),
            onLongPress: () {
              if (item.id == null) return;
              // Quick shortcut to full search results for this category.
              context.push('/search?cat=${Uri.encodeComponent(item.id!)}');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(item.label, style: textStyle),
                  const SizedBox(height: 2),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    height: 3,
                    width: selected ? 22 : 0,
                    decoration: BoxDecoration(
                      color: selected ? cs.onSurface : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _KwItem {
  final String? id;
  final String label;
  const _KwItem({required this.id, required this.label});
}

class _DealBubblesRow extends StatelessWidget {
  const _DealBubblesRow({
    required this.items,
    required this.onOpenAll,
    this.height = 92,
  });

  final List<AppProduct?> items;
  final VoidCallback onOpenAll;

  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: height,
      child: ListView.separated(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 0),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = items[i];
          final hasImg = p != null && p.imageUrl.trim().isNotEmpty;
          final badge = (p == null)
              ? tikkiTr(context, ar: 'خصم', fr: 'Promo', en: 'Deal')
              : _dealPctLabel(p);

          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onOpenAll,
            child: SizedBox(
              width: 70,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.surface,
                          border: Border.all(
                            color: cs.outlineVariant.withAlpha(140),
                          ),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 10,
                              offset: const Offset(0, 6),
                              color: Colors.black.withAlpha(isDark ? 28 : 18),
                            )
                          ],
                          image: hasImg
                              ? DecorationImage(
                                  image: NetworkImage(p!.imageUrl),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: hasImg
                            ? null
                            : Icon(
                                Icons.local_offer_rounded,
                                color: cs.primary,
                                size: 22,
                              ),
                      ),
                      PositionedDirectional(
                        bottom: -7,
                        start: 6,
                        end: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                              height: 1.0,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    p?.title ??
                        tikkiTr(context,
                            ar: 'التخفيضات', fr: 'Promos', en: 'Discounts'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                      color: cs.onSurface.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MostViewedTilesRow extends StatelessWidget {
  const _MostViewedTilesRow({
    required this.items,
    required this.onOpenAll,
    this.viewsOf,
  });

  final List<AppProduct?> items;
  final VoidCallback onOpenAll;
  final int Function(AppProduct p)? viewsOf;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 92,
      child: ListView.separated(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 0),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = items[i];
          final hasImg = p != null && p.imageUrl.trim().isNotEmpty;
          final views = (p != null && viewsOf != null) ? viewsOf!(p) : 0;

          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onOpenAll,
            child: SizedBox(
              width: 70,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: cs.surface,
                          border: Border.all(
                            color: cs.outlineVariant.withAlpha(140),
                          ),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 10,
                              offset: const Offset(0, 6),
                              color: Colors.black.withAlpha(isDark ? 28 : 18),
                            )
                          ],
                          image: hasImg
                              ? DecorationImage(
                                  image: NetworkImage(p!.imageUrl),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: hasImg
                            ? null
                            : Icon(
                                Icons.trending_up_rounded,
                                color: cs.primary,
                                size: 24,
                              ),
                      ),
                      if (views > 0)
                        PositionedDirectional(
                          bottom: -7,
                          start: 6,
                          end: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${views}',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                                height: 1.0,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    p?.title ??
                        tikkiTr(context,
                            ar: 'الأكثر مشاهدة',
                            fr: 'Les plus vus',
                            en: 'Most viewed'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                      color: cs.onSurface.withAlpha(200),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- Promo ticker (3 demo ads). Replace with Firestore later. ---

class _PromoItem {
  final String id;
  final String? productId;
  final String imageUrl;

  /// Public contact phone shown to users in the ad details screen.
  ///
  /// This is intentionally separate from [ownerUserId] (which may be an internal
  /// id) so the advertiser can choose what number to display.
  final String? contactPhone;

  /// Paid placement: shown first and labeled مميّز.
  ///
  /// NOTE: kept for backward compatibility with older demo data.
  /// In the new flow, مميّز is driven by [promoStatus].
  final bool isVip;

  /// Promo moderation status:
  /// - none: normal ad
  /// - pending: user submitted a payment reference id (awaiting review)
  /// - approved: مميّز active
  /// - rejected: rejected
  final String promoStatus;

  final String? promoPkgId;
  final String? promoTxId;
  final String? promoWalletId;
  final int? promoReqAtMs;
  final int? promoApprAtMs;
  final int? promoUntilMs;

  /// Marks ads created from this device (mock mode), so we can show extra promo info.
  final bool createdByMe;

  /// Owner user id for moderation/admin review.
  final String? ownerUserId;

  /// Targeting (Option A): a single wilaya id.
  ///
  /// - null/empty => show country-wide
  /// - otherwise => show only to users in that wilaya
  final String? targetWilayaId;

  /// Optional: opens a category search when the ad is tapped.
  /// Must match a CategoryNode id from ma_catalog.dart (e.g. 'vehicles', 'real_estate', ...).
  final String? categoryId;

  final String arTitle;
  final String frTitle;
  final String enTitle;
  final String arSubtitle;
  final String frSubtitle;
  final String enSubtitle;
  final String arBody;
  final String frBody;
  final String enBody;

  const _PromoItem({
    required this.id,
    this.productId,
    required this.imageUrl,
    this.contactPhone,
    this.isVip = false,
    this.promoStatus = 'none',
    this.promoPkgId,
    this.promoTxId,
    this.promoWalletId,
    this.promoReqAtMs,
    this.promoApprAtMs,
    this.promoUntilMs,
    this.createdByMe = false,
    this.ownerUserId,
    this.targetWilayaId,
    this.categoryId,
    required this.arTitle,
    required this.frTitle,
    required this.enTitle,
    required this.arSubtitle,
    required this.frSubtitle,
    required this.enSubtitle,
    required this.arBody,
    required this.frBody,
    required this.enBody,
  });

  static int _asMs(dynamic v) {
    if (v == null) return 0;
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    if (v is DateTime) return v.millisecondsSinceEpoch;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static String _asStr(dynamic v) {
    if (v == null) return '';
    return v.toString();
  }

  /// Firestore -> model.
  ///
  /// Supports both the new nested schema (titles/subtitles/bodies maps) and the
  /// legacy flat fields (arTitle/frTitle/enTitle...).
  factory _PromoItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};

    Map<String, dynamic> _map(dynamic v) => v is Map<String, dynamic>
        ? v
        : (v is Map ? v.map((k, vv) => MapEntry(k.toString(), vv)) : {});

    final titles = _map(m['titles']);
    final subtitles = _map(m['subtitles']);
    final bodies = _map(m['bodies']);

    String pickLang(Map<String, dynamic> src, String key) {
      final v = src[key];
      return (v == null) ? '' : v.toString();
    }

    final arTitle = pickLang(titles, 'ar').isNotEmpty
        ? pickLang(titles, 'ar')
        : _asStr(m['arTitle']);
    final frTitle = pickLang(titles, 'fr').isNotEmpty
        ? pickLang(titles, 'fr')
        : _asStr(m['frTitle']);
    final enTitle = pickLang(titles, 'en').isNotEmpty
        ? pickLang(titles, 'en')
        : _asStr(m['enTitle']);

    final arSubtitle = pickLang(subtitles, 'ar').isNotEmpty
        ? pickLang(subtitles, 'ar')
        : _asStr(m['arSubtitle']);
    final frSubtitle = pickLang(subtitles, 'fr').isNotEmpty
        ? pickLang(subtitles, 'fr')
        : _asStr(m['frSubtitle']);
    final enSubtitle = pickLang(subtitles, 'en').isNotEmpty
        ? pickLang(subtitles, 'en')
        : _asStr(m['enSubtitle']);

    final arBody = pickLang(bodies, 'ar').isNotEmpty
        ? pickLang(bodies, 'ar')
        : _asStr(m['arBody']);
    final frBody = pickLang(bodies, 'fr').isNotEmpty
        ? pickLang(bodies, 'fr')
        : _asStr(m['frBody']);
    final enBody = pickLang(bodies, 'en').isNotEmpty
        ? pickLang(bodies, 'en')
        : _asStr(m['enBody']);

    final promoStatus = _asStr(m['promoStatus']).trim().isEmpty
        ? 'none'
        : _asStr(m['promoStatus']).trim();

    // Use doc.id as the primary id.
    final id = doc.id;

    // Prefer explicit ms fields, then timestamps.
    int? msOrNull(dynamic v) {
      final ms = _asMs(v);
      return ms <= 0 ? null : ms;
    }

    final reqAt = msOrNull(m['promoReqAtMs']) ?? msOrNull(m['createdAtMs']);
    final apprAt = msOrNull(m['promoApprAtMs']);
    final until = msOrNull(m['promoUntilMs']);

    final owner = _asStr(m['ownerUserId']).trim();
    final target = _asStr(m['targetWilayaId']).trim();
    final cat = _asStr(m['categoryId']).trim();
    final productId = _asStr(m['productId']).trim();

    final isVip = (m['isVip'] == true) || promoStatus == 'approved';

    final img = _asStr(m['imageUrl']).trim();
    final contact = _asStr(m['contactPhone']).trim();

    return _PromoItem(
      id: id,
      productId: productId.isEmpty ? null : productId,
      imageUrl: img.isEmpty
          ? 'https://picsum.photos/seed/tikki_promo_${id}/120/120'
          : img,
      contactPhone: contact.isEmpty ? null : contact,
      isVip: isVip,
      promoStatus: promoStatus,
      promoPkgId: _asStr(m['promoPkgId']).trim().isEmpty
          ? null
          : _asStr(m['promoPkgId']).trim(),
      promoTxId: _asStr(m['promoTxId']).trim().isEmpty
          ? null
          : _asStr(m['promoTxId']).trim(),
      promoWalletId: _asStr(m['promoWalletId']).trim().isEmpty
          ? (_asStr(m['walletId']).trim().isEmpty
              ? null
              : _asStr(m['walletId']).trim())
          : _asStr(m['promoWalletId']).trim(),
      promoReqAtMs: reqAt,
      promoApprAtMs: apprAt,
      promoUntilMs: until,
      createdByMe: (m['createdByMe'] == true),
      ownerUserId: owner.isEmpty ? null : owner,
      targetWilayaId: target.isEmpty ? null : target,
      categoryId: cat.isEmpty ? null : cat,
      arTitle: arTitle.isEmpty ? 'إعلان' : arTitle,
      frTitle: frTitle.isEmpty ? (arTitle.isEmpty ? 'Ad' : arTitle) : frTitle,
      enTitle: enTitle.isEmpty ? (arTitle.isEmpty ? 'Ad' : arTitle) : enTitle,
      arSubtitle: arSubtitle,
      frSubtitle: frSubtitle,
      enSubtitle: enSubtitle,
      arBody: arBody,
      frBody: frBody,
      enBody: enBody,
    );
  }

  /// Model -> Firestore.
  ///
  /// Uses a compact schema with localized maps for titles/subtitles/bodies.
  Map<String, dynamic> toFirestoreJson() {
    return <String, dynamic>{
      'productId': (productId ?? '').trim(),
      'imageUrl': imageUrl.trim(),
      'contactPhone': (contactPhone ?? '').trim(),
      'isVip': isVip,
      'promoStatus': promoStatus.trim(),
      'promoPkgId': (promoPkgId ?? '').trim(),
      'promoTxId': (promoTxId ?? '').trim(),
      'promoWalletId': (promoWalletId ?? '').trim(),
      'promoReqAtMs': promoReqAtMs,
      'promoApprAtMs': promoApprAtMs,
      'promoUntilMs': promoUntilMs,
      'createdByMe': createdByMe,
      'ownerUserId': (ownerUserId ?? '').trim(),
      'targetWilayaId': (targetWilayaId ?? '').trim(),
      'categoryId': (categoryId ?? '').trim(),
      'titles': <String, String>{
        'ar': arTitle,
        'fr': frTitle,
        'en': enTitle,
      },
      'subtitles': <String, String>{
        'ar': arSubtitle,
        'fr': frSubtitle,
        'en': enSubtitle,
      },
      'bodies': <String, String>{
        'ar': arBody,
        'fr': frBody,
        'en': enBody,
      },
      // Also write legacy flat fields for backward compatibility with older builds.
      'arTitle': arTitle,
      'frTitle': frTitle,
      'enTitle': enTitle,
      'arSubtitle': arSubtitle,
      'frSubtitle': frSubtitle,
      'enSubtitle': enSubtitle,
      'arBody': arBody,
      'frBody': frBody,
      'enBody': enBody,
    };
  }

  static const Object _unset = Object();

  _PromoItem copyWith({
    String? id,
    Object? productId = _unset,
    String? imageUrl,
    Object? contactPhone = _unset,
    bool? isVip,
    String? promoStatus,
    Object? promoPkgId = _unset,
    Object? promoTxId = _unset,
    Object? promoWalletId = _unset,
    Object? promoReqAtMs = _unset,
    Object? promoApprAtMs = _unset,
    Object? promoUntilMs = _unset,
    bool? createdByMe,
    Object? ownerUserId = _unset,
    Object? targetWilayaId = _unset,
    Object? categoryId = _unset,
    String? arTitle,
    String? frTitle,
    String? enTitle,
    String? arSubtitle,
    String? frSubtitle,
    String? enSubtitle,
    String? arBody,
    String? frBody,
    String? enBody,
  }) {
    return _PromoItem(
      id: id ?? this.id,
      productId: productId == _unset ? this.productId : productId as String?,
      imageUrl: imageUrl ?? this.imageUrl,
      contactPhone:
          contactPhone == _unset ? this.contactPhone : contactPhone as String?,
      isVip: isVip ?? this.isVip,
      promoStatus: promoStatus ?? this.promoStatus,
      promoPkgId:
          promoPkgId == _unset ? this.promoPkgId : promoPkgId as String?,
      promoTxId: promoTxId == _unset ? this.promoTxId : promoTxId as String?,
      promoWalletId: promoWalletId == _unset
          ? this.promoWalletId
          : promoWalletId as String?,
      promoReqAtMs:
          promoReqAtMs == _unset ? this.promoReqAtMs : promoReqAtMs as int?,
      promoApprAtMs:
          promoApprAtMs == _unset ? this.promoApprAtMs : promoApprAtMs as int?,
      promoUntilMs:
          promoUntilMs == _unset ? this.promoUntilMs : promoUntilMs as int?,
      createdByMe: createdByMe ?? this.createdByMe,
      ownerUserId:
          ownerUserId == _unset ? this.ownerUserId : ownerUserId as String?,
      targetWilayaId: targetWilayaId == _unset
          ? this.targetWilayaId
          : targetWilayaId as String?,
      categoryId:
          categoryId == _unset ? this.categoryId : categoryId as String?,
      arTitle: arTitle ?? this.arTitle,
      frTitle: frTitle ?? this.frTitle,
      enTitle: enTitle ?? this.enTitle,
      arSubtitle: arSubtitle ?? this.arSubtitle,
      frSubtitle: frSubtitle ?? this.frSubtitle,
      enSubtitle: enSubtitle ?? this.enSubtitle,
      arBody: arBody ?? this.arBody,
      frBody: frBody ?? this.frBody,
      enBody: enBody ?? this.enBody,
    );
  }

  bool get hasCategory => (categoryId ?? '').trim().isNotEmpty;

  bool get isPromoApproved => isVip || promoStatus == 'approved';
  bool get isPromoPending => promoStatus == 'pending' && !isPromoApproved;

  String title(BuildContext c) =>
      tikkiTr(c, ar: arTitle, fr: frTitle, en: enTitle);
  String subtitle(BuildContext c) =>
      tikkiTr(c, ar: arSubtitle, fr: frSubtitle, en: enSubtitle);
  String body(BuildContext c) => tikkiTr(c, ar: arBody, fr: frBody, en: enBody);

  bool get isCountryWide => (targetWilayaId ?? '').trim().isEmpty;

  String targetLabel(BuildContext c) {
    final id = (targetWilayaId ?? '').trim();
    if (id.isEmpty) {
      return tikkiTr(c,
          ar: 'كل موريتانيا', fr: 'Toute la Mauritanie', en: 'All Mauritania');
    }
    for (final w in maWilayas) {
      if (w.id == id) return w.name.of(c);
    }
    return id;
  }

  bool get isListingPromo => (productId ?? '').trim().isNotEmpty;

  factory _PromoItem.fromProduct(AppProduct p, BuildContext context) {
    final title = p.title.trim().isEmpty ? 'مميّز' : p.title.trim();
    final price = p.price;
    final subtitle = tikkiTr(
      context,
      ar: 'مميّز المميزة • ${p.wilaya} • ${price} MRU',
      fr: 'مميّز Top • ${p.wilaya} • ${price} MRU',
      en: 'مميّز Top • ${p.wilaya} • ${price} MRU',
    );

    return _PromoItem(
      id: 'مميّزTOP_${p.id}',
      productId: p.id,
      imageUrl: p.imageUrl,
      isVip: true,
      promoStatus: 'approved',
      promoPkgId: 'top',
      promoReqAtMs: null,
      promoApprAtMs: DateTime.now()
          .subtract(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
      promoUntilMs: PromoModeration.promoUntil(p)?.millisecondsSinceEpoch,
      createdByMe: false,
      categoryId: resolveCategoryIdAny(p.category),
      arTitle: title,
      frTitle: title,
      enTitle: title,
      arSubtitle: subtitle,
      frSubtitle: subtitle,
      enSubtitle: subtitle,
      arBody: (p.description ?? p.details ?? '').trim().isEmpty
          ? title
          : (p.description ?? p.details ?? title),
      frBody: (p.description ?? p.details ?? '').trim().isEmpty
          ? title
          : (p.description ?? p.details ?? title),
      enBody: (p.description ?? p.details ?? '').trim().isEmpty
          ? title
          : (p.description ?? p.details ?? title),
    );
  }
}

const _demoPromos = <_PromoItem>[
  _PromoItem(
    id: 'AD-101',
    targetWilayaId: 'nouakchott_ouest',
    categoryId: 'electronics',
    imageUrl: 'https://picsum.photos/seed/tikki_shop1/120/120',
    arTitle: 'إعلان محل: إلكترونيات نواكشوط',
    frTitle: 'Pub boutique: Électronique Nouakchott',
    enTitle: 'Shop Ad: Electronics Nouakchott',
    arSubtitle: 'عروض على الهواتف والاكسسوارات',
    frSubtitle: 'Promos sur téléphones et accessoires',
    enSubtitle: 'Deals on phones & accessories',
    arBody:
        '''هذا مثال إعلان لمحل. لاحقًا سنربطه بـ Firebase لتحديث الصور والعناوين تلقائيًا.

نصيحة: اذكر اسم المحل، العنوان، رقم الهاتف، وساعات العمل.''',
    frBody:
        '''Ceci est un exemple d'annonce. Plus tard, on le reliera à Firebase pour mettre à jour les images et les titres automatiquement.

Astuce: ajoutez le nom du magasin, l'adresse, le téléphone et les horaires.''',
    enBody:
        '''This is a demo shop ad. Later we can load it from Firebase with live images/titles.

Tip: include shop name, address, phone and working hours.''',
  ),
  _PromoItem(
    id: 'AD-102',
    isVip: true,
    categoryId: 'fashion',
    imageUrl: 'https://picsum.photos/seed/tikki_offer/120/120',
    arTitle: 'عروض اليوم داخل تيكي',
    frTitle: 'Offres du jour surTkii',
    enTitle: "Today's deals onTkii",
    arSubtitle: 'خصومات على فئات مختارة',
    frSubtitle: 'Réductions sur des catégories sélectionnées',
    enSubtitle: 'Discounts on selected categories',
    arBody: '''مثال إعلان عروض. يمكنك لاحقًا تخصيصه حسب الولاية والفئة.

اضغط لمعرفة التفاصيل.''',
    frBody:
        '''Exemple de promotion. Vous pourrez plus tard le personnaliser par wilaya et catégorie.

Appuyez pour voir les détails.''',
    enBody: '''Demo deals promo. Later you can target by region/category.

Tap to see details.''',
  ),
  _PromoItem(
    id: 'AD-103',
    targetWilayaId: 'dakhlet_nouadhibou',
    categoryId: 'fashion',
    imageUrl: 'https://picsum.photos/seed/tikki_delivery/120/120',
    arTitle: 'إعلان محل: ملابس وأحذية',
    frTitle: 'Pub boutique: Mode',
    enTitle: 'Shop Ad: Fashion',
    arSubtitle: 'تخفيضات موسمية داخل المدينة',
    frSubtitle: 'Promotions saisonnières en ville',
    enSubtitle: 'Seasonal discounts in town',
    arBody:
        '''مثال إعلان لمحلات الملابس. لاحقًا يمكن للإعلان أن يفتح صفحة المحل أو منتجاته.

تنبيه: لا تشارك رمز OTP مع أي شخص.''',
    frBody:
        '''Exemple pour les boutiques de mode. Plus tard, la pub peut ouvrir la page du magasin ou ses produits.

Rappel: ne partagez jamais votre code OTP.''',
    enBody:
        '''Demo fashion shop ad. Later it can open the shop page or its products.

Reminder: never share your OTP code.''',
  ),
];

class _PromoTicker extends StatefulWidget {
  const _PromoTicker({
    required this.items,
    required this.onOpen,
    required this.onOpenAll,
    this.height = 40,
  });

  final List<_PromoItem> items;
  final void Function(_PromoItem item) onOpen;

  /// Opens the full ads list (مميّز pinned first) + "Add your ad".
  final VoidCallback onOpenAll;

  final double height;

  @override
  State<_PromoTicker> createState() => _PromoTickerState();
}

class _PromoTickerState extends State<_PromoTicker> {
  final PageController _ctl = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_ctl.hasClients) return;
      if (widget.items.length <= 1) return;
      final next = (_index + 1) % widget.items.length;
      _ctl.animateToPage(
        next,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (widget.items.isEmpty) {
      // Show a clickable "Ads" button so users can open the Ads screen
      // even when there are no مميّز ads yet.
      return Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onOpenAll,
          child: Container(
            height: widget.height,
            padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 8, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withAlpha(170)),
            ),
            child: Row(
              children: [
                Icon(Icons.campaign_rounded, size: 18, color: cs.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tikkiTr(context,
                            ar: 'ميّز إعلانك',
                            fr: 'Mettre en vedette',
                            en: 'Feature your ad'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tikkiTr(context,
                            ar: 'تواصل مع المشرف عبر واتساب',
                            fr: 'Contactez l\'admin sur WhatsApp',
                            en: 'Contact admin on WhatsApp'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 10.5,
                          color: cs.onSurface.withValues(
                            alpha: isDark ? 0.78 : 0.62,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 26,
                  color: cs.onSurface.withValues(alpha: isDark ? 0.72 : 0.62),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withAlpha(170)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                // Leave room for the dropdown button on the "end" side (RTL/LTR).
                padding: const EdgeInsetsDirectional.only(end: 44),
                child: PageView.builder(
                  controller: _ctl,
                  scrollDirection: Axis.vertical,
                  itemCount: widget.items.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final item = widget.items[i];
                    return InkWell(
                      onTap: () => widget.onOpen(item),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 10,
                          end: 10,
                        ),
                        child: Row(
                          children: [
                            if (item.isPromoApproved) ...[
                              Icon(Icons.star_rounded,
                                  size: 16, color: cs.primary),
                              const SizedBox(width: 6),
                            ],
                            _promoImage(
                              context,
                              item.imageUrl,
                              width: 30,
                              height: 30,
                              radius: BorderRadius.circular(10),
                              fallbackIcon: item.isPromoApproved
                                  ? Icons.star_rounded
                                  : Icons.storefront_rounded,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title(context),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.subtitle(context),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10.5,
                                      color: cs.onSurface.withValues(
                                        alpha: isDark ? 0.78 : 0.62,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            PositionedDirectional(
              end: 0,
              top: 0,
              bottom: 0,
              child: InkWell(
                onTap: widget.onOpenAll,
                child: Container(
                  width: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.surface,
                    border: BorderDirectional(
                      start: BorderSide(
                        color: cs.outlineVariant.withAlpha(170),
                      ),
                    ),
                  ),
                  child: Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 26,
                    color: cs.onSurface.withValues(alpha: isDark ? 0.72 : 0.62),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showPromoDetails(BuildContext context, _PromoItem item) async {
  final pid = (item.productId ?? '').trim();
  if (pid.isNotEmpty) {
    context.push('/product/$pid');
    return;
  }
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _promoImage(
                    ctx,
                    item.imageUrl,
                    width: 64,
                    height: 64,
                    radius: BorderRadius.circular(14),
                    fallbackIcon: Icons.campaign_rounded,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title(ctx),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle(ctx),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface
                                .withValues(alpha: isDark ? 0.78 : 0.62),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.place_rounded,
                                size: 15,
                                color: cs.onSurface.withValues(alpha: 0.55)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item.targetLabel(ctx),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: cs.onSurface.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (item.createdByMe || item.isPromoPending) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.id,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.48),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                item.body(ctx),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                  color: cs.onSurface.withValues(alpha: isDark ? 0.86 : 0.78),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.check_rounded),
                      label:
                          Text(tikkiTr(ctx, ar: 'حسنًا', fr: 'OK', en: 'OK')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Future<void>.delayed(const Duration(milliseconds: 140),
                            () {
                          _showPromoAdFullDetails(context, item);
                        });
                      },
                      icon: const Icon(Icons.info_outline_rounded),
                      label: Text(
                        tikkiTr(ctx,
                            ar: 'تفاصيل', fr: 'Détails', en: 'Details'),
                      ),
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
}

Future<void> _showPromoAdFullDetails(
    BuildContext context, _PromoItem item) async {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final phoneRaw = (item.contactPhone ?? item.ownerUserId ?? '').trim();
  final hasPhone = phoneRaw.isNotEmpty;

  String digitsOnly(String input) {
    var d = input.replaceAll(RegExp(r'[^0-9]'), '');
    // If user entered a local 8-digit number, assume Mauritania country code 222.
    if (d.length == 8 && !d.startsWith('222')) d = '222$d';
    return d;
  }

  Future<void> tryLaunch(Uri uri) async {
    try {
      final ok = await canLaunchUrl(uri);
      if (!ok) throw Exception('cannot_launch');
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tikkiTr(context,
              ar: 'تعذّر فتح الرابط على هذا الجهاز',
              fr: "Impossible d'ouvrir le lien",
              en: 'Could not open link')),
          duration: const Duration(milliseconds: 950),
        ),
      );
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.55,
        maxChildSize: 0.98,
        builder: (ctx, scrollCtrl) {
          return SafeArea(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tikkiTr(ctx,
                            ar: 'تفاصيل الإعلان',
                            fr: "Détails de la pub",
                            en: 'Ad details'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close_rounded),
                      tooltip:
                          tikkiTr(ctx, ar: 'إغلاق', fr: 'Fermer', en: 'Close'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Large preview
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(
                      item.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: cs.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(Icons.campaign_rounded,
                            size: 42,
                            color: cs.onSurface.withValues(alpha: 0.55)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  item.title(ctx),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle(ctx),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface.withValues(alpha: isDark ? 0.78 : 0.62),
                  ),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Icon(Icons.place_rounded,
                        size: 16, color: cs.onSurface.withValues(alpha: 0.55)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.targetLabel(ctx),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface.withValues(alpha: 0.58),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest
                        .withValues(alpha: isDark ? 0.55 : 0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant.withAlpha(160)),
                  ),
                  child: Text(
                    item.body(ctx),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color:
                          cs.onSurface.withValues(alpha: isDark ? 0.88 : 0.82),
                    ),
                  ),
                ),

                const SizedBox(height: 14),
                Text(
                  tikkiTr(ctx, ar: 'التواصل', fr: 'Contact', en: 'Contact'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),

                if (!hasPhone)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest
                          .withValues(alpha: isDark ? 0.48 : 0.65),
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: cs.outlineVariant.withAlpha(160)),
                    ),
                    child: Text(
                      tikkiTr(ctx,
                          ar: 'لا يوجد رقم تواصل لهذا الإعلان حالياً.',
                          fr: "Aucun numéro de contact pour cette pub.",
                          en: 'No contact number for this ad.'),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color:
                            cs.onSurface.withValues(alpha: isDark ? 0.78 : 0.7),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: cs.outlineVariant.withAlpha(170)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.phone_rounded,
                                size: 18,
                                color: cs.onSurface.withValues(alpha: 0.65)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                phoneRaw,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: tikkiTr(ctx,
                                  ar: 'نسخ', fr: 'Copier', en: 'Copy'),
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: phoneRaw));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(tikkiTr(context,
                                        ar: 'تم النسخ',
                                        fr: 'Copié',
                                        en: 'Copied')),
                                    duration: const Duration(milliseconds: 750),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  final uri = Uri(
                                    scheme: 'tel',
                                    path: phoneRaw,
                                  );
                                  tryLaunch(uri);
                                },
                                icon: const Icon(Icons.call_rounded),
                                label: Text(tikkiTr(ctx,
                                    ar: 'اتصال', fr: 'Appeler', en: 'Call')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  final d = digitsOnly(phoneRaw);
                                  final uri = Uri.parse('https://wa.me/$d');
                                  tryLaunch(uri);
                                },
                                icon: const Icon(Icons.chat_rounded),
                                label: Text(tikkiTr(ctx,
                                    ar: 'واتساب',
                                    fr: 'WhatsApp',
                                    en: 'WhatsApp')),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          tikkiTr(ctx,
                              ar: 'تلميح: إن كان الرقم محلياً أضفنا +222 تلقائياً لواتساب.',
                              fr: "Astuce : si le numéro est local, +222 est ajouté pour WhatsApp.",
                              en: 'Tip: For local numbers, +222 is added for WhatsApp.'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            height: 1.25,
                            color: cs.onSurface
                                .withValues(alpha: isDark ? 0.6 : 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 14),
                if (item.hasCategory)
                  OutlinedButton.icon(
                    onPressed: () {
                      final cat = Uri.encodeComponent(item.categoryId!.trim());
                      Navigator.of(ctx).pop();
                      context.push('/search?cat=$cat');
                    },
                    icon: const Icon(Icons.category_outlined),
                    label: Text(tikkiTr(ctx,
                        ar: 'استكشاف الفئة',
                        fr: 'Explorer la catégorie',
                        en: 'Explore category')),
                  ),

                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(tikkiTr(ctx, ar: 'تم', fr: 'OK', en: 'Done')),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> _showPromoList(
  BuildContext context,
  List<_PromoItem> items,
  WidgetRef _,
) async {
  // Option A: promos are derived from مميّز Top listings.
  // Try to resolve promo items back to products; fallback to مميّز Top in mock mode.
  final byId = <String, dynamic>{
    for (final p in const <AppProduct>[]) (p.id ?? '').toString(): p,
  };

  final resolved = <dynamic>[];
  for (final it in items) {
    final pid = (it.productId ?? '').trim();
    if (pid.isEmpty) continue;
    final p = byId[pid];
    if (p != null) resolved.add(p);
  }

  final products = resolved.isNotEmpty
      ? resolved
      : const <AppProduct>[]
          .where((p) => PromoModeration.isVipTopActive(p))
          .toList(growable: false);

  await _showVipTopList(context, products);
}

Future<void> _showVipTopList(
  BuildContext context,
  List<dynamic> products,
) async {
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder: (_) => _VipTopListScreen(products: products),
    ),
  );
}

Future<void> _showVipFeaturedList(
  BuildContext context,
  List<dynamic> products,
) async {
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder: (_) => _VipFeaturedListScreen(products: products),
    ),
  );
}

Future<void> _showVipBoostList(
  BuildContext context,
  List<dynamic> products,
) async {
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder: (_) => _VipBoostListScreen(products: products),
    ),
  );
}

class _VipFeaturedListScreen extends StatelessWidget {
  const _VipFeaturedListScreen({required this.products});

  final List<dynamic> products;

  String _tr(BuildContext context,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'ar') return ar;
    if (code == 'fr') return fr;
    return en;
  }

  @override
  Widget build(BuildContext context) {
    final list = products.toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr(context, ar: 'مميز', fr: 'En vedette', en: 'Featured'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: list.isEmpty
            ? Center(
                child: Text(
                  _tr(
                    context,
                    ar: 'لا توجد عناصر مميزة حالياً',
                    fr: "Aucun élément en vedette",
                    en: 'No featured items right now',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final p = list[i];
                  final id = (p.id ?? '').toString();
                  return ProductCard(
                    product: p,
                    variant: ProductCardVariant.feed,
                    onTap: () {
                      if (id.isEmpty) return;
                      ctx.push('/product/$id');
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _VipBoostListScreen extends StatelessWidget {
  const _VipBoostListScreen({required this.products});

  final List<dynamic> products;

  String _tr(BuildContext context,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'ar') return ar;
    if (code == 'fr') return fr;
    return en;
  }

  @override
  Widget build(BuildContext context) {
    final list = products.toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr(context, ar: 'تعزيز', fr: 'Boost', en: 'Boost'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: list.isEmpty
            ? Center(
                child: Text(
                  _tr(
                    context,
                    ar: 'لا توجد عناصر تعزيز حالياً',
                    fr: "Aucun boost pour l'instant",
                    en: 'No boost items right now',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final p = list[i];
                  final id = (p.id ?? '').toString();
                  return ProductCard(
                    product: p,
                    variant: ProductCardVariant.feed,
                    onTap: () {
                      if (id.isEmpty) return;
                      ctx.push('/product/$id');
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _VipTopListScreen extends StatelessWidget {
  const _VipTopListScreen({required this.products});

  final List<dynamic> products;

  String _tr(BuildContext context,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'ar') return ar;
    if (code == 'fr') return fr;
    return en;
  }

  @override
  Widget build(BuildContext context) {
    final list = products.toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _tr(context, ar: 'إعلانات مميزة', fr: 'Top', en: 'مميّز Top'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: list.isEmpty
            ? Center(
                child: Text(
                  _tr(
                    context,
                    ar: 'لا توجد عناصر مميّز حالياً',
                    fr: "Aucun مميّز pour l'instant",
                    en: 'No مميّز items right now',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final p = list[i];
                  final id = (p.id ?? '').toString();
                  return ProductCard(
                    product: p,
                    variant: ProductCardVariant.feed,
                    onTap: () {
                      if (id.isEmpty) return;
                      ctx.push('/product/$id');
                    },
                  );
                },
              ),
      ),
    );
  }
}

Future<void> _showCreatePromoSheet(BuildContext context, WidgetRef ref) async {
  final uid = fb.FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    final goLogin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tikkiTr(ctx,
            ar: 'تسجيل الدخول مطلوب',
            fr: 'Connexion requise',
            en: 'Login required')),
        content: Text(tikkiTr(ctx,
            ar: 'لإضافة إعلان، قم بتسجيل الدخول أولاً.',
            fr: 'Pour ajouter une pub, connectez-vous d\'abord.',
            en: 'To add an ad, please sign in first.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tikkiTr(ctx, ar: 'إلغاء', fr: 'Annuler', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tikkiTr(ctx,
                ar: 'تسجيل الدخول', fr: 'Se connecter', en: 'Sign in')),
          ),
        ],
      ),
    );

    if (goLogin == true && context.mounted) {
      final next = Uri.encodeComponent('/promo-ads?mine=1');
      context.push('/auth?next=$next');
    }
    return;
  }

  final created =
      await Navigator.of(context, rootNavigator: true).push<_PromoItem?>(
    MaterialPageRoute(
      builder: (_) => _CreatePromoScreen(
        ownerUserId: uid,
        mineOnly: true,
      ),
    ),
  );

  if (created == null) return;

  try {
    await ref.read(promoAdsProvider.notifier).add(created);
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[promo_ads] create error: $e');
    }
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(
      SnackBar(
        content: Text(
          tikkiTr(
            context,
            ar: 'تعذّر حفظ الإعلان. راجع صلاحيات Firestore/Storage ثم حاول مرة أخرى.',
            fr: 'Impossible d\'enregistrer la pub. Vérifiez les règles Firestore/Storage.',
            en: 'Could not save the ad. Check Firestore/Storage rules.',
          ),
        ),
      ),
    );
    return;
  }

  // In-app receipt/notice for creating the ad (and مميّز request if chosen).
  final nCtrl = ref.read(notificationsControllerProvider.notifier);
  if (created.isPromoPending) {
    nCtrl.pushText(
      id: 'vip_promo_${created.id}_request',
      type: AppNotificationType.sales,
      arTitle: 'تم استلام طلب مميّز للإعلان',
      frTitle: 'Demande مميّز reçue (pub)',
      enTitle: 'مميّز request received (ad)',
      arBody:
          'طلب مميّز لإعلانك قيد المراجعة. رقم الدفع: ${created.promoTxId ?? ''}.',
      frBody:
          'Votre demande مميّز est en cours de vérification. Transaction: ${created.promoTxId ?? ''}.',
      enBody:
          'Your مميّز request is under review. Transaction: ${created.promoTxId ?? ''}.',
      targetRoute: '/promo-ads?mine=1',
    );
  } else {
    nCtrl.pushText(
      id: 'promo_${created.id}_created',
      type: AppNotificationType.system,
      arTitle: 'تمت إضافة إعلان جديد',
      frTitle: 'Nouvelle publicité ajoutée',
      enTitle: 'New ad created',
      arBody: 'تم نشر إعلانك بنجاح داخل قسم الإعلانات.',
      frBody: 'Votre publicité a été ajoutée avec succès.',
      enBody: 'Your ad has been created successfully.',
      targetRoute: '/promo-ads?mine=1',
    );
  }

  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(
        tikkiTr(context,
            ar: 'تمت إضافة الإعلان ✅', fr: 'Pub ajoutée ✅', en: 'Ad added ✅'),
      ),
      duration: const Duration(milliseconds: 950),
    ),
  );
}

class PromoAdsScreen extends StatelessWidget {
  const PromoAdsScreen({super.key, this.mineOnly = false});

  /// Kept for backward compatibility (old deep links like /promo-ads?mine=1).
  final bool mineOnly;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(tikkiTr(context,
            ar: 'ميّز إعلانك', fr: 'Mettre en vedette', en: 'Feature your ad')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant.withAlpha(140)),
              ),
              child: Text(
                tikkiTr(context,
                    ar: 'لتمييز إعلانك أو عرضك، تواصل مع المشرف عبر واتساب.\nأرسل رابط الإعلان أو رقمه والمدة المطلوبة.',
                    fr: "Pour mettre en vedette votre annonce/offre, contactez l'admin sur WhatsApp.\nEnvoyez le lien ou le numéro et la durée souhaitée.",
                    en: 'To feature your ad/offer, contact admin on WhatsApp.\nSend the ad link or ID and the desired duration.'),
                style:
                    TextStyle(height: 1.35, color: cs.onSurface.withAlpha(220)),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () async {
                final message = tikkiTr(context,
                    ar: 'السلام عليكم، أريد تمييز إعلان/عرض.\nمن فضلك أرسل لك رابط الإعلان أو رقمه والمدة المطلوبة.',
                    fr: 'Bonjour, je veux mettre en vedette une annonce/offre.\nMerci de m\'envoyer le lien ou le numéro et la durée souhaitée.',
                    en: 'Hi, I want to feature an ad/offer.\nPlease send the ad link or ID and the desired duration.');
                final phone =
                    kSupportWhatsApp.replaceAll('+', '').replaceAll(' ', '');
                final uri = Uri.parse(
                    'https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.support_agent_rounded),
              label: Text(tikkiTr(context,
                  ar: 'تواصل عبر واتساب', fr: 'WhatsApp', en: 'WhatsApp')),
            ),
          ],
        ),
      ),
    );
  }
}

class _VipPkg {
  final String id;
  final int days;
  final int priceMru;
  const _VipPkg({required this.id, required this.days, required this.priceMru});

  String label(BuildContext c) {
    if (days == 1) {
      return tikkiTr(c,
          ar: 'مميّز لمدة يوم', fr: 'مميّز 1 jour', en: 'مميّز for 1 day');
    }
    if (days == 7) {
      return tikkiTr(c,
          ar: 'مميّز لمدة أسبوع',
          fr: 'مميّز 1 semaine',
          en: 'مميّز for 1 week');
    }
    return tikkiTr(c,
        ar: 'مميّز لمدة $days أيام',
        fr: 'مميّز $days jours',
        en: 'مميّز for $days days');
  }
}

final List<_VipPkg> _kAdVipPkgs = [
  const _VipPkg(id: 'vip_1d', days: 1, priceMru: 500),
  const _VipPkg(id: 'vip_3d', days: 3, priceMru: 1000),
  const _VipPkg(id: 'vip_7d', days: 7, priceMru: 2000),
  const _VipPkg(id: 'vip_30d', days: 30, priceMru: 7000),
];

String _vipPkgIdForDays(int days) => 'vip_${days}d';

int _vipDaysFromPkgId(String? id) {
  final s = (id ?? '').trim().toLowerCase();
  if (s.isEmpty) return 0;
  // expected: vip_7d
  final parts = s.split('_');
  if (parts.length < 2) return 0;
  final d = parts.last;
  final numStr = d.endsWith('d') ? d.substring(0, d.length - 1) : d;
  return int.tryParse(numStr) ?? 0;
}

List<_VipPkg> _vipPkgsFromPlan(PromoAdsVipPlan? plan) {
  final p = plan;
  if (p == null) return const <_VipPkg>[];
  if (!p.active) return const <_VipPkg>[];
  if (p.durations.isEmpty) return const <_VipPkg>[];

  return p.durations
      .map(
        (d) => _VipPkg(
          id: _vipPkgIdForDays(d.days),
          days: d.days,
          priceMru: d.priceMru,
        ),
      )
      .toList(growable: false);
}

enum _AdReachMode { single, multi, country }

bool _isCountryWideTarget(String? wilayaId) {
  return (wilayaId ?? '').trim().isEmpty;
}

/// Parses a target string into wilaya ids.
/// - '' => []
/// - 'id' => ['id']
/// - 'id1,id2' => ['id1','id2']
List<String> _targetWilayaIds(String? target) {
  final t = (target ?? '').trim();
  if (t.isEmpty) return const <String>[];
  final parts = t.split(',');
  final out = <String>[];
  for (final p in parts) {
    final v = p.trim();
    if (v.isNotEmpty) out.add(v);
  }
  return out;
}

int _targetWilayaCount(String? target) {
  final ids = _targetWilayaIds(target);
  return ids.isEmpty ? 0 : ids.toSet().length;
}

/// Returns true if the ad should be shown for this user wilaya.
bool _targetsUserWilaya(String? target, String? myWilayaId) {
  final t = (target ?? '').trim();
  if (t.isEmpty) return true; // country-wide
  final mw = (myWilayaId ?? '').trim();
  if (mw.isEmpty) return false;
  if (!t.contains(',')) return t == mw;
  for (final id in _targetWilayaIds(t)) {
    if (id == mw) return true;
  }
  return false;
}

double _multiWilayaCap(
    int countryWideMultiplier, double multiWilayaCapMultiplier) {
  final cw =
      countryWideMultiplier <= 0 ? 1.0 : countryWideMultiplier.toDouble();
  var cap = multiWilayaCapMultiplier <= 0 ? cw : multiWilayaCapMultiplier;
  if (cap > cw) cap = cw;
  if (cap < 1.0) cap = 1.0;
  return cap;
}

/// Multi-wilaya pricing: each additional wilaya adds a configurable percent of the base price.
/// The final multiplier never exceeds the configured cap and never exceeds the country-wide multiplier.
double _multiWilayaMultiplier(
  int count, {
  required double extraPercentPerWilaya,
  required double capMultiplier,
  required int countryWideMultiplier,
}) {
  if (count <= 1) return 1.0;
  final pct = extraPercentPerWilaya < 0 ? 0.0 : extraPercentPerWilaya;
  final base = 1.0 + (pct * (count - 1));
  final cap = _multiWilayaCap(countryWideMultiplier, capMultiplier);
  return base > cap ? cap : base;
}

int _vipPriceForTarget(
  _VipPkg pkg,
  String? target, {
  required int countryWideMultiplier,
  required double extraPercentPerWilaya,
  required double multiWilayaCapMultiplier,
}) {
  final t = (target ?? '').trim();
  final cwMult = countryWideMultiplier <= 0 ? 1 : countryWideMultiplier;
  final maxPrice = pkg.priceMru * cwMult;

  if (t.isEmpty) return maxPrice;
  final count = _targetWilayaCount(t);
  if (count <= 1) return pkg.priceMru;

  final m = _multiWilayaMultiplier(
    count,
    extraPercentPerWilaya: extraPercentPerWilaya,
    capMultiplier: multiWilayaCapMultiplier,
    countryWideMultiplier: cwMult,
  );

  final price = (pkg.priceMru * m).round();
  return price > maxPrice ? maxPrice : price;
}

class _CreatePromoScreen extends ConsumerStatefulWidget {
  const _CreatePromoScreen({
    this.initial,
    this.forceVip = false,
    this.defaultWilayaId,
    this.ownerUserId,
    this.mineOnly = false,
  });

  /// When provided, the screen works in edit mode and returns an updated item.
  final _PromoItem? initial;

  /// When true, pre-opens the مميّز section (used from the manage menu).
  final bool forceVip;

  /// Default targeting for new ads (usually the user's profile wilaya).
  final String? defaultWilayaId;

  /// Owner id for new ads (usually the signed-in user id).
  final String? ownerUserId;

  /// True when opened from "My ads" context (hides the public prompt).
  final bool mineOnly;

  @override
  ConsumerState<_CreatePromoScreen> createState() => _CreatePromoScreenState();
}

class _CreatePromoScreenState extends ConsumerState<_CreatePromoScreen> {
  final titleCtrl = TextEditingController();
  final subCtrl = TextEditingController();
  final bodyCtrl = TextEditingController();
  final contactCtrl = TextEditingController();
  final imgCtrl = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  String? _pickedImagePath;

  // Targeting:
  // - '' => all Mauritania
  // - 'wilaya_id' => one wilaya
  // - 'id1,id2,...' => multiple wilayas (comma-separated)
  String _targetWilayaId = '';

  _AdReachMode _reachMode = _AdReachMode.single;
  final Set<String> _multiWilayaIds = <String>{};

  String? selectedCat;
  bool wantsVip = false;
  _VipPkg? selectedVipPkg;
  String? _selectedWalletId;
  final txCtrl = TextEditingController();

  void _syncReachFromTarget() {
    final t = _targetWilayaId.trim();
    _multiWilayaIds.clear();
    if (t.isEmpty) {
      _reachMode = _AdReachMode.country;
      return;
    }
    if (t.contains(',')) {
      _reachMode = _AdReachMode.multi;
      _multiWilayaIds.addAll(_targetWilayaIds(t));
      _applyMultiTarget();
      return;
    }
    _reachMode = _AdReachMode.single;
  }

  void _applyMultiTarget() {
    final ids = _multiWilayaIds.toList()..sort();
    _targetWilayaId = ids.join(',');
  }

  void _switchReach(_AdReachMode mode) {
    if (_reachMode == mode) return;
    setState(() {
      _reachMode = mode;

      if (mode == _AdReachMode.country) {
        _multiWilayaIds.clear();
        _targetWilayaId = '';
        return;
      }

      if (mode == _AdReachMode.single) {
        // Keep a sensible single wilaya when coming from multi/country.
        String candidate = _targetWilayaId.trim();
        if (candidate.contains(',')) {
          final ids = _targetWilayaIds(candidate);
          candidate = ids.isNotEmpty ? ids.first : '';
        }
        if (candidate.isEmpty) {
          candidate = (widget.defaultWilayaId ?? '').trim();
        }
        _multiWilayaIds.clear();
        _targetWilayaId = candidate;
        return;
      }

      // multi
      final current = _targetWilayaId.trim();
      if (current.isNotEmpty && !current.contains(',')) {
        _multiWilayaIds.add(current);
      } else if (current.contains(',')) {
        _multiWilayaIds.addAll(_targetWilayaIds(current));
      }

      final d = (widget.defaultWilayaId ?? '').trim();
      if (_multiWilayaIds.isEmpty && d.isNotEmpty) {
        _multiWilayaIds.add(d);
      }
      _applyMultiTarget();
    });
  }

  Future<void> _openMultiWilayaPicker() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final initial = Set<String>.from(_multiWilayaIds);
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final searchCtrl = TextEditingController();
        final selected = Set<String>.from(initial);

        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final q = searchCtrl.text.trim().toLowerCase();
            final list = maWilayas.where((w) {
              if (q.isEmpty) return true;
              final n = w.name.of(ctx).toLowerCase();
              return n.contains(q) || w.id.toLowerCase().contains(q);
            }).toList(growable: false);

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 14,
                  right: 14,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
                  top: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tikkiTr(ctx,
                                ar: 'اختر الولايات',
                                fr: 'Choisir des wilayas',
                                en: 'Choose wilayas'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setSheet(() => selected.clear()),
                          child: Text(tikkiTr(ctx,
                              ar: 'مسح', fr: 'Vider', en: 'Clear')),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: () {
                            setSheet(() {
                              selected
                                ..clear()
                                ..addAll(maWilayas.map((w) => w.id));
                            });
                          },
                          child: Text(tikkiTr(ctx,
                              ar: 'تحديد الكل', fr: 'Tout', en: 'All')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: searchCtrl,
                      onChanged: (_) => setSheet(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: tikkiTr(ctx,
                            ar: 'ابحث عن ولاية',
                            fr: 'Rechercher une wilaya',
                            en: 'Search a wilaya'),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: cs.outlineVariant.withAlpha(160)),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: list.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: cs.outlineVariant
                                .withValues(alpha: isDark ? 0.35 : 0.45),
                          ),
                          itemBuilder: (_, i) {
                            final w = list[i];
                            final checked = selected.contains(w.id);
                            return CheckboxListTile(
                              value: checked,
                              onChanged: (v) {
                                setSheet(() {
                                  if (v == true) {
                                    selected.add(w.id);
                                  } else {
                                    selected.remove(w.id);
                                  }
                                });
                              },
                              title: Text(w.name.of(ctx),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(null),
                            child: Text(tikkiTr(ctx,
                                ar: 'إلغاء', fr: 'Annuler', en: 'Cancel')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(ctx)
                                .pop(Set<String>.from(selected)),
                            child: Text(
                                tikkiTr(ctx, ar: 'تم', fr: 'OK', en: 'Done')),
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

    if (!mounted) return;
    if (result == null) return;

    setState(() {
      _reachMode = _AdReachMode.multi;
      _multiWilayaIds
        ..clear()
        ..addAll(result);
      _applyMultiTarget();
    });
  }

  @override
  void initState() {
    super.initState();

    final i = widget.initial;
    if (i != null) {
      _targetWilayaId = (i.targetWilayaId ?? '').trim();
      _syncReachFromTarget();
      titleCtrl.text = i.arTitle;
      subCtrl.text = i.arSubtitle;
      bodyCtrl.text = i.arBody;
      contactCtrl.text =
          (i.contactPhone ?? i.ownerUserId ?? widget.ownerUserId ?? '').trim();
      selectedCat = i.categoryId;

      final u = i.imageUrl.trim();
      if (u.isNotEmpty) {
        if (_isNetworkUrl(u)) {
          imgCtrl.text = u;
        } else {
          _pickedImagePath = _asFilePath(u);
        }
      }

      final vipWanted =
          widget.forceVip || i.isPromoPending || i.isPromoApproved;
      wantsVip = vipWanted;
      if (vipWanted) {
        final pid = (i.promoPkgId ?? '').trim();
        if (pid.isNotEmpty) {
          selectedVipPkg = _kAdVipPkgs.firstWhere(
            (p) => p.id == pid,
            orElse: () => _kAdVipPkgs.first,
          );
        }
        txCtrl.text = i.promoTxId ?? '';
        final wid = (i.promoWalletId ?? '').trim();
        _selectedWalletId = wid.isEmpty ? null : wid;
      }
      return;
    }

    _targetWilayaId = (widget.defaultWilayaId ?? '').trim();
    _syncReachFromTarget();

    // Prefill contact phone from account (mock mode uses ownerUserId as phone).
    contactCtrl.text =
        (fb.FirebaseAuth.instance.currentUser?.phoneNumber ?? '').trim();

    // مميّز is optional: you can create a normal ad, then upgrade to مميّز later.
    wantsVip = widget.forceVip;
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    subCtrl.dispose();
    bodyCtrl.dispose();
    contactCtrl.dispose();
    imgCtrl.dispose();
    txCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 950)),
    );
  }

  Future<void> _pickAdImage(ImageSource source) async {
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Reduce size a bit to keep the UI snappy in mock mode.
      final x = await _picker.pickImage(
        source: source,
        imageQuality: 78,
        maxWidth: 1400,
      );
      if (x == null) return;
      if (!mounted) return;
      setState(() => _pickedImagePath = x.path);
    } catch (_) {
      if (!mounted) return;
      _toast(
        tikkiTr(context,
            ar: 'تعذّر اختيار الصورة',
            fr: "Impossible de choisir l'image",
            en: 'Could not pick image'),
      );
    }
  }

  Future<void> _safePop([_PromoItem? result]) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  void _clearPickedImage() {
    setState(() => _pickedImagePath = null);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isEdit = widget.initial != null;
    // When a مميّز request is pending, prevent editing the مميّز request fields.
    final vipLocked = widget.initial?.isPromoPending ?? false;

    final vipPlan = ref.watch(promoAdsVipPlanProvider).asData?.value;
    final wallets = ref.watch(paymentWalletsProvider).asData?.value ??
        const <PaymentWallet>[];

    final adVipPkgs = _vipPkgsFromPlan(vipPlan);
    final vipOffersAvailable = adVipPkgs.isNotEmpty;
    final countryMult = vipPlan?.countryWideMultiplier ?? 2;
    final extraPct = vipPlan?.multiWilayaExtraPercent ?? 0.20;
    final capMult = vipPlan?.multiWilayaMaxMultiplier ?? countryMult.toDouble();
    final multiCap = _multiWilayaCap(countryMult, capMult);
    final extraPctLabel = (extraPct * 100).round();
    final multiCapLabel = (multiCap - multiCap.roundToDouble()).abs() < 0.0001
        ? multiCap.toInt().toString()
        : multiCap.toStringAsFixed(1);

    // If admin removed مميّز offers, force-disable مميّز to avoid showing hardcoded prices.
    if (wantsVip && !vipOffersAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          wantsVip = false;
          selectedVipPkg = null;
          _selectedWalletId = null;
          txCtrl.clear();
        });
      });
    }

    // Keep selected package in sync with admin plan.
    if (wantsVip && selectedVipPkg != null && adVipPkgs.isNotEmpty) {
      final sid = selectedVipPkg!.id;
      final updatedPkg = adVipPkgs.firstWhere(
        (p) => p.id == sid,
        orElse: () => selectedVipPkg!,
      );
      if (updatedPkg.priceMru != selectedVipPkg!.priceMru ||
          updatedPkg.days != selectedVipPkg!.days) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => selectedVipPkg = updatedPkg);
        });
      }
    }

    // Default wallet (when enabled).
    if (wantsVip && wallets.isNotEmpty) {
      final current = (_selectedWalletId ?? '').trim();
      final w = wallets.firstWhere(
        (x) => x.id == current,
        orElse: () => wallets.first,
      );
      if (current.isEmpty || current != w.id) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _selectedWalletId = w.id);
        });
      }
    }

    final langCode = Localizations.localeOf(context).languageCode;
    final selectedWallet = wallets.isEmpty
        ? null
        : wallets.firstWhere(
            (w) => w.id == (_selectedWalletId ?? '').trim(),
            orElse: () => wallets.first,
          );
    final selectedWalletLabel =
        selectedWallet == null ? '' : selectedWallet.labelForLocale(langCode);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          isEdit
              ? tikkiTr(context,
                  ar: 'تعديل إعلان', fr: 'Modifier la pub', en: 'Edit ad')
              : tikkiTr(context,
                  ar: 'إضافة إعلان', fr: 'Ajouter une pub', en: 'Add an ad'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => _safePop(),
          tooltip: tikkiTr(context, ar: 'إغلاق', fr: 'Fermer', en: 'Close'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (!widget.mineOnly) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withAlpha(170)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tikkiTr(context,
                        ar: 'هل تريد إعلانك يظهر هنا؟',
                        fr: 'Vous voulez afficher votre pub ici ?',
                        en: 'Want your ad to appear here?'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tikkiTr(context,
                        ar: 'أضف إعلانك داخل "إعلاناتي". يظهر للناس فقط بعد تفعيل مميّز.',
                        fr: 'Ajoutez votre pub dans "Mes pubs". Elle devient publique seulement après مميّز.',
                        en: 'Add your ad in "My ads". It becomes public only after مميّز.'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:
                          cs.onSurface.withValues(alpha: isDark ? 0.78 : 0.62),
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/promo-ads?mine=1'),
                          icon: const Icon(Icons.person_rounded),
                          label: Text(tikkiTr(context,
                              ar: 'إعلاناتي', fr: 'Mes pubs', en: 'My ads')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            final signedIn =
                                (widget.ownerUserId ?? '').trim().isNotEmpty;
                            if (signedIn) {
                              context.push('/promo-ads?mine=1');
                              return;
                            }
                            final next =
                                Uri.encodeComponent('/promo-ads?mine=1');
                            context.push('/auth?next=$next');
                          },
                          icon: const Icon(Icons.add_circle_outline),
                          label: Text(tikkiTr(context,
                              ar: 'أضف إعلان', fr: 'Ajouter', en: 'Add')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: titleCtrl,
            decoration: InputDecoration(
              labelText:
                  tikkiTr(context, ar: 'العنوان', fr: 'Titre', en: 'Title'),
              hintText: tikkiTr(
                context,
                ar: 'مثال: عروض اليوم داخل تيكي',
                fr: "Ex: Offres du jour surTkii",
                en: 'e.g. Today deals onTkii',
              ),
              helperText: tikkiTr(
                context,
                ar: 'عنوان قصير وواضح يظهر في بطاقة الإعلان',
                fr: 'Un titre court qui s\'affiche sur la carte',
                en: 'A short title shown on the ad card',
              ),
              prefixIcon: const Icon(Icons.title_rounded),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: subCtrl,
            decoration: InputDecoration(
              labelText: tikkiTr(context,
                  ar: 'وصف قصير', fr: 'Sous-titre', en: 'Subtitle'),
              hintText: tikkiTr(
                context,
                ar: 'مثال: خصومات على فئات مختارة',
                fr: "Ex: Remises sur des catégories",
                en: 'e.g. Discounts on selected categories',
              ),
              helperText: tikkiTr(
                context,
                ar: 'سطر واحد لجذب الانتباه (اختياري)',
                fr: 'Une ligne accrocheuse (optionnel)',
                en: 'One catchy line (optional)',
              ),
              prefixIcon: const Icon(Icons.short_text_rounded),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: contactCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+()\-\s]')),
            ],
            decoration: InputDecoration(
              labelText: tikkiTr(context,
                  ar: 'رقم التواصل', fr: 'Téléphone', en: 'Contact phone'),
              hintText: tikkiTr(context,
                  ar: 'مثال: 22200000000 أو 00 00 00 00',
                  fr: 'Ex: 22200000000 ou 00 00 00 00',
                  en: 'e.g. 22200000000 or 00 00 00 00'),
              helperText: tikkiTr(context,
                  ar: 'سيظهر للزبون في التفاصيل (اتصال/واتساب). (اختياري)',
                  fr: 'Affiché dans les détails (Appeler/WhatsApp). (optionnel)',
                  en: 'Shown in details (Call/WhatsApp). (optional)'),
              prefixIcon: const Icon(Icons.phone_rounded),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: bodyCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: tikkiTr(
                context,
                ar: 'تفاصيل (اختياري)',
                fr: 'Détails (optionnel)',
                en: 'Details (optional)',
              ),
              hintText: tikkiTr(
                context,
                ar: 'اكتب تفاصيل مختصرة... (اختياري)',
                fr: 'Écrivez quelques détails... (optionnel)',
                en: 'Write a few details... (optional)',
              ),
              prefixIcon: const Icon(Icons.notes_rounded),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),

          // Image picker (gallery / camera) + optional URL fallback
          Text(
            tikkiTr(context,
                ar: 'صورة الإعلان', fr: "Image de la pub", en: 'Ad image'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withAlpha(170)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _promoImage(
                      context,
                      (_pickedImagePath != null && _pickedImagePath!.isNotEmpty)
                          ? _pickedImagePath!
                          : imgCtrl.text.trim(),
                      width: 84,
                      height: 84,
                      radius: BorderRadius.circular(18),
                      fallbackIcon: Icons.photo_rounded,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tikkiTr(
                              context,
                              ar: 'أضف صورة أو التقطها بالكاميرا',
                              fr: 'Ajoutez une image ou prenez une photo',
                              en: 'Add an image or take a photo',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tikkiTr(
                              context,
                              ar: 'تساعد الصورة على جذب الانتباه. (اختياري)',
                              fr: "Une image attire plus d'attention. (optionnel)",
                              en: 'Images get more attention. (optional)',
                            ),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: cs.onSurface
                                  .withValues(alpha: isDark ? 0.70 : 0.60),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickAdImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_rounded),
                        label: Text(tikkiTr(context,
                            ar: 'من المعرض', fr: 'Galerie', en: 'Gallery')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickAdImage(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_rounded),
                        label: Text(tikkiTr(context,
                            ar: 'الكاميرا', fr: 'Caméra', en: 'Camera')),
                      ),
                    ),
                  ],
                ),
                if (_pickedImagePath != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: _clearPickedImage,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(tikkiTr(context,
                          ar: 'إزالة الصورة', fr: 'Supprimer', en: 'Remove')),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 10),
          TextField(
            controller: imgCtrl,
            onChanged: (_) {
              // Refresh preview when user pastes a URL.
              setState(() {});
            },
            decoration: InputDecoration(
              labelText: tikkiTr(
                context,
                ar: 'رابط صورة (اختياري)',
                fr: "URL de l'image (optionnel)",
                en: 'Image URL (optional)',
              ),
              hintText: 'https://...',
              helperText: tikkiTr(
                context,
                ar: 'اتركه فارغاً إذا اخترت صورة من المعرض/الكاميرا',
                fr: 'Laissez vide si vous choisissez une image',
                en: 'Leave empty if you picked an image',
              ),
              prefixIcon: const Icon(Icons.link_rounded),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 14),

          Text(
            tikkiTr(context,
                ar: 'الفئة عند الضغط',
                fr: 'Catégorie au clic',
                en: 'Tap category'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: (selectedCat == null || selectedCat!.isEmpty)
                ? ''
                : selectedCat!,
            items: [
              DropdownMenuItem<String>(
                value: '',
                child: Text(
                  tikkiTr(context, ar: 'بدون', fr: 'Aucune', en: 'None'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ...maCategories.map(
                (c) => DropdownMenuItem<String>(
                  value: c.id,
                  child: Text(
                    c.name.of(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (v) => setState(() {
              selectedCat = (v ?? '').trim();
              if (selectedCat!.isEmpty) selectedCat = null;
            }),
            decoration: InputDecoration(
              hintText: tikkiTr(
                context,
                ar: 'اختياري: اختر فئة ليتم فتحها عند الضغط',
                fr: 'Optionnel: ouvrir une catégorie au clic',
                en: 'Optional: open a category on tap',
              ),
              prefixIcon: const Icon(Icons.category_rounded),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),

          const SizedBox(height: 14),
          Text(
            tikkiTr(context, ar: 'نطاق الظهور', fr: 'Portée', en: 'Reach'),
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                label: Text(tikkiTr(context,
                    ar: 'ولاية واحدة', fr: '1 wilaya', en: 'One wilaya')),
                selected: _reachMode == _AdReachMode.single,
                onSelected: (_) => _switchReach(_AdReachMode.single),
              ),
              ChoiceChip(
                label: Text(tikkiTr(context,
                    ar: 'عدة ولايات', fr: 'Plusieurs', en: 'Multiple')),
                selected: _reachMode == _AdReachMode.multi,
                onSelected: (_) => _switchReach(_AdReachMode.multi),
              ),
              ChoiceChip(
                label: Text(tikkiTr(context,
                    ar: 'كل موريتانيا',
                    fr: 'Tout le pays',
                    en: 'Country-wide')),
                selected: _reachMode == _AdReachMode.country,
                onSelected: (_) => _switchReach(_AdReachMode.country),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_reachMode == _AdReachMode.single) ...[
            DropdownButtonFormField<String>(
              value: _targetWilayaId.isEmpty ? null : _targetWilayaId,
              items: maWilayas
                  .map(
                    (w) => DropdownMenuItem<String>(
                      value: w.id,
                      child: Text(w.name.of(context)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (v) => setState(() {
                _targetWilayaId = (v ?? '').trim();
                _syncReachFromTarget();
              }),
              decoration: InputDecoration(
                hintText: tikkiTr(context,
                    ar: 'اختر ولاية',
                    fr: 'Choisissez une wilaya',
                    en: 'Pick a wilaya'),
                prefixIcon: const Icon(Icons.place_rounded),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tikkiTr(context,
                  ar: 'إعلان ولاية واحدة هو الأرخص. اختر "عدة ولايات" للوصول لمناطق أكثر.',
                  fr: 'Une wilaya est la moins chère. Choisissez "Plusieurs" pour une portée plus large.',
                  en: 'One wilaya is cheapest. Pick “Multiple” to reach more areas.'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.onSurface.withValues(alpha: isDark ? 0.62 : 0.64),
              ),
            ),
          ] else if (_reachMode == _AdReachMode.multi) ...[
            InkWell(
              onTap: _openMultiWilayaPicker,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant.withAlpha(160)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.map_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _multiWilayaIds.isEmpty
                            ? tikkiTr(context,
                                ar: 'اضغط لاختيار الولايات',
                                fr: 'Appuyez pour choisir',
                                en: 'Tap to choose wilayas')
                            : tikkiTr(context,
                                ar: 'تم اختيار ${_multiWilayaIds.length} ولاية',
                                fr: '${_multiWilayaIds.length} wilayas sélectionnées',
                                en: '${_multiWilayaIds.length} wilayas selected'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Icon(Icons.edit_rounded,
                        color: cs.onSurface.withValues(alpha: 0.70)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withAlpha(160)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: cs.primary.withValues(alpha: 0.90)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tikkiTr(
                        context,
                        ar: 'كل ولاية إضافية تزيد السعر +$extraPctLabel% (حتى حد أقصى يساوي السعر الأساسي ×$multiCapLabel).',
                        fr: 'Chaque wilaya en plus ajoute +$extraPctLabel% (plafond = base ×$multiCapLabel).',
                        en: 'Each extra wilaya adds +$extraPctLabel% (cap = base ×$multiCapLabel).',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withAlpha(160)),
              ),
              child: Row(
                children: [
                  Icon(Icons.public_rounded,
                      color: cs.primary.withValues(alpha: 0.90)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tikkiTr(context,
                          ar: 'سيظهر إعلانك في جميع ولايات موريتانيا (السعر ×$countryMult).',
                          fr: 'Votre pub sera visible partout (prix ×$countryMult).',
                          en: 'Your ad will appear country-wide (price ×$countryMult).'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          if (isEdit &&
              widget.initial != null &&
              widget.initial!.isPromoApproved &&
              !wantsVip) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant.withAlpha(170)),
              ),
              child: Row(
                children: [
                  Icon(Icons.star_rounded,
                      color: cs.primary.withValues(alpha: 0.90)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tikkiTr(context,
                          ar: 'هذا الإعلان مميّز حالياً',
                          fr: 'Cette pub est مميّز',
                          en: 'This ad is currently مميّز'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => wantsVip = true),
                    child: Text(tikkiTr(context,
                        ar: 'تجديد', fr: 'Renouveler', en: 'Renew')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // مميّز promotion request (manual payment)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withAlpha(170)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.star_rounded, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tikkiTr(context,
                                ar: 'ترويج مميّز',
                                fr: 'Promotion مميّز',
                                en: 'مميّز promotion'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tikkiTr(
                              context,
                              ar: 'ادفع عبر إحدى وسائل الدفع المتاحة ثم أدخل رقم العملية. يتم التفعيل بعد المراجعة.',
                              fr: 'Payez via une méthode disponible puis saisissez le numéro. Activation après validation.',
                              en: 'Pay using an available method then enter the transaction/reference id. Activated after review.',
                            ),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface
                                  .withValues(alpha: isDark ? 0.70 : 0.62),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: wantsVip,
                      onChanged: (vipLocked || !vipOffersAvailable)
                          ? null
                          : (v) => setState(() {
                                wantsVip = v;
                                if (!v) {
                                  selectedVipPkg = null;
                                  _selectedWalletId = null;
                                  txCtrl.clear();
                                }
                              }),
                    ),
                  ],
                ),
                if (!wantsVip) ...[
                  const SizedBox(height: 8),
                  Text(
                    tikkiTr(
                      context,
                      ar: 'بدون مميّز: سيظهر إعلانك داخل "إعلاناتي" فقط. لتظهر للناس في الصفحة الرئيسية، فعّل مميّز.',
                      fr: 'Sans مميّز : votre pub reste dans "Mes pubs" uniquement. Pour la rendre publique, activez مميّز.',
                      en: 'Without مميّز: your ad stays in "My ads" only. Enable مميّز to make it public.',
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.25,
                      color:
                          cs.onSurface.withValues(alpha: isDark ? 0.78 : 0.62),
                    ),
                  ),
                ],
                if (wantsVip) ...[
                  const SizedBox(height: 10),
                  if (!vipOffersAvailable) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: cs.outlineVariant.withAlpha(170)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: cs.onSurface.withValues(alpha: 0.70)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              tikkiTr(
                                context,
                                ar: 'لا توجد باقات مميّز متاحة حالياً. سيظهر إعلانك بدون مميّز حتى يقوم الأدمن بإضافة باقات.',
                                fr: 'Aucun pack مميّز disponible pour le moment. La pub sera sans مميّز.',
                                en: 'No مميّز packages available right now. Your ad will be created without مميّز.',
                              ),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, height: 1.25),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    if (wallets.isEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: cs.outlineVariant.withAlpha(170)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: cs.error.withValues(alpha: 0.90)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                tikkiTr(
                                  context,
                                  ar: 'لم يتم إعداد وسائل الدفع من قبل الأدمن بعد. لن يعرف المستخدم أين يدفع.',
                                  fr: 'Aucune méthode de paiement n\'est configurée par l\'admin.',
                                  en: 'No payment methods configured by admin yet.',
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Text(
                        tikkiTr(context,
                            ar: 'اختر وسيلة الدفع',
                            fr: 'Choisir une méthode',
                            en: 'Choose payment method'),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: wallets.any(
                                (w) => w.id == (_selectedWalletId ?? '').trim())
                            ? (_selectedWalletId ?? '').trim()
                            : wallets.first.id,
                        items: wallets
                            .map(
                              (w) => DropdownMenuItem<String>(
                                value: w.id,
                                child: Text(w.labelForLocale(langCode)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: vipLocked
                            ? null
                            : (v) => setState(
                                  () => _selectedWalletId = (v ?? '').trim(),
                                ),
                        decoration: InputDecoration(
                          prefixIcon:
                              const Icon(Icons.account_balance_wallet_rounded),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: cs.outlineVariant.withAlpha(170)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.account_balance_wallet_rounded,
                                color: cs.onSurface.withValues(alpha: 0.70)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${selectedWalletLabel.isEmpty ? tikkiTr(context, ar: 'محفظة', fr: 'Portefeuille', en: 'Wallet') : selectedWalletLabel}: ${selectedWallet?.number ?? ''}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    (selectedWallet?.displayName ?? '').trim(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color:
                                          cs.onSurface.withValues(alpha: 0.62),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: tikkiTr(context,
                                  ar: 'نسخ', fr: 'Copier', en: 'Copy'),
                              onPressed: selectedWallet == null
                                  ? null
                                  : () async {
                                      await Clipboard.setData(
                                        ClipboardData(
                                            text: selectedWallet!.number),
                                      );
                                      if (!mounted) return;
                                      _toast(tikkiTr(context,
                                          ar: 'تم النسخ',
                                          fr: 'Copié',
                                          en: 'Copied'));
                                    },
                              icon: const Icon(Icons.copy_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      tikkiTr(context,
                          ar: 'اختر الباقة',
                          fr: 'Choisir le pack',
                          en: 'Choose package'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: (!vipOffersAvailable || vipLocked)
                          ? null
                          : () async {
                              FocusManager.instance.primaryFocus?.unfocus();
                              await Future<void>.delayed(
                                  const Duration(milliseconds: 40));
                              if (!mounted) return;
                              final picked =
                                  await showModalBottomSheet<_VipPkg>(
                                context: context,
                                showDragHandle: true,
                                backgroundColor: cs.surface,
                                builder: (ctx) {
                                  return SafeArea(
                                    child: ListView(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 8, 16, 16),
                                      children: [
                                        Text(
                                          tikkiTr(ctx,
                                              ar: 'اختر الباقة',
                                              fr: 'Choisir le pack',
                                              en: 'Choose package'),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16),
                                        ),
                                        const SizedBox(height: 10),
                                        if (adVipPkgs.isEmpty)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 24),
                                            child: Text(
                                              tikkiTr(ctx,
                                                  ar: 'لا توجد باقات مميّز متاحة حالياً.',
                                                  fr: 'Aucun pack مميّز disponible.',
                                                  en: 'No مميّز packages available.'),
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: cs.onSurface
                                                    .withValues(alpha: 0.65),
                                              ),
                                            ),
                                          )
                                        else
                                          ...adVipPkgs.map(
                                            (p) => ListTile(
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              leading: Icon(
                                                Icons.star_rounded,
                                                color: cs.primary,
                                              ),
                                              title: Text(
                                                p.label(ctx),
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w900),
                                              ),
                                              subtitle: Text(
                                                'MRU ${_vipPriceForTarget(
                                                  p,
                                                  _targetWilayaId,
                                                  countryWideMultiplier:
                                                      countryMult,
                                                  extraPercentPerWilaya:
                                                      extraPct,
                                                  multiWilayaCapMultiplier:
                                                      capMult,
                                                )}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  color: cs.onSurface
                                                      .withValues(alpha: 0.65),
                                                ),
                                              ),
                                              trailing: const Icon(
                                                  Icons.chevron_right_rounded),
                                              onTap: () =>
                                                  Navigator.of(ctx).pop(p),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              );
                              if (!mounted) return;
                              if (picked != null) {
                                setState(() => selectedVipPkg = picked);
                              }
                            },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14)),
                          contentPadding: const EdgeInsetsDirectional.fromSTEB(
                              12, 14, 12, 14),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                selectedVipPkg == null
                                    ? (vipOffersAvailable
                                        ? tikkiTr(context,
                                            ar: 'اضغط للاختيار',
                                            fr: 'Appuyez pour choisir',
                                            en: 'Tap to choose')
                                        : tikkiTr(context,
                                            ar: 'غير متاح حالياً',
                                            fr: 'Indisponible',
                                            en: 'Not available'))
                                    : '${selectedVipPkg!.label(context)} • MRU ${_vipPriceForTarget(
                                        selectedVipPkg!,
                                        _targetWilayaId,
                                        countryWideMultiplier: countryMult,
                                        extraPercentPerWilaya: extraPct,
                                        multiWilayaCapMultiplier: capMult,
                                      )}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: selectedVipPkg == null
                                      ? cs.onSurface.withValues(alpha: 0.55)
                                      : cs.onSurface,
                                ),
                              ),
                            ),
                            Icon(Icons.keyboard_arrow_down_rounded,
                                color: cs.onSurface.withValues(alpha: 0.70)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: txCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tikkiTr(
                          context,
                          ar: 'رقم العملية${selectedWalletLabel.isEmpty ? '' : ' ($selectedWalletLabel)'}',
                          fr: 'Référence de paiement${selectedWalletLabel.isEmpty ? '' : ' ($selectedWalletLabel)'}',
                          en: 'Payment reference${selectedWalletLabel.isEmpty ? '' : ' ($selectedWalletLabel)'}',
                        ),
                        hintText: tikkiTr(
                          context,
                          ar: 'مثال: 36566606',
                          fr: 'Ex: 36566606',
                          en: 'e.g. 36566606',
                        ),
                        helperText: tikkiTr(
                          context,
                          ar: 'أدخل الرقم كما ظهر لك بعد إتمام الدفع',
                          fr: 'Saisissez la référence reçue après paiement',
                          en: 'Enter the reference you received after payment',
                        ),
                        prefixIcon:
                            const Icon(Icons.confirmation_number_rounded),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _safePop(),
                  child: Text(tikkiTr(context,
                      ar: 'إلغاء', fr: 'Annuler', en: 'Cancel')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    final t = titleCtrl.text.trim();
                    if (t.isEmpty) {
                      _toast(tikkiTr(context,
                          ar: 'اكتب العنوان أولاً',
                          fr: 'Entrez un titre',
                          en: 'Enter a title'));
                      return;
                    }

                    final isNew = widget.initial == null;
                    // Normal ads can be saved without مميّز. They become public only after مميّز activation.
                    if (isNew && (widget.ownerUserId ?? '').trim().isEmpty) {
                      _toast(tikkiTr(context,
                          ar: 'سجل الدخول أولاً',
                          fr: 'Connectez-vous d\'abord',
                          en: 'Please sign in first'));
                      return;
                    }

                    // Reach validation
                    if (_reachMode == _AdReachMode.single &&
                        _targetWilayaId.trim().isEmpty) {
                      _toast(tikkiTr(context,
                          ar: 'اختر ولاية واحدة',
                          fr: 'Choisissez une wilaya',
                          en: 'Choose one wilaya'));
                      return;
                    }
                    if (_reachMode == _AdReachMode.multi &&
                        _multiWilayaIds.isEmpty) {
                      _toast(tikkiTr(context,
                          ar: 'اختر ولاية واحدة على الأقل',
                          fr: 'Choisissez au moins une wilaya',
                          en: 'Choose at least one wilaya'));
                      return;
                    }
                    if (wantsVip) {
                      if (wallets.isNotEmpty && selectedWallet == null) {
                        _toast(tikkiTr(context,
                            ar: 'اختر وسيلة الدفع أولاً',
                            fr: 'Choisissez une méthode de paiement',
                            en: 'Choose a payment method'));
                        return;
                      }
                      if (selectedVipPkg == null) {
                        _toast(tikkiTr(context,
                            ar: 'اختر باقة مميّز أولاً',
                            fr: 'Choisissez un pack مميّز',
                            en: 'Choose a مميّز package'));
                        return;
                      }
                      if (txCtrl.text.trim().isEmpty) {
                        _toast(tikkiTr(context,
                            ar: 'أدخل رقم العملية',
                            fr: 'Entrez la référence de paiement',
                            en: 'Enter the payment reference'));
                        return;
                      }
                    }

                    final now = DateTime.now().millisecondsSinceEpoch;
                    final picked = (_pickedImagePath ?? '').trim();
                    final url = imgCtrl.text.trim();
                    final img = picked.isNotEmpty
                        ? picked
                        : (url.isEmpty
                            ? 'https://picsum.photos/seed/tikki_userad_$now/200/200'
                            : url);
                    final sub = subCtrl.text.trim();
                    final body = bodyCtrl.text.trim();

                    final prev = widget.initial;
                    final id = prev?.id ?? 'USR-$now';
                    final prevApproved = prev?.isPromoApproved ?? false;
                    final prevPending = prev?.isPromoPending ?? false;
                    final effectiveWantsVip = wantsVip || prevApproved;
                    final promoStatus = effectiveWantsVip
                        ? (prevApproved ? (prev!.promoStatus) : 'pending')
                        : 'none';

                    final prevApproved2 = prev?.isPromoApproved ?? false;
                    final pkg = effectiveWantsVip ? selectedVipPkg : null;
                    final promoPkgId = effectiveWantsVip
                        ? (pkg?.id ?? prev?.promoPkgId)
                        : (prevApproved2 ? prev?.promoPkgId : null);
                    final promoWalletId = effectiveWantsVip
                        ? (() {
                            final v = (selectedWallet?.id ??
                                    (prev?.promoWalletId ?? ''))
                                .trim();
                            return v.isEmpty ? null : v;
                          })()
                        : (prevApproved2 ? prev?.promoWalletId : null);
                    final promoTxId = effectiveWantsVip
                        ? (txCtrl.text.trim().isEmpty
                            ? (prev?.promoTxId ?? '')
                            : txCtrl.text.trim())
                        : (prevApproved2 ? prev?.promoTxId : null);
                    final promoReqAtMs =
                        effectiveWantsVip ? (prev?.promoReqAtMs ?? now) : null;
                    final promoApprAtMs = prev?.promoApprAtMs;
                    // مميّز becomes active only after approval. Keep existing until/approval.
                    final promoUntilMs = prev?.promoUntilMs;

                    final target = _targetWilayaId.trim();
                    final targetWilayaId = target.isEmpty ? null : target;
                    final owner = (prev?.ownerUserId ??
                            fb.FirebaseAuth.instance.currentUser?.uid ??
                            widget.ownerUserId)
                        ?.trim();
                    final contact = contactCtrl.text.trim();
                    final contactPhone = contact.isEmpty ? null : contact;

                    final item = _PromoItem(
                      id: id,
                      imageUrl: img,
                      isVip: prev?.isVip ?? false,
                      contactPhone: contactPhone,
                      ownerUserId: owner,
                      targetWilayaId: targetWilayaId,
                      promoStatus: promoStatus,
                      promoPkgId: promoPkgId,
                      promoTxId: promoTxId,
                      promoWalletId: promoWalletId,
                      promoReqAtMs: promoReqAtMs,
                      promoApprAtMs: promoApprAtMs,
                      promoUntilMs: promoUntilMs,
                      createdByMe: prev?.createdByMe ?? true,
                      categoryId: selectedCat,
                      arTitle: t,
                      frTitle: t,
                      enTitle: t,
                      arSubtitle: sub.isEmpty
                          ? tikkiTr(context,
                              ar: 'إعلان جديد',
                              fr: 'Nouvelle pub',
                              en: 'New ad')
                          : sub,
                      frSubtitle: sub.isEmpty
                          ? tikkiTr(context,
                              ar: 'إعلان جديد',
                              fr: 'Nouvelle pub',
                              en: 'New ad')
                          : sub,
                      enSubtitle: sub.isEmpty
                          ? tikkiTr(context,
                              ar: 'إعلان جديد',
                              fr: 'Nouvelle pub',
                              en: 'New ad')
                          : sub,
                      arBody: body.isEmpty ? '' : body,
                      frBody: body.isEmpty ? '' : body,
                      enBody: body.isEmpty ? '' : body,
                    );

                    await _safePop(item);
                  },
                  child: Text(
                    isEdit
                        ? AppStrings.of(context).save
                        : AppStrings.of(context).navPublish,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PromoListTile extends StatelessWidget {
  const _PromoListTile(
      {required this.item, required this.onTap, this.trailing});
  final _PromoItem item;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withAlpha(170)),
          ),
          child: Row(
            children: [
              _promoImage(
                context,
                item.imageUrl,
                width: 48,
                height: 48,
                radius: BorderRadius.circular(12),
                fallbackIcon: item.isPromoApproved
                    ? Icons.star_rounded
                    : Icons.campaign_rounded,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        if (item.isPromoApproved) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: cs.primary.withAlpha(22),
                              borderRadius: BorderRadius.circular(999),
                              border:
                                  Border.all(color: cs.primary.withAlpha(70)),
                            ),
                            child: Text(
                              'مميّز',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 11.5,
                                color: cs.primary,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ] else if (item.isPromoPending) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: cs.tertiary.withAlpha(18),
                              borderRadius: BorderRadius.circular(999),
                              border:
                                  Border.all(color: cs.tertiary.withAlpha(70)),
                            ),
                            child: Text(
                              tikkiTr(context,
                                  ar: 'قيد المراجعة',
                                  fr: 'En attente',
                                  en: 'Pending'),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 11.0,
                                color: cs.tertiary,
                                height: 1.0,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                        color: cs.onSurface
                            .withValues(alpha: isDark ? 0.78 : 0.62),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.place_rounded,
                            size: 14,
                            color: cs.onSurface.withValues(alpha: 0.52)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.targetLabel(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                              color: cs.onSurface.withValues(alpha: 0.52),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (item.createdByMe || item.isPromoPending) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                          color: cs.onSurface.withValues(alpha: 0.44),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurface.withValues(alpha: isDark ? 0.55 : 0.45),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TikkiSplitBanner extends ConsumerStatefulWidget {
  const _TikkiSplitBanner({
    this.height = 58,
    this.collapseT = 0.0,
  });

  final double height;

  /// 0 = expanded, 1 = fully collapsed (used to "Temu-fold" the content).
  final double collapseT;
  @override
  ConsumerState<_TikkiSplitBanner> createState() => _TikkiSplitBannerState();
}

class _TikkiSplitBannerState extends ConsumerState<_TikkiSplitBanner> {
  final PageController _supportCtl = PageController();
  final PageController _adminCtl = PageController();
  Timer? _timer;
  int _supportIndex = 0;
  int _adminIndex = 0;

  // Updated at runtime (remote notes length).
  int _adminLen = _adminNotes.length;

  static const _supportTopics = <Map<String, String>>[
    {'ar': 'كيف أشتري؟', 'fr': 'Comment acheter ?', 'en': 'How to buy?'},
    {
      'ar': 'كيف أتواصل مع البائع؟',
      'fr': 'Contacter le vendeur',
      'en': 'Contact seller'
    },
    {'ar': 'الدفع', 'fr': 'Paiement', 'en': 'Payments'},
    {
      'ar': 'التوصيل و الاستلام',
      'fr': 'Livraison & retrait',
      'en': 'Delivery & pickup'
    },
  ];

  static const _adminNotes = <Map<String, String>>[
    {
      'ar': 'عروض تيكي: خصومات أسبوعية',
      'fr': 'OffresTkii: promos hebdo',
      'en': 'Tikki deals: weekly promos',
    },
    {
      'ar': 'تحديث جديد قريباً',
      'fr': 'Mise à jour bientôt',
      'en': 'New update coming',
    },
  ];

  String _pick(BuildContext context, Map<String, String> m) {
    return tikkiTr(
      context,
      ar: m['ar'] ?? '',
      fr: m['fr'] ?? '',
      en: m['en'] ?? '',
    );
  }

  void _tick() {
    if (_supportCtl.hasClients && _supportTopics.length > 1) {
      final next = (_supportIndex + 1) % _supportTopics.length;
      _supportCtl.animateToPage(
        next,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
    if (_adminCtl.hasClients && _adminLen > 1) {
      final next = (_adminIndex + 1) % _adminLen;
      _adminCtl.animateToPage(
        next,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _supportCtl.dispose();
    _adminCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Home offers notes (right tile): loaded from Firestore if available.
    // Collection: `home_offers` (active == true).
    final remote = ref.watch(homeOffersNotesProvider).maybeWhen(
          data: (v) => v,
          orElse: () => const <HomeOfferNote>[],
        );

    final adminNotes = remote.isNotEmpty
        ? remote.map((e) => e.toUiMap()).where((m) {
            return (m['ar'] ?? '').trim().isNotEmpty ||
                (m['fr'] ?? '').trim().isNotEmpty ||
                (m['en'] ?? '').trim().isNotEmpty;
          }).toList(growable: false)
        : _adminNotes;

    // Keep timer math aligned with the currently-rendered notes.
    _adminLen = adminNotes.isEmpty ? 0 : adminNotes.length;
    if (_adminIndex >= _adminLen && _adminLen > 0) {
      _adminIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_adminCtl.hasClients) _adminCtl.jumpToPage(0);
      });
    }

    final t = widget.collapseT.clamp(0.0, 1.0);
    double lerp(double a, double b) => a + (b - a) * t;

    // As the header collapses, reduce padding and hide the second line.
    final vPad = lerp(8, 6);
    final showDetails = t < 0.55;

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withAlpha(160)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Row(
          children: [
            // Left: support ticker
            Expanded(
              child: _HalfTile(
                onTap: () => context.push('/you/support'),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, vPad, 12, vPad),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: cs.primary.withAlpha(18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.support_agent_rounded,
                            color: cs.primary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tikkiTr(context,
                                  ar: 'الدعم', fr: 'Support', en: 'Support'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 11.5,
                                color: cs.onSurface.withAlpha(190),
                              ),
                            ),
                            if (showDetails) ...[
                              const SizedBox(height: 2),
                              SizedBox(
                                height: 16,
                                child: PageView.builder(
                                  controller: _supportCtl,
                                  scrollDirection: Axis.vertical,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _supportTopics.length,
                                  onPageChanged: (i) =>
                                      setState(() => _supportIndex = i),
                                  itemBuilder: (context, i) {
                                    return Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: Text(
                                        _pick(context, _supportTopics[i]),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Divider
            Container(width: 1, color: cs.outlineVariant.withAlpha(140)),

            // Right: admin-only announcement
            Expanded(
              child: _HalfTile(
                onTap: () => context.push('/discounts'),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, vPad, 12, vPad),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: cs.secondary.withAlpha(18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child:
                            Icon(Icons.campaign_rounded, color: cs.secondary),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tikkiTr(context,
                                  ar: 'عروض تيكي',
                                  fr: 'OffresTkii',
                                  en: 'Tikki offers'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 11.5,
                                color: cs.onSurface.withAlpha(190),
                              ),
                            ),
                            if (showDetails) ...[
                              const SizedBox(height: 2),
                              SizedBox(
                                height: 16,
                                child: PageView.builder(
                                  controller: _adminCtl,
                                  scrollDirection: Axis.vertical,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: adminNotes.length,
                                  onPageChanged: (i) =>
                                      setState(() => _adminIndex = i),
                                  itemBuilder: (context, i) {
                                    return Align(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      child: Text(
                                        _pick(context, adminNotes[i]),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HalfTile extends StatelessWidget {
  const _HalfTile({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: child),
    );
  }
}

/// Compact card used in the مميّز Top strip under the header.
class _VipMiniCard extends StatelessWidget {
  const _VipMiniCard({required this.product, required this.onTap});

  final AppProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImg = product.imageUrl.trim().isNotEmpty;
    final price = product.price;

    return SizedBox(
      width: 270,
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withAlpha(170)),
            ),
            child: Row(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color:
                        cs.surfaceContainerHighest.withAlpha(isDark ? 120 : 90),
                    image: hasImg
                        ? DecorationImage(
                            image: NetworkImage(product.imageUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: hasImg
                      ? null
                      : Icon(Icons.image_rounded,
                          color: cs.onSurface.withValues(alpha: 0.45)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: cs.primary.withValues(alpha: 0.22)),
                            ),
                            child: Text(
                              tikkiTr(context, ar: '...', fr: '...', en: '...'),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                                color: cs.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              product.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded,
                              size: 14,
                              color: cs.onSurface.withValues(alpha: 0.55)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              product.wilaya,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: cs.onSurface
                                    .withValues(alpha: isDark ? 0.78 : 0.62),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'MRU $price',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
