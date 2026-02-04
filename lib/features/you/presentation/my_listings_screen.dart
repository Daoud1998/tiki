import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:tiki/core/mocks/promo_moderation.dart';
import 'package:tiki/core/state/auth_state.dart';
import 'package:tiki/core/widgets/product_card.dart';
import 'package:tiki/features/product/data/products_repository.dart';
import 'package:tiki/features/product/state/products_providers.dart';

class MyListingsScreen extends ConsumerWidget {
  const MyListingsScreen({super.key});

  String _tr(
    BuildContext context, {
    required String ar,
    required String fr,
    required String en,
  }) {
    final lang = Localizations.localeOf(context).languageCode.toLowerCase();
    if (lang.startsWith('ar')) return ar;
    if (lang.startsWith('fr')) return fr;
    return en;
  }

  String _tierFromPkgId(String pkgId) {
    final x = pkgId.toLowerCase();
    if (x.contains('top')) return 'top';
    if (x.contains('featured')) return 'featured';
    if (x.contains('boost')) return 'boost';
    return '';
  }

  Future<void> _showDeleteOptions(
    BuildContext context, {
    required ProductsRepository repo,
    required dynamic product,
  }) async {
    // product is AppProduct, but kept dynamic to avoid import cycles.
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(
                  _tr(
                    context,
                    ar: 'إخفاء الإعلان (يمكن استرجاعه)',
                    fr: 'Masquer (récupérable)',
                    en: 'Hide (recoverable)',
                  ),
                ),
                subtitle: Text(
                  _tr(
                    context,
                    ar: 'سيختفي من التطبيق ويمكنك إرجاعه لاحقاً.',
                    fr: "Sera masqué, réactivation possible.",
                    en: 'Will be hidden and can be reactivated later.',
                  ),
                ),
                onTap: () => Navigator.pop(ctx, 'soft'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined,
                    color: Colors.redAccent),
                title: Text(
                  _tr(
                    context,
                    ar: 'حذف نهائي (لا رجعة)',
                    fr: 'Supprimer définitivement',
                    en: 'Delete forever',
                  ),
                ),
                subtitle: Text(
                  _tr(
                    context,
                    ar: 'سيتم حذف الإعلان والصور من Firebase نهائياً.',
                    fr: "Supprime l'annonce et les images.",
                    en: 'Deletes listing and images from Firebase.',
                  ),
                ),
                onTap: () => Navigator.pop(ctx, 'hard'),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );

    if (choice == null) return;

    if (choice == 'soft') {
      await repo.setStatus(product.id, 'deleted');
      return;
    }

    // hard delete confirmation
    final ok = await showDialog<bool>(
          context: context,
          builder: (dctx) => AlertDialog(
            title: Text(_tr(context,
                ar: 'حذف نهائي؟',
                fr: 'Suppression définitive ?',
                en: 'Delete forever?')),
            content: Text(_tr(context,
                ar: 'هذا الإجراء لا يمكن التراجع عنه.',
                fr: "Cette action est irréversible.",
                en: 'This action cannot be undone.')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: Text(_tr(context,
                    ar: 'إلغاء', fr: 'Annuler', en: 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: Text(
                    _tr(context, ar: 'حذف نهائي', fr: 'Supprimer', en: 'Delete')),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;
    await repo.deleteProductForever(product);
  }

  Future<void> _showVipOptions(
    BuildContext context, {
    required ProductsRepository repo,
    required dynamic product,
  }) async {
    final pkgs = PromoModeration.packages;

    final chosen = await showDialog<PromoPackage>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(_tr(context,
              ar: 'خيارات VIP', fr: 'Options VIP', en: 'VIP options')),
          content: SizedBox(
            width: 360,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: pkgs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final p = pkgs[i];
                return ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: Text(p.labelOf(context)),
                  subtitle: Text(_tr(context,
                      ar: 'المدة: ${p.days} يوم | السعر: ${p.priceMru} MRU',
                      fr: 'Durée: ${p.days}j | Prix: ${p.priceMru} MRU',
                      en: 'Duration: ${p.days}d | Price: ${p.priceMru} MRU')),
                  onTap: () => Navigator.pop(ctx, p),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child:
                  Text(_tr(context, ar: 'إغلاق', fr: 'Fermer', en: 'Close')),
            ),
          ],
        );
      },
    );

    if (chosen == null) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await repo.updateAttrs(product.id, {
      PromoKeys.promoStatus: PromoStatus.pending,
      PromoKeys.promoPkgId: chosen.id,
      PromoKeys.promoTier: _tierFromPkgId(chosen.id),
      PromoKeys.promoDays: chosen.days.toString(),
      PromoKeys.promoPriceMru: chosen.priceMru.toString(),
      PromoKeys.promoReqAtMs: nowMs.toString(),
      // Leave promoUntilMs empty: admin/automation can approve and set until.
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr(context,
              ar: 'تم إرسال طلب VIP للمراجعة ✅',
              fr: 'Demande VIP envoyée ✅',
              en: 'VIP request sent ✅')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(authControllerProvider);
    final uid =
        (a.userId ?? 'guest').trim().isEmpty ? 'guest' : a.userId!.trim();

    final async = ref.watch(sellerProductsProvider(uid));
    final repo = ref.read(productsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr(context,
            ar: 'إعلاناتي', fr: 'Mes annonces', en: 'My listings')),
        actions: [
          IconButton(
            tooltip: _tr(context, ar: 'نشر', fr: 'Publier', en: 'Publish'),
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => context.go('/publish'),
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
                child: Text(_tr(context,
                    ar: 'لا توجد إعلانات بعد. انشر أول إعلان لك 👇',
                    fr: 'Aucune annonce. Publiez votre première 👇',
                    en: 'No listings yet. Publish your first 👇')),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final p = items[i];
              final vipStatus = PromoModeration.promoStatus(p);
              final isNeedsPrice = vipStatus == PromoStatus.needsPrice;
              final isPending = vipStatus == PromoStatus.pending;
              final isVipActive = PromoModeration.isVipActive(p);

              final isPaused = p.status == 'paused';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProductCard(
                    product: p,
                    onTap: () => context.go('/product/${p.id}'),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Views
                      Chip(
                        avatar: const Icon(Icons.remove_red_eye_outlined, size: 16),
                        label: Text('${p.viewCount}'),
                      ),

                      // Status
                      if (p.status != 'active')
                        Chip(
                          label: Text(p.status.toUpperCase()),
                        ),

                      // VIP tags
                      if (isVipActive)
                        Chip(
                          label: Text(_tr(context,
                              ar: 'VIP مفعّل',
                              fr: 'VIP actif',
                              en: 'VIP active')),
                        ),
                      if (isPending)
                        Chip(
                          label: Text(_tr(context,
                              ar: 'VIP قيد المراجعة',
                              fr: 'VIP en attente',
                              en: 'VIP pending')),
                        ),
                      if (isNeedsPrice)
                        Chip(
                          label: Text(_tr(context,
                              ar: 'VIP يحتاج سعر',
                              fr: 'VIP بحاجة لسعر',
                              en: 'VIP needs price')),
                        ),

                      TextButton.icon(
                        onPressed: () => context.go('/product/${p.id}'),
                        icon: const Icon(Icons.open_in_new),
                        label: Text(
                            _tr(context, ar: 'فتح', fr: 'Ouvrir', en: 'Open')),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          // Opens drafts screen which will create an edit draft and navigate to wizard.
                          context.go('/publish', extra: p);
                        },
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(_tr(context,
                            ar: 'تعديل', fr: 'Modifier', en: 'Edit')),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          if (isPaused) {
                            await repo.resumeProduct(p.id);
                          } else {
                            await repo.pauseProduct(p.id);
                          }
                        },
                        icon: Icon(isPaused
                            ? Icons.play_circle_outline
                            : Icons.pause_circle_outline),
                        label: Text(isPaused
                            ? _tr(context,
                                ar: 'إعادة النشر',
                                fr: 'Republier',
                                en: 'Resume')
                            : _tr(context,
                                ar: 'إيقاف النشر',
                                fr: 'Mettre en pause',
                                en: 'Pause')),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final next =
                              (p.status == 'sold' || p.status == 'deleted')
                                  ? 'active'
                                  : 'sold';
                          await repo.setStatus(p.id, next);
                        },
                        icon: Icon(
                          (p.status == 'sold' || p.status == 'deleted')
                              ? Icons.undo
                              : Icons.check_circle,
                        ),
                        label: Text((p.status == 'sold' || p.status == 'deleted')
                            ? _tr(context,
                                ar: 'إرجاع',
                                fr: 'Réactiver',
                                en: 'Reactivate')
                            : _tr(context,
                                ar: 'تم البيع',
                                fr: 'Vendu',
                                en: 'Sold')),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            _showVipOptions(context, repo: repo, product: p),
                        icon: const Icon(Icons.workspace_premium_outlined),
                        label:
                            Text(_tr(context, ar: 'VIP', fr: 'VIP', en: 'VIP')),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            _showDeleteOptions(context, repo: repo, product: p),
                        icon: const Icon(Icons.delete_outline),
                        label: Text(_tr(context,
                            ar: 'حذف', fr: 'Supprimer', en: 'Delete')),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
