import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/support_contacts.dart';
import '../../../core/mocks/promo_moderation.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/widgets/product_card.dart';
import '../../product/data/products_repository.dart';
import '../../product/domain/app_product.dart';
import '../../product/state/products_providers.dart';
import '../../promo/data/promo_repository.dart';
import '../../promo/state/promo_providers.dart';

/// My listings screen (seller dashboard).
///
/// Improvements:
/// - Compact layout (chips in a single horizontal row).
/// - Action buttons are smaller + less cluttered.
/// - Prevent double-taps by disabling buttons while an operation is running.
/// - VIP button shows a clear state (pending / needs price) to avoid repeated taps.
class MyListingsScreen extends ConsumerStatefulWidget {
  const MyListingsScreen({super.key});

  @override
  ConsumerState<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends ConsumerState<MyListingsScreen> {
  /// In-flight operation locks per product/action to prevent double taps.
  final Set<String> _busy = <String>{};

  bool _isBusy(String productId, String action) =>
      _busy.contains('$productId:$action');

  void _setBusy(String productId, String action, bool v) {
    setState(() {
      final k = '$productId:$action';
      if (v) {
        _busy.add(k);
      } else {
        _busy.remove(k);
      }
    });
  }

  String _tr(BuildContext context,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code.startsWith('ar')) return ar;
    if (code.startsWith('fr')) return fr;
    return en;
  }

  String _statusLabel(BuildContext context, String status) {
    switch (status.trim().toLowerCase()) {
      case 'active':
        return _tr(context, ar: 'نشط', fr: 'Actif', en: 'Active');
      case 'paused':
        return _tr(context, ar: 'متوقف', fr: 'En pause', en: 'Paused');
      case 'sold':
        return _tr(context, ar: 'تم البيع', fr: 'Vendu', en: 'Sold');
      case 'deleted':
        return _tr(context, ar: 'مخفي', fr: 'Masqué', en: 'Hidden');
      case 'pending':
        return _tr(context,
            ar: 'جاري المراجعة', fr: 'En attente', en: 'Pending');
      default:
        return status;
    }
  }

  IconData _statusIcon(String status) {
    switch (status.trim().toLowerCase()) {
      case 'paused':
        return Icons.pause_circle_outline;
      case 'sold':
        return Icons.check_circle_outline;
      case 'deleted':
        return Icons.visibility_off_outlined;
      case 'pending':
        return Icons.hourglass_top_rounded;
      default:
        return Icons.info_outline;
    }
  }

  String _tierLabelForLang(String lang, String tier) {
    final t = tier.trim().toLowerCase();
    final l = lang.trim().toLowerCase();

    if (l.startsWith('ar')) {
      switch (t) {
        case 'boost':
          return 'تعزيز';
        case 'featured':
          return 'مميّز';
        case 'top':
          return 'TOP';
        default:
          return tier;
      }
    }

    if (l.startsWith('fr')) {
      switch (t) {
        case 'boost':
          return 'Boost';
        case 'featured':
          return 'Vedette';
        case 'top':
          return 'TOP';
        default:
          return tier;
      }
    }

    // EN
    switch (t) {
      case 'boost':
        return 'Boost';
      case 'featured':
        return 'Featured';
      case 'top':
        return 'TOP';
      default:
        return tier;
    }
  }

  String _tierLabel(BuildContext context, String tier) {
    final lang = Localizations.localeOf(context).languageCode.toLowerCase();
    return _tierLabelForLang(lang, tier);
  }

  String _rejectReason(dynamic p) {
    try {
      final attrs = (p as dynamic).attrs;
      if (attrs is Map) {
        final m =
            attrs.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
        final v = (m[PromoKeys.promoRejectReason] ?? '').trim();
        if (v.isNotEmpty) return v;
        return (m[PromoKeys.rPromoRejectReason] ?? '').trim();
      }
    } catch (_) {}
    return '';
  }

  List<PromoPackage> _packagesFromTiers(
      BuildContext context, List<PromoTier> tiers) {
    final pkgs = <PromoPackage>[];
    for (final t in tiers) {
      for (final d in t.durations) {
        final id = '${t.tier}_${d.days}d';

        String titleForLang(String lang) {
          final l = lang.trim().toLowerCase();
          final raw =
              (t.titles[l] ?? t.titles[l.split('-').first] ?? '').trim();
          if (raw.isNotEmpty) return raw;
          return _tierLabelForLang(l, t.tier);
        }

        pkgs.add(
          PromoPackage(
            id: id,
            labelAr: titleForLang('ar'),
            labelFr: titleForLang('fr'),
            labelEn: titleForLang('en'),
            days: d.days,
            priceMru: d.priceMru,
          ),
        );
      }
    }
    return pkgs;
  }

  String _tierFromPkgId(String pkgId) {
    final x = pkgId.toLowerCase();
    if (x.startsWith('top_') || x.contains('top')) return 'top';
    if (x.startsWith('featured_') || x.contains('featured')) return 'featured';
    if (x.startsWith('boost_') || x.contains('boost')) return 'boost';
    return '';
  }

  String _fmtShortDate(BuildContext context, DateTime dt) {
    try {
      return MaterialLocalizations.of(context).formatShortDate(dt);
    } catch (_) {
      return '${dt.year}-${dt.month}-${dt.day}';
    }
  }

  String _mapError(BuildContext context, Object e) {
    if (e is FirebaseException) {
      final code = e.code.toLowerCase();
      if (code.contains('permission')) {
        return _tr(
          context,
          ar: 'لا يمكن تنفيذ العملية الآن. إذا استمر الخطأ تواصل مع الدعم.',
          fr: 'Action impossible pour le moment. Contactez le support si le problème persiste.',
          en: 'You cannot perform this action right now. Contact support if it persists.',
        );
      }
      if (code.contains('unavailable') || code.contains('network')) {
        return _tr(
          context,
          ar: 'تحقق من الاتصال بالإنترنت',
          fr: 'Vérifiez votre connexion',
          en: 'Check your connection',
        );
      }
    }
    return _tr(context,
        ar: 'حدث خطأ غير متوقع',
        fr: 'Une erreur est survenue',
        en: 'Something went wrong');
  }

  Future<void> _runWithSnack(
    BuildContext context,
    Future<void> Function() op, {
    required String ok,
    String? productId,
    String? action,
  }) async {
    try {
      if (productId != null && action != null)
        _setBusy(productId, action, true);
      await op();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = _mapError(context, e is Object ? e : Exception('error'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (productId != null && action != null && mounted) {
        _setBusy(productId, action, false);
      }
    }
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr(context,
                ar: 'تعذر فتح الرابط',
                fr: "Impossible d’ouvrir le lien",
                en: 'Could not open link')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr(context,
              ar: 'تعذر فتح الرابط',
              fr: "Impossible d’ouvrir le lien",
              en: 'Could not open link')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Uri _supportWhatsAppUri({String message = ''}) {
    final p = kSupportWhatsApp.replaceAll('+', '').replaceAll(' ', '');
    final text = Uri.encodeComponent(message);
    return Uri.parse('https://wa.me/$p?text=$text');
  }

  Future<void> _showVipNeedsPriceDialog(
      BuildContext context, dynamic product) async {
    final msg = _tr(
      context,
      ar: 'لطلب VIP يجب إضافة سعر للمنتج.',
      fr: 'Pour demander VIP, ajoutez un prix.',
      en: 'To request VIP, please add a price.',
    );

    await showDialog<void>(
      context: context,
      builder: (dctx) {
        return AlertDialog(
          title: Text(_tr(context,
              ar: 'السعر مطلوب', fr: 'Prix requis', en: 'Price required')),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dctx).pop();
                context.push('/publish', extra: product);
              },
              child: Text(_tr(context,
                  ar: 'إضافة السعر', fr: 'Ajouter le prix', en: 'Add price')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dctx).pop();
                _openExternal(
                    _supportWhatsAppUri(message: 'VIP request: price missing'));
              },
              child: Text(_tr(context,
                  ar: 'واتساب الدعم',
                  fr: 'WhatsApp support',
                  en: 'WhatsApp support')),
            ),
          ],
        );
      },
    );
  }

  Widget _miniChip(
      {required Widget avatar,
      required Widget label,
      VoidCallback? onPressed}) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall;

    if (onPressed != null) {
      return InputChip(
        avatar: avatar,
        label: DefaultTextStyle(
            style: labelStyle ?? const TextStyle(fontSize: 12), child: label),
        onPressed: onPressed,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );
    }

    return Chip(
      avatar: avatar,
      label: DefaultTextStyle(
          style: labelStyle ?? const TextStyle(fontSize: 12), child: label),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  ButtonStyle _smallButtonStyle(BuildContext context) {
    return ButtonStyle(
      padding: WidgetStateProperty.resolveWith(
          (_) => const EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: WidgetStateProperty.resolveWith((_) =>
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    );
  }

  Future<void> _showVipOptions(
    BuildContext context, {
    required String userId,
    required ProductsRepository repo,
    required dynamic product,
    required List<PromoPackage> packages,
  }) async {
    // Feature via WhatsApp (no VIP / no in-app payments)
    final pid = (product as dynamic).id?.toString() ?? '';
    final title = (product as dynamic).title?.toString() ?? '';
    final msg = _tr(context,
      ar: 'السلام عليكم، أريد تمييز هذا الإعلان:\n$title\nرقم الإعلان: $pid',
      fr: 'Bonjour, je veux mettre en vedette cette annonce :\n$title\nID: $pid',
      en: 'Hi, I want to feature this ad:\n$title\nID: $pid',
    );
    final uri = _supportWhatsAppUri(message: msg);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return;

    // Require price for VIP request.
    try {
      final price = (product as dynamic).price as int?;
      if ((price ?? 0) <= 0) {
        await _showVipNeedsPriceDialog(context, product);
        return;
      }
    } catch (_) {
      // If unknown model, continue.
    }

    if (packages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr(context,
              ar: 'لا توجد باقات VIP متاحة حالياً',
              fr: 'Aucun plan VIP disponible',
              en: 'No VIP plans available')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Group packages by tier.
    final groups = <String, List<PromoPackage>>{};
    for (final p in packages) {
      final tier = _tierFromPkgId(p.id);
      groups.putIfAbsent(tier.isEmpty ? 'other' : tier, () => []).add(p);
    }
    for (final g in groups.values) {
      g.sort((a, b) => a.days.compareTo(b.days));
    }

    final order = <String>['boost', 'featured', 'top', 'other'];
    final chosen = await showModalBottomSheet<PromoPackage>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            builder: (ctx, scroll) {
              return ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Text(
                    _tr(context,
                        ar: 'اختر باقة VIP',
                        fr: 'Choisir un plan VIP',
                        en: 'Choose a VIP plan'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _tr(
                      context,
                      ar: 'سيتم إرسال الطلب للمراجعة قبل التفعيل.',
                      fr: 'La demande sera examinée avant activation.',
                      en: 'Your request will be reviewed before activation.',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  for (final tier in order)
                    if (groups.containsKey(tier)) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 8),
                        child: Text(
                          tier == 'other'
                              ? _tr(context,
                                  ar: 'أخرى', fr: 'Autre', en: 'Other')
                              : _tierLabel(context, tier),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      ...groups[tier]!.map((pkg) {
                        final label = _tr(context,
                            ar: pkg.labelAr, fr: pkg.labelFr, en: pkg.labelEn);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(label),
                          subtitle: Text(_tr(context,
                              ar: '${pkg.days} يوم',
                              fr: '${pkg.days} jours',
                              en: '${pkg.days} days')),
                          trailing: Text('MRU ${pkg.priceMru}'),
                          onTap: () => Navigator.of(ctx).pop(pkg),
                        );
                      }),
                      const Divider(height: 18),
                    ],
                ],
              );
            },
          ),
        );
      },
    );

    if (chosen == null) return;

    final tier = _tierFromPkgId(chosen.id);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await _runWithSnack(
      context,
      () async {
        await FirebaseFirestore.instance.collection('vip_requests').add({
          'uid': userId,
          'productId': product.id,
          'tierId': tier,
          'tier': tier, // legacy compatibility
          'pkgId': chosen.id,
          'days': chosen.days,
          'priceMru': chosen.priceMru,
          'type': 'productVip',
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'createdAtMs': nowMs,
          'reqAtMs': nowMs,
        });
      },
      ok: _tr(context,
          ar: 'تم إرسال طلب VIP',
          fr: 'Demande VIP envoyée',
          en: 'VIP request sent'),
      productId: product.id,
      action: 'vip',
    );
  }

  Future<void> _showDeleteOptions(
    BuildContext context, {
    required ProductsRepository repo,
    required dynamic product,
  }) async {
    final res = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final isDeleted = (product.status ?? '') == 'deleted';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(isDeleted
                      ? Icons.visibility
                      : Icons.visibility_off_outlined),
                  title: Text(isDeleted
                      ? _tr(context,
                          ar: 'إظهار الإعلان', fr: "Afficher", en: 'Unhide')
                      : _tr(context,
                          ar: 'إخفاء الإعلان', fr: "Masquer", en: 'Hide')),
                  onTap: () =>
                      Navigator.of(ctx).pop(isDeleted ? 'unhide' : 'hide'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(_tr(context,
                      ar: 'حذف نهائي',
                      fr: 'Supprimer',
                      en: 'Delete permanently')),
                  onTap: () => Navigator.of(ctx).pop('delete'),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );

    if (res == null) return;

    if (res == 'hide') {
      await _runWithSnack(
        context,
        () => repo.setStatus(product.id, 'deleted'),
        ok: _tr(context, ar: 'تم إخفاء الإعلان', fr: 'Masqué', en: 'Hidden'),
        productId: product.id,
        action: 'delete',
      );
    } else if (res == 'unhide') {
      await _runWithSnack(
        context,
        () => repo.setStatus(product.id, 'active'),
        ok: _tr(context, ar: 'تم إظهار الإعلان', fr: 'Affiché', en: 'Unhidden'),
        productId: product.id,
        action: 'delete',
      );
    } else if (res == 'delete') {
      await _runWithSnack(
        context,
        () => repo.deleteProductForever(product as AppProduct),
        ok: _tr(context, ar: 'تم الحذف', fr: 'Supprimé', en: 'Deleted'),
        productId: product.id,
        action: 'delete',
      );
    }
  }

  Future<void> _showActionsSheet(
    BuildContext context, {
    required String userId,
    required ProductsRepository repo,
    required dynamic product,
    required bool isPaused,
    required bool isSold,
    required bool isDeleted,
    required List<PromoPackage> packages,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(isPaused
                    ? Icons.play_circle_outline
                    : Icons.pause_circle_outline),
                title: Text(isPaused
                    ? _tr(context,
                        ar: 'إعادة النشر', fr: 'Republier', en: 'Resume')
                    : _tr(context,
                        ar: 'إيقاف النشر', fr: 'Pause', en: 'Pause')),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _runWithSnack(
                    context,
                    () => isPaused
                        ? repo.resumeProduct(product.id)
                        : repo.pauseProduct(product.id),
                    ok: isPaused
                        ? _tr(context,
                            ar: 'تمت إعادة النشر',
                            fr: 'Republie',
                            en: 'Resumed')
                        : _tr(context,
                            ar: 'تم إيقاف النشر', fr: 'En pause', en: 'Paused'),
                    productId: product.id,
                    action: 'pause',
                  );
                },
              ),
              ListTile(
                leading: Icon(isSold ? Icons.undo : Icons.check_circle_outline),
                title: Text(isSold
                    ? _tr(context,
                        ar: 'إرجاع للبيع',
                        fr: 'Remettre en vente',
                        en: 'Back for sale')
                    : _tr(context,
                        ar: 'وضع كـ (تم البيع)',
                        fr: 'Marqué vendu',
                        en: 'Mark as sold')),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _runWithSnack(
                    context,
                    () =>
                        repo.setStatus(product.id, isSold ? 'active' : 'sold'),
                    ok: isSold
                        ? _tr(context,
                            ar: 'تم إرجاع المنتج للبيع',
                            fr: 'Remis en vente',
                            en: 'Back for sale')
                        : _tr(context,
                            ar: 'تم وضعه كـ (تم البيع)',
                            fr: 'Marqué vendu',
                            en: 'Marked as sold'),
                    productId: product.id,
                    action: 'sold',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.star_outline_rounded),
                title: Text(_tr(context,
                    ar: 'ميّز إعلانك', fr: 'Mettre en vedette', en: 'Feature your ad')),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _showVipOptions(context,
                      userId: userId,
                      repo: repo,
                      product: product,
                      packages: packages);
                },
              ),
              ListTile(
                leading: Icon(isDeleted ? Icons.visibility : Icons.more_horiz),
                title: Text(_tr(context, ar: 'المزيد', fr: 'Plus', en: 'More')),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _showDeleteOptions(context,
                      repo: repo, product: product);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final userId = auth.userId;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(
            title: Text(_tr(context,
                ar: 'منتجاتي', fr: 'Mes annonces', en: 'My listings'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_tr(context,
                ar: 'سجّل الدخول أولاً',
                fr: 'Connectez-vous',
                en: 'Please sign in')),
          ),
        ),
      );
    }

    final async = ref.watch(sellerProductsProvider(userId));
    final repo = ref.watch(productsRepositoryProvider);
    final tiersAsync = ref.watch(promoTiersProvider);

    final packages = tiersAsync.maybeWhen(
      data: (tiers) => tiers.isNotEmpty
          ? _packagesFromTiers(context, tiers)
          : PromoModeration.packages,
      orElse: () => PromoModeration.packages,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
            _tr(context, ar: 'منتجاتي', fr: 'Mes annonces', en: 'My listings')),
        actions: [
          IconButton(
            tooltip: _tr(context, ar: 'نشر', fr: 'Publier', en: 'Publish'),
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => context.push('/publish'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_tr(context,
                ar: 'تعذر تحميل إعلاناتك',
                fr: 'Impossible de charger',
                en: 'Failed to load')),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_tr(
                  context,
                  ar: 'لا توجد إعلانات بعد. انشر أول إعلان لك 👇',
                  fr: 'Aucune annonce. Publiez votre première 👇',
                  en: 'No listings yet. Publish your first 👇',
                )),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) {
              final p = items[i];
              final basePromoStatus = PromoModeration.promoStatus(p);
              final isVipActive = PromoModeration.isVipActive(p);
              final until = PromoModeration.promoUntil(p);
              final isVipExpired = basePromoStatus == PromoStatus.approved &&
                  until != null &&
                  until.isBefore(DateTime.now());
              final baseRejectReason = basePromoStatus == PromoStatus.rejected
                  ? _rejectReason(p)
                  : '';

              final isPaused = p.status == 'paused';
              final isSold = p.status == 'sold';
              final isDeleted = p.status == 'deleted';

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('vip_requests')
                    .where('uid', isEqualTo: userId)
                    .where('productId', isEqualTo: p.id)
                    .orderBy('createdAt', descending: true)
                    .limit(1)
                    .snapshots(),
                builder: (context, snap) {
                  final req = (snap.data?.docs.isNotEmpty ?? false)
                      ? snap.data!.docs.first.data()
                      : null;
                  final reqStatus =
                      (req?['status'] as String?)?.toLowerCase().trim() ?? '';
                  final promoStatus = (reqStatus == 'pending')
                      ? PromoStatus.pending
                      : (reqStatus == 'rejected')
                          ? PromoStatus.rejected
                          : basePromoStatus;
                  final rejectReason = (reqStatus == 'rejected')
                      ? ((req?['rejectReason'] ??
                              req?['promoRejectReason'] ??
                              req?['reason'] ??
                              '') as String)
                          .trim()
                      : baseRejectReason;

                  final chips = <Widget>[
                    _miniChip(
                      avatar:
                          const Icon(Icons.remove_red_eye_outlined, size: 16),
                      label: Text('${p.viewCount}'),
                    ),
                    _miniChip(
                      avatar:
                          const Icon(Icons.calendar_today_outlined, size: 16),
                      label: Text(_fmtShortDate(context, p.publishedAt)),
                    ),
                    if (p.status != 'active')
                      _miniChip(
                        avatar: Icon(_statusIcon(p.status), size: 16),
                        label: Text(_statusLabel(context, p.status)),
                      ),
                    if (isVipActive)
                      _miniChip(
                        avatar: const Icon(Icons.star_outline_rounded,
                            size: 16),
                        label: Text(
                          until != null
                              ? '${PromoModeration.promoBadgeText(context, p)} • ${_fmtShortDate(context, until)}'
                              : PromoModeration.promoBadgeText(context, p),
                        ),
                      ),
                    if (!isVipActive && isVipExpired)
                      _miniChip(
                        avatar: const Icon(Icons.star_outline_rounded,
                            size: 16),
                        label: Text(_tr(context,
                            ar: 'VIP منتهي',
                            fr: 'VIP expiré',
                            en: 'VIP expired')),
                      ),
                    if (promoStatus == PromoStatus.pending)
                      _miniChip(
                        avatar:
                            const Icon(Icons.hourglass_top_rounded, size: 16),
                        label: Text(_tr(context,
                            ar: 'VIP جاري المراجعة',
                            fr: 'VIP en attente',
                            en: 'VIP pending')),
                      ),
                    if (promoStatus == PromoStatus.needsPrice)
                      _miniChip(
                        avatar: const Icon(Icons.sell_outlined, size: 16),
                        label: Text(_tr(context,
                            ar: 'السعر مطلوب',
                            fr: 'Prix requis',
                            en: 'Price needed')),
                      ),
                    if (promoStatus == PromoStatus.rejected)
                      _miniChip(
                        avatar: const Icon(Icons.block_outlined, size: 16),
                        label: Text(_tr(context,
                            ar: 'مرفوض', fr: 'Refusé', en: 'Rejected')),
                        onPressed: rejectReason.trim().isEmpty
                            ? null
                            : () {
                                showDialog<void>(
                                  context: context,
                                  builder: (dctx) {
                                    return AlertDialog(
                                      title: Text(_tr(context,
                                          ar: 'سبب الرفض',
                                          fr: 'Raison',
                                          en: 'Reason')),
                                      content: Text(rejectReason),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(dctx).pop(),
                                          child: Text(_tr(context,
                                              ar: 'حسناً', fr: 'OK', en: 'OK')),
                                        )
                                      ],
                                    );
                                  },
                                );
                              },
                      ),
                  ];

                  final vipBusy = _isBusy(p.id, 'vip');
                  final pauseBusy = _isBusy(p.id, 'pause');
                  final soldBusy = _isBusy(p.id, 'sold');

                  final vipLabel = (promoStatus == PromoStatus.pending)
                      ? _tr(context,
                          ar: 'جاري المراجعة', fr: 'En attente', en: 'Pending')
                      : (promoStatus == PromoStatus.rejected)
                          ? _tr(context,
                              ar: 'مرفوض', fr: 'Refusé', en: 'Rejected')
                          : (promoStatus == PromoStatus.needsPrice)
                              ? _tr(context,
                                  ar: 'السعر مطلوب',
                                  fr: 'Prix requis',
                                  en: 'Price needed')
                              : _tr(context, ar: 'مميّز', fr: 'Vedette', en: 'Featured');

                  VoidCallback? onVipPressed() {
                    if (vipBusy) return null;
                    if (promoStatus == PromoStatus.pending) {
                      return null; // avoid repeated taps
                    }
                    if (promoStatus == PromoStatus.rejected) {
                      return () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (dctx) {
                            final reasonText = rejectReason.trim().isEmpty
                                ? _tr(context,
                                    ar: 'تم رفض طلب VIP. يمكنك إعادة الطلب.',
                                    fr: 'Demande VIP refusée. Vous pouvez réessayer.',
                                    en: 'VIP request rejected. You can reapply.')
                                : rejectReason.trim();
                            return AlertDialog(
                              title: Text(_tr(context,
                                  ar: 'تم رفض طلب VIP',
                                  fr: 'VIP refusé',
                                  en: 'VIP rejected')),
                              content: Text(reasonText),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dctx).pop(false),
                                  child: Text(_tr(context,
                                      ar: 'إلغاء',
                                      fr: 'Annuler',
                                      en: 'Cancel')),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(dctx).pop(true),
                                  child: Text(_tr(context,
                                      ar: 'إعادة الطلب',
                                      fr: 'Réessayer',
                                      en: 'Reapply')),
                                ),
                              ],
                            );
                          },
                        );
                        if (ok == true && context.mounted) {
                          await _showVipOptions(context,
                              userId: userId,
                              repo: repo,
                              product: p,
                              packages: packages);
                        }
                      };
                    }
                    if (promoStatus == PromoStatus.needsPrice) {
                      return () => _showVipNeedsPriceDialog(context, p);
                    }
                    if (isVipActive) {
                      return () {
                        showDialog<void>(
                          context: context,
                          builder: (dctx) => AlertDialog(
                            title: Text(
                                _tr(context, ar: 'مميّز', fr: 'Vedette', en: 'Featured')),
                            content: Text(
                              until != null
                                  ? _tr(
                                      context,
                                      ar: 'VIP مفعّل حتى ${_fmtShortDate(context, until)}',
                                      fr: 'VIP actif jusqu’au ${_fmtShortDate(context, until)}',
                                      en: 'VIP active until ${_fmtShortDate(context, until)}',
                                    )
                                  : _tr(context,
                                      ar: 'VIP مفعّل',
                                      fr: 'VIP actif',
                                      en: 'VIP active'),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(dctx).pop(),
                                child: Text(_tr(context,
                                    ar: 'حسناً', fr: 'OK', en: 'OK')),
                              ),
                            ],
                          ),
                        );
                      };
                    }
                    return () => _showVipOptions(context,
                        userId: userId,
                        repo: repo,
                        product: p,
                        packages: packages);
                  }

                  return Card(
                    elevation: 0,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ProductCard(
                            product: p,
                            variant: ProductCardVariant.compact,
                            onTap: () => context.push('/product/${p.id}'),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (int j = 0; j < chips.length; j++) ...[
                                  chips[j],
                                  if (j != chips.length - 1)
                                    const SizedBox(width: 8),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              IconButton(
                                tooltip: _tr(context,
                                    ar: 'فتح', fr: 'Ouvrir', en: 'Open'),
                                onPressed: () =>
                                    context.push('/product/${p.id}'),
                                icon: const Icon(Icons.open_in_new),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: FilledButton.icon(
                                  style: _smallButtonStyle(context),
                                  onPressed: pauseBusy || soldBusy || vipBusy
                                      ? null
                                      : () =>
                                          context.push('/publish', extra: p),
                                  icon:
                                      const Icon(Icons.edit_outlined, size: 18),
                                  label: Text(_tr(context,
                                      ar: 'تعديل', fr: 'Modifier', en: 'Edit')),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: _smallButtonStyle(context),
                                  onPressed: onVipPressed(),
                                  icon: vipBusy
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(
                                          Icons.star_outline_rounded,
                                          size: 18),
                                  label: Text(vipLabel),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: _tr(context,
                                    ar: 'المزيد', fr: 'Plus', en: 'More'),
                                onPressed: () => _showActionsSheet(
                                  context,
                                  userId: userId,
                                  repo: repo,
                                  product: p,
                                  isPaused: isPaused,
                                  isSold: isSold,
                                  isDeleted: isDeleted,
                                  packages: packages,
                                ),
                                icon: const Icon(Icons.more_horiz),
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
        },
      ),
    );
  }
}
