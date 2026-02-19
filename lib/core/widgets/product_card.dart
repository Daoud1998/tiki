import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/ma_catalog.dart';
import '../data/ma_locations.dart';
import '../mocks/promo_moderation.dart';
import '../state/likes_controller.dart';
import '../utils/helper.dart';

enum ProductCardVariant { feed, trending, grid, compact }

/// A Temu-like product card that never overflows.
///
/// - Tap the card to open details.
/// - Tap the heart to like/unlike WITHOUT navigating.
class ProductCard extends ConsumerWidget {
  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    bool compact = false,
    this.showLikeButton = true,
    this.onLikeOverride,
    this.showMeta = true,
    this.variant = ProductCardVariant.feed,
    // required String productId,
  }) : compact = compact || variant == ProductCardVariant.trending;

  /// Accepts either Product or dynamic.
  final dynamic product;
  final VoidCallback onTap;
  final bool compact;
  final bool showLikeButton;

  final bool showMeta;
  final ProductCardVariant variant;

  /// Optional override if some screen wants custom like behavior.
  final Future<void> Function()? onLikeOverride;

  String _tr(BuildContext context,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'ar') return ar;
    if (code == 'fr') return fr;
    return en;
  }

  String _wilayaLabel(BuildContext context) =>
      resolveWilayaLabelSmart(context, _wilaya);

  String get _id => (product.id ?? '') as String;
  String get _title => (product.title ?? '') as String;
  num get _price => (product.price ?? 0) as num;
  num? get _oldPrice => product.oldPrice as num?;
  String get _wilaya => (product.wilaya ?? '') as String;
  String get _sellerName {
    final p = product;
    if (p is dynamic) return p.sellerName;
    try {
      final v = p.sellerName;
      if (v is String) return v;
    } catch (_) {}
    return '';
  }

  String get _sellerId {
    final p = product;
    if (p is dynamic) return p.sellerId;
    try {
      final v = p.sellerId;
      if (v is String) return v;
    } catch (_) {}

    // Some models might use `ownerId`.
    try {
      final v = p.ownerId;
      if (v is String) return v;
    } catch (_) {}

    return '';
  }

  void _openSeller(BuildContext context) {
    final sid = _sellerId.trim();
    if (sid.isEmpty) return;
    final name = _sellerName.trim();
    final qp = name.isNotEmpty ? '?name=${Uri.encodeComponent(name)}' : '';
    context.push('/seller/$sid$qp');
  }

  String get _imageUrl {
    final p = product;
    if (p is dynamic) return p.imageUrl;

    try {
      final v = p.imageUrl;
      if (v is String) return v;
    } catch (_) {}

    try {
      final v = p.image;
      if (v is String) return v;
    } catch (_) {}

    return '';
  }

  List<String> get _images {
    final p = product;

    if (p is dynamic) return p.images;

    // Try common shapes used across the app (Product, Map, etc.)
    try {
      final v = p.images;
      if (v is List) {
        return v.map((e) => '$e').where((s) => s.trim().isNotEmpty).toList();
      }
    } catch (_) {}

    try {
      final v = p.imageUrls;
      if (v is List) {
        return v.map((e) => '$e').where((s) => s.trim().isNotEmpty).toList();
      }
    } catch (_) {}

    final single = _imageUrl.trim();
    return single.isNotEmpty ? <String>[single] : const <String>[];
  }

  DateTime get _publishedAt =>
      (product.publishedAt ?? DateTime.now()) as DateTime;
  bool get _isSold => (product.isSold ?? false) as bool;

  bool get _isVipActive {
    final p = product;
    if (p is dynamic) return PromoModeration.isVipActive(p);
    // Best-effort for future models that expose attrs map.
    try {
      final attrs = p.attrs;
      if (attrs is Map) {
        final m = attrs.map((k, v) => MapEntry(k.toString(), v.toString()));
        final status = (m[PromoKeys.promoStatus] ?? "").toLowerCase();
        final untilMs = int.tryParse(m[PromoKeys.promoUntilMs] ?? "");
        if (status == "approved" && untilMs != null) {
          return DateTime.now().millisecondsSinceEpoch < untilMs;
        }
      }
    } catch (_) {}
    return false;
  }

  String _vipBadgeText(BuildContext context) {
    final p = product;
    if (p is dynamic) return PromoModeration.promoBadgeText(context, p);
    return 'مميّز';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final liked = ref.watch(likesProvider.select((s) => s.contains(_id)));

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withAlpha(153)),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, c) {
            // Split height between image and info WITHOUT clamp (prevents overflow).
            final h =
                c.maxHeight.isFinite ? c.maxHeight : (compact ? 210.0 : 320.0);

            // If the card is rendered in a tight slot (Trending / small grids),
            // switch automatically to a compact layout to prevent overflows.
            //
            // NOTE: Grid cards are typically tighter (2 columns on phones), so we treat them as compact.
            final bool isGrid = variant == ProductCardVariant.grid;
            final bool isTight = h <= 230.0 || isGrid;
            final bool isCompact = compact || isTight;

            // Narrow slots (2-column grids) are the most likely to overflow because the price row wraps.
            final double cardW = c.maxWidth.isFinite ? c.maxWidth : 180.0;
            final bool isNarrow = cardW <= 175.0;

            // In seller grids, showing the seller line is redundant and costs vertical space.
            final bool showSellerRow = showMeta &&
                _sellerName.trim().isNotEmpty &&
                !isGrid &&
                !isCompact;

            // Minimum space reserved for the info section depends on what we show.
            // This is the main guard against "BOTTOM OVERFLOWED BY XX PIXELS".
            final double baseInfoH = showMeta
                ? (isCompact ? (isNarrow ? 90.0 : 86.0) : 100.0)
                : (isCompact ? (isNarrow ? 62.0 : 60.0) : 72.0);

            // Seller row adds one extra line.
            final double extraSellerH =
                showSellerRow ? (isCompact ? 18.0 : 20.0) : 0.0;

            // Extra buffer when the price row can wrap (deal text or old price).
            final bool hasOldPrice = (_oldPrice != null && _oldPrice! > _price);
            final bool isDeal = _price <= 0;
            final double extraWrapH =
                (isNarrow && (hasOldPrice || isDeal)) ? 14.0 : 0.0;

            final double minInfoH = baseInfoH + extraSellerH + extraWrapH;

            // Make image dominant (better visibility like Temu).
            final targetImageH = h * (isCompact ? 0.75 : 0.80);

            // Always leave enough room for the info section without exceeding total height.
            final maxImageH = (h - minInfoH).clamp(0.0, h);
            final imageH = targetImageH.clamp(0.0, maxImageH).floorToDouble();

            // Remaining height goes to info (never clamped up).
            final infoH = (h - imageH).clamp(0.0, h);
            final images = _images;
            final fallbackLabel = _categoryLabel(context);
            final fallbackIcon = _iconForCategory(_resolvedCategoryId);
            return Column(
              children: [
                SizedBox(
                  height: imageH,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _CardImage(
                        url: images.isNotEmpty ? images.first : _imageUrl,
                        fallbackIcon: fallbackIcon,
                        fallbackLabel: fallbackLabel,
                      ),
                      if (images.length > 1)
                        PositionedDirectional(
                          top: 10,
                          start: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withAlpha(140),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.photo_library_outlined,
                                    size: 16, color: Colors.white),
                                const SizedBox(width: 6),
                                Text(
                                  '+${images.length - 1}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_isSold)
                        Align(
                          alignment: AlignmentDirectional.bottomStart,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(140),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle,
                                      size: 16, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text(
                                      _tr(context,
                                          ar: 'تم البيع',
                                          fr: 'Vendu',
                                          en: 'Sold'),
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_isVipActive)
                        Align(
                          alignment: AlignmentDirectional.bottomEnd,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withAlpha(150),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded,
                                      size: 16, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Text(
                                    _vipBadgeText(context),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (showLikeButton)
                        PositionedDirectional(
                          top: 10,
                          end: 10,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () async {
                              if (_id.isEmpty) return;

                              // Toggle like (and WAIT so UI stays consistent).
                              if (onLikeOverride != null) {
                                await onLikeOverride!();
                              } else {
                                await ref
                                    .read(likesProvider.notifier)
                                    .toggle(_id);
                              }

                              final nowLiked =
                                  ref.read(likesProvider).contains(_id);

                              // Small hint (non-blocking).
                              final msg = nowLiked
                                  ? 'تمت الإضافة إلى الإعجابات'
                                  : 'تمت الإزالة من الإعجابات';

                              showQuickSnack(
                                context,
                                msg,
                                actionLabel: 'You',
                                onAction: () => context.go('/you'),
                              );
                            },
                            child: Container(
                              height: isCompact ? 34 : 38,
                              width: isCompact ? 34 : 38,
                              decoration: BoxDecoration(
                                color: cs.surface.withAlpha(235),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: cs.outlineVariant.withAlpha(153)),
                              ),
                              child: Icon(
                                liked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: liked
                                    ? const Color(0xFFFF4D6D)
                                    : cs.onSurface.withAlpha(191),
                                size: isCompact ? 18 : 20,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: infoH,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        (isCompact ? 10 : 12).toDouble(),
                        (isCompact ? (isNarrow ? 8 : 10) : 10).toDouble(),
                        (isCompact ? 10 : 12).toDouble(),
                        (isCompact ? (isNarrow ? 8 : 10) : 10).toDouble()),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        Text(
                          _title,
                          maxLines: (isGrid ? 1 : (isCompact ? 1 : 2)),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: isCompact ? 12.5 : 14.5,
                          ),
                        ),
                        if (showMeta) ...[
                          SizedBox(height: isCompact ? (isNarrow ? 3 : 4) : 6),

                          // Location + time

                          Row(
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: isCompact ? 14 : 16, color: cs.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _wilayaLabel(context),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: isCompact ? 11 : 12),
                                ),
                              ),
                              if (!(isCompact && isNarrow)) ...[
                                const SizedBox(width: 6),
                                Text(
                                  _timeAgo(context, _publishedAt),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: isCompact ? 10.5 : 11.5,
                                    color: cs.onSurface.withAlpha(166),
                                  ),
                                ),
                              ],
                            ],
                          ),

                          if (showSellerRow) ...[
                            SizedBox(
                                height: isCompact ? (isNarrow ? 2 : 3) : 4),
                            Row(
                              children: [
                                Icon(Icons.person_outline,
                                    size: isCompact ? 14 : 16,
                                    color: cs.onSurface.withAlpha(180)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => _openSeller(context),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 2),
                                      child: Text(
                                        _sellerName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: isCompact ? 10.8 : 12,
                                          color: cs.primary.withAlpha(230),
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],

                        const Spacer(),
                        // Price row uses Wrap so it NEVER overflows.
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              (_price <= 0
                                  ? _dealText(context)
                                  : '${_price.toStringAsFixed(0)} MRU'),
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: isCompact ? 12.5 : 14.5,
                                  color: cs.primary),
                            ),
                            if (_oldPrice != null && _oldPrice! > _price)
                              Text(
                                '${_oldPrice!.toStringAsFixed(0)} MRU',
                                style: TextStyle(
                                  fontSize: isCompact ? 11 : 12,
                                  color: cs.onSurface.withAlpha(140),
                                  decoration: TextDecoration.lineThrough,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String? _tryGetString(String key) {
    // Support both typed Product models and Map-like payloads.
    try {
      if (key == 'category') {
        final v = product.category;
        if (v is String) return v;
      }
    } catch (_) {}

    try {
      if (key == 'categoryId') {
        final v = product.categoryId;
        if (v is String) return v;
      }
    } catch (_) {}

    // Some versions used `cat` instead of `categoryId`.
    try {
      if (key == 'categoryId') {
        final v = product.cat;
        if (v is String) return v;
      }
    } catch (_) {}

    // Map / JSON shape
    try {
      final v = (product as dynamic)[key];
      if (v == null) return null;
      if (v is String) return v;
      return '$v';
    } catch (_) {}

    return null;
  }

  /// Returns a localized label for either a category id OR a stored label.
  ///
  /// - If [any] is a category id (e.g. "electronics"), we return its localized name.
  /// - If [any] is a subcategory id (e.g. "beauty"), we return the subcategory name.
  /// - If [any] is already a label, we return it as-is.
  String resolveCategoryLabel(BuildContext context, String? any) {
    final raw = (any ?? '').trim();
    if (raw.isEmpty) return '';

    // Try category id first.
    final catId = resolveCategoryIdAny(raw)?.trim() ?? raw;
    for (final c in maCategories) {
      if (c.id == catId) return c.name.of(context);
    }

    // If not a category, try subcategory id.
    final subId = resolveSubCategoryIdAny(raw)?.trim() ?? raw;
    for (final c in maCategories) {
      for (final s in withOtherSubcategory(c.sub)) {
        if (s.id == subId) return s.name.of(context);
      }
    }

    // Fallback for legacy ids not present in ma_catalog.
    switch (raw) {
      case 'sports':
        return _tr(context, ar: 'رياضة', fr: 'Sport', en: 'Sports');
      case 'kids':
        return _tr(context, ar: 'أطفال', fr: 'Enfants', en: 'Kids');
      case 'animals':
        return _tr(context, ar: 'حيوانات', fr: 'Animaux', en: 'Animals');
      default:
        return raw; // might already be localized.
    }
  }

  String _categoryLabel(BuildContext context) {
    final raw = _tryGetString('category') ?? _tryGetString('categoryId') ?? '';
    final id = resolveCategoryIdAny(raw) ?? raw;
    final label = resolveCategoryLabel(context, id);
    if (label.trim().isNotEmpty) return label;
    return _tr(context, ar: 'منتج', fr: 'Produit', en: 'Product');
  }

  String? get _resolvedCategoryId {
    final raw = _tryGetString('category') ?? _tryGetString('categoryId');
    return resolveCategoryIdAny(raw) ?? raw;
  }

  IconData _iconForCategory(String? id) {
    switch ((id ?? '').trim()) {
      case 'vehicles':
        return Icons.directions_car_rounded;
      case 'real_estate':
        return Icons.home_work_rounded;
      case 'electronics':
        return Icons.phone_iphone_rounded;
      case 'home':
        return Icons.chair_alt_rounded;
      case 'fashion':
        return Icons.checkroom_rounded;
      case 'beauty':
        return Icons.brush_rounded;
      case 'sports':
        return Icons.sports_soccer_rounded;
      case 'kids':
        return Icons.child_care_rounded;
      case 'services':
        return Icons.handyman_rounded;
      case 'animals':
        return Icons.pets_rounded;
      default:
        return Icons.local_offer_rounded;
    }
  }

  String _timeAgo(BuildContext context, DateTime dt) {
    final now = DateTime.now();
    final d = now.difference(dt);
    final code = Localizations.localeOf(context).languageCode.toLowerCase();

    String unit(int n, String arS, String arP, String fr, String en) {
      if (code == 'fr') return '$n $fr';
      if (code == 'en') return '$n $en';
      // Arabic (simple)
      return n == 1 ? '$n $arS' : '$n $arP';
    }

    if (d.inMinutes < 1)
      return (code == 'fr')
          ? 'à l’instant'
          : (code == 'en')
              ? 'just now'
              : 'الآن';
    if (d.inHours < 1) return unit(d.inMinutes, 'دقيقة', 'دقائق', 'min', 'min');
    if (d.inDays < 1) return unit(d.inHours, 'ساعة', 'ساعات', 'h', 'h');
    if (d.inDays < 7) return unit(d.inDays, 'يوم', 'أيام', 'j', 'd');
    final w = (d.inDays / 7).floor();
    return unit(w, 'أسبوع', 'أسابيع', 'sem', 'w');
  }
}

String _dealText(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode.toLowerCase();
  if (code == 'fr') return 'À négocier';
  if (code == 'en') return 'Negotiable';
  return 'حسب الاتفاق';
}

class _CardImage extends StatelessWidget {
  const _CardImage({
    required this.url,
    required this.fallbackIcon,
    required this.fallbackLabel,
  });

  final String url;
  final IconData fallbackIcon;
  final String fallbackLabel;

  Widget _fallback(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // When cards are rendered in tight slots (e.g. horizontal shelves),
    // the image area can become short. This fallback adapts to avoid
    // "BOTTOM OVERFLOWED" when there is no image.
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight.isFinite ? c.maxHeight : 140.0;
        final w = c.maxWidth.isFinite ? c.maxWidth : 200.0;

        final bool tight = h < 120 || w < 150;
        final double pad = tight ? 8 : 12;
        final double iconSize = tight ? 32 : 44;
        final double gap = tight ? 6 : 10;
        final int lines = tight ? 1 : 2;
        final double fontSize = tight ? 12.0 : 13.5;

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.primaryContainer.withAlpha(130),
                cs.surfaceContainerHighest,
              ],
            ),
          ),
          alignment: Alignment.center,
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: w - pad * 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(fallbackIcon,
                        size: iconSize, color: cs.primary.withAlpha(220)),
                    SizedBox(height: gap),
                    Text(
                      fallbackLabel,
                      textAlign: TextAlign.center,
                      maxLines: lines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface.withAlpha(200),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _fallback(context),
      );
    }
    if (url.isEmpty) {
      return _fallback(context);
    }

    // Local file path (picked from gallery/camera)
    if (!kIsWeb &&
        (url.startsWith('/') ||
            url.startsWith('file:') ||
            url.contains('\\'))) {
      final path = url.startsWith('file:') ? Uri.parse(url).toFilePath() : url;
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _fallback(context),
      );
    }

    return Image.asset(
      url,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => Container(
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: _fallback(context),
      ),
    );
  }
}
