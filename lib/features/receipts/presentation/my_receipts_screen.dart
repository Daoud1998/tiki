import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/i18n/tikki_tr.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/mocks/promo_moderation.dart';
import '../../../core/state/auth_state.dart';
import '../../product/state/products_providers.dart';
import '../../notifications/presentation/notifications_controller.dart';
import '../domain/service_receipt.dart';
import '../services/renewal_reminders.dart';
import '../services/receipt_pdf_service.dart';
import 'receipts_controller.dart';

class MyReceiptsScreen extends ConsumerStatefulWidget {
  const MyReceiptsScreen({super.key});

  @override
  ConsumerState<MyReceiptsScreen> createState() => _MyReceiptsScreenState();
}

class _MyReceiptsScreenState extends ConsumerState<MyReceiptsScreen> {
  @override
  void initState() {
    super.initState();
    // Sync approvals from Firestore (products + promo_ads) to local receipts.
    // This makes invoices auto-activate after admin approval.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncApprovals();
    });
  }

  Future<void> _syncApprovals() async {
    final a = ref.read(authControllerProvider);
    final uid = (a.userId ?? '').trim();
    if (uid.isEmpty || uid == 'guest') return;

    final receipts = ref.read(receiptsControllerProvider.notifier);

    // 1) Products: activate pending VIP receipts when promo becomes approved.
    try {
      final products = await ref.read(sellerProductsProvider(uid).future);
      for (final p in products) {
        final attrs = p.attrs ?? const <String, String>{};
        final st = (attrs[PromoKeys.promoStatus] ?? '').trim();
        if (st != PromoStatus.approved) continue;

        final apprMsStr = (attrs[PromoKeys.promoApprAtMs] ?? '').trim();
        final apprMs = int.tryParse(apprMsStr) ?? 0;
        if (apprMs <= 0) continue;

        await receipts.activateLatestPendingProductVip(
          productId: p.id,
          approvedAt: DateTime.fromMillisecondsSinceEpoch(apprMs),
        );
      }
    } catch (_) {}

    // 2) Promo ads: activate pending ad VIP receipts when promoStatus becomes approved.
    try {
      final qs = await FirebaseFirestore.instance
          .collection('promo_ads')
          .where('ownerUserId', isEqualTo: uid)
          .where('promoStatus', isEqualTo: 'approved')
          .limit(50)
          .get();

      for (final d in qs.docs) {
        final m = d.data();
        final apprMs = (m['promoApprAtMs'] is int)
            ? (m['promoApprAtMs'] as int)
            : int.tryParse('${m['promoApprAtMs']}') ?? 0;
        if (apprMs <= 0) continue;

        await receipts.activateLatestPendingPromoAdVip(
          adId: d.id,
          approvedAt: DateTime.fromMillisecondsSinceEpoch(apprMs),
        );
      }
    } catch (_) {}
  }

  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _toggleSelected(String id) {
    final rid = id.trim();
    if (rid.isEmpty) return;
    setState(() {
      if (_selected.contains(rid)) {
        _selected.remove(rid);
      } else {
        _selected.add(rid);
      }
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  void _enterSelectionWith(String id) {
    final rid = id.trim();
    if (rid.isEmpty) return;
    setState(() {
      _selectionMode = true;
      _selected.add(rid);
    });
  }

  void _toggleSelectAll(List<ServiceReceipt> receipts) {
    if (receipts.isEmpty) return;
    setState(() {
      _selectionMode = true;
      if (_selected.length == receipts.length) {
        _selected.clear();
        _selectionMode = false;
      } else {
        _selected
          ..clear()
          ..addAll(receipts.map((r) => r.id));
      }
    });
  }

  Future<void> _deleteSelected(List<ServiceReceipt> receipts) async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: Text(_tr(ctx,
                  ar: 'حذف الفواتير', fr: 'Supprimer', en: 'Delete receipts')),
              content: Text(_tr(ctx,
                  ar: 'هل تريد حذف $count فاتورة؟',
                  fr: 'Supprimer $count reçus ?',
                  en: 'Delete $count receipts?')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child:
                      Text(_tr(ctx, ar: 'إلغاء', fr: 'Annuler', en: 'Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child:
                      Text(_tr(ctx, ar: 'حذف', fr: 'Supprimer', en: 'Delete')),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!ok) return;
    await ref.read(receiptsControllerProvider.notifier).deleteMany(_selected);
    if (mounted) _exitSelection();
  }

  String _tr(BuildContext context,
      {required String ar, required String fr, required String en}) {
    return tikkiTr(context, ar: ar, fr: fr, en: en);
  }

  String _kindLabel(BuildContext context, ServiceReceiptKind kind) {
    switch (kind) {
      case ServiceReceiptKind.productVip:
        return _tr(context,
            ar: 'VIP للمنتج', fr: 'VIP produit', en: 'Product VIP');
      case ServiceReceiptKind.promoAdVip:
        return _tr(context, ar: 'VIP للإعلان', fr: 'VIP pub', en: 'Ad VIP');
      case ServiceReceiptKind.productActivation:
        return _tr(context,
            ar: 'تفعيل المنتج', fr: 'Activation', en: 'Activation');
    }
  }

  String _statusLabel(BuildContext context, ServiceReceiptStatus status) {
    switch (status) {
      case ServiceReceiptStatus.pending:
        return _tr(context,
            ar: 'قيد المراجعة', fr: 'En attente', en: 'Pending');
      case ServiceReceiptStatus.active:
        return _tr(context, ar: 'نشط', fr: 'Actif', en: 'Active');
      case ServiceReceiptStatus.expired:
        return _tr(context, ar: 'منتهي', fr: 'Expiré', en: 'Expired');
      case ServiceReceiptStatus.cancelled:
        return _tr(context, ar: 'ملغي', fr: 'Annulé', en: 'Cancelled');
      case ServiceReceiptStatus.failed:
        return _tr(context, ar: 'فشل', fr: 'Échec', en: 'Failed');
    }
  }

  Color _statusColor(ColorScheme cs, ServiceReceiptStatus status) {
    switch (status) {
      case ServiceReceiptStatus.pending:
        return cs.secondary;
      case ServiceReceiptStatus.active:
        return cs.primary;
      case ServiceReceiptStatus.expired:
        return cs.error;
      case ServiceReceiptStatus.cancelled:
        return cs.outline;
      case ServiceReceiptStatus.failed:
        return cs.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipts = ref.watch(receiptsControllerProvider);

    // Passive reminders (deduped by notification id).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nCtrl = ref.read(notificationsControllerProvider.notifier);
      ReceiptsRenewalReminders.run(receipts, nCtrl);
    });

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? _tr(context,
                  ar: 'تم اختيار ${_selected.length}',
                  fr: '${_selected.length} sélectionné(s)',
                  en: '${_selected.length} selected')
              : _tr(context, ar: 'الفواتير', fr: 'Factures', en: 'Receipts'),
        ),
        actions: _selectionMode
            ? [
                IconButton(
                  tooltip: _tr(context,
                      ar: 'تحديد الكل',
                      fr: 'Tout sélectionner',
                      en: 'Select all'),
                  onPressed: () => _toggleSelectAll(receipts),
                  icon: const Icon(Icons.select_all_rounded),
                ),
                IconButton(
                  tooltip:
                      _tr(context, ar: 'حذف', fr: 'Supprimer', en: 'Delete'),
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _deleteSelected(receipts),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                IconButton(
                  tooltip:
                      _tr(context, ar: 'إلغاء', fr: 'Annuler', en: 'Cancel'),
                  onPressed: _exitSelection,
                  icon: const Icon(Icons.close_rounded),
                ),
              ]
            : [
                IconButton(
                  tooltip: _tr(context,
                      ar: 'اختيار متعدد',
                      fr: 'Sélection multiple',
                      en: 'Multi select'),
                  onPressed: () {
                    setState(() => _selectionMode = true);
                  },
                  icon: const Icon(Icons.checklist_rtl_rounded),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'select_all') {
                      _toggleSelectAll(receipts);
                    }
                    if (v == 'delete_all') {
                      // Option B: select all first, then user confirms delete.
                      _toggleSelectAll(receipts);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_tr(context,
                              ar: 'تم تحديد الكل. اضغط حذف لإتمام العملية.',
                              fr: 'Tout est sélectionné. Appuyez sur Supprimer.',
                              en: 'All selected. Tap Delete to confirm.')),
                        ),
                      );
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'select_all',
                      child: Text(_tr(context,
                          ar: 'تحديد الكل',
                          fr: 'Tout sélectionner',
                          en: 'Select all')),
                    ),
                    PopupMenuItem(
                      value: 'delete_all',
                      child: Text(_tr(context,
                          ar: 'حذف الكل',
                          fr: 'Tout supprimer',
                          en: 'Delete all')),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: _tr(context,
                      ar: 'تحديث', fr: 'Actualiser', en: 'Refresh'),
                  onPressed: () async {
                    await ref
                        .read(receiptsControllerProvider.notifier)
                        .expireIfNeeded();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
      ),
      body: receipts.isEmpty
          ? _EmptyState(
              title: _tr(context,
                  ar: 'لا توجد فواتير بعد',
                  fr: 'Aucune facture',
                  en: 'No receipts yet'),
              subtitle: _tr(context,
                  ar: 'عند تفعيل VIP أو الإعلان سيظهر هنا سجلّ الدفع.',
                  fr: 'Vos paiements VIP apparaîtront ici.',
                  en: 'Your VIP payments will appear here.'),
              actionLabel: _tr(context,
                  ar: 'إنشاء فاتورة تجريبية',
                  fr: 'Créer une démo',
                  en: 'Create demo'),
              onAction: () async {
                final now = DateTime.now();
                final demo = ServiceReceipt(
                  id: 'r_demo_${now.millisecondsSinceEpoch}',
                  kind: ServiceReceiptKind.productVip,
                  status: ServiceReceiptStatus.active,
                  amountMru: 1200,
                  transactionId: '36566606',
                  subjectId: 'P-DEMO',
                  subjectTitleAr: 'منتج تجريبي',
                  subjectTitleFr: 'Produit démo',
                  subjectTitleEn: 'Demo product',
                  startsAt: now,
                  endsAt: now.add(const Duration(days: 3)),
                  createdAt: now,
                  meta: const {'pkgId': 'vip_3d', 'durationMs': 259200000},
                );
                await ref
                    .read(receiptsControllerProvider.notifier)
                    .upsert(demo);
              },
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              itemCount: receipts.length,
              itemBuilder: (ctx, i) {
                final r = receipts[i];
                final title = (Localizations.localeOf(context)
                            .languageCode
                            .toLowerCase() ==
                        'fr')
                    ? (r.subjectTitleFr ?? r.subjectTitleAr ?? r.subjectTitleEn)
                    : (Localizations.localeOf(context)
                                .languageCode
                                .toLowerCase() ==
                            'en')
                        ? (r.subjectTitleEn ??
                            r.subjectTitleAr ??
                            r.subjectTitleFr)
                        : (r.subjectTitleAr ??
                            r.subjectTitleEn ??
                            r.subjectTitleFr);

                final amount = Formatters.priceMRU(r.amountMru);

                final statusColor = _statusColor(cs, r.status);

                final ends = r.endsAt;
                final remaining = r.remaining;

                String? timeLine;
                if (r.status == ServiceReceiptStatus.active &&
                    ends != null &&
                    remaining != null) {
                  if (remaining.isNegative) {
                    timeLine =
                        _tr(context, ar: 'منتهي', fr: 'Expiré', en: 'Expired');
                  } else {
                    final h = remaining.inHours;
                    final d = remaining.inDays;
                    if (d >= 1) {
                      timeLine = _tr(context,
                          ar: 'متبقي $d يوم',
                          fr: 'Reste $d j',
                          en: '$d days left');
                    } else {
                      timeLine = _tr(context,
                          ar: 'متبقي $h ساعة',
                          fr: 'Reste $h h',
                          en: '$h hours left');
                    }
                  }
                }

                final selected = _selected.contains(r.id);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: cs.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: selected
                            ? cs.primary.withAlpha(160)
                            : cs.outlineVariant,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onLongPress: _selectionMode
                          ? null
                          : () => _enterSelectionWith(r.id),
                      onTap: () => _selectionMode
                          ? _toggleSelected(r.id)
                          : context.push('/you/receipts/${r.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _selectionMode
                                ? Checkbox(
                                    value: selected,
                                    onChanged: (_) => _toggleSelected(r.id),
                                  )
                                : Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: statusColor.withAlpha(18),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      r.kind == ServiceReceiptKind.promoAdVip
                                          ? Icons.campaign_rounded
                                          : Icons.local_offer_rounded,
                                      color: statusColor,
                                    ),
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
                                          title ?? _kindLabel(context, r.kind),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: statusColor.withAlpha(16),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border: Border.all(
                                              color: statusColor.withAlpha(70)),
                                        ),
                                        child: Text(
                                          _statusLabel(context, r.status),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 12,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (!_selectionMode)
                                        _ReceiptActionsMenu(receipt: r),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${_kindLabel(context, r.kind)} · $amount',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: cs.onSurface.withAlpha(190),
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  if (timeLine != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      timeLine,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: cs.onSurface.withAlpha(170),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!_selectionMode)
                              Icon(Icons.chevron_right_rounded,
                                  color: cs.onSurface.withAlpha(150)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

enum _ReceiptMenuAction { view, share, print }

class _ReceiptActionsMenu extends ConsumerWidget {
  const _ReceiptActionsMenu({required this.receipt});

  final ServiceReceipt receipt;

  String _tr(BuildContext context,
      {required String ar, required String fr, required String en}) {
    return tikkiTr(context, ar: ar, fr: fr, en: en);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final code = Localizations.localeOf(context).languageCode.toLowerCase();

    Future<void> run(_ReceiptMenuAction action) async {
      try {
        switch (action) {
          case _ReceiptMenuAction.view:
            context.push('/you/receipts/${receipt.id}');
            return;
          case _ReceiptMenuAction.share:
            await ReceiptPdfService.sharePdf(receipt, localeCode: code);
            return;
          case _ReceiptMenuAction.print:
            await ReceiptPdfService.printPdf(receipt, localeCode: code);
            return;
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_tr(context,
                  ar: 'تعذر إنشاء الفاتورة الآن',
                  fr: "Impossible de générer le reçu",
                  en: 'Could not generate invoice')),
            ),
          );
        }
      }
    }

    return PopupMenuButton<_ReceiptMenuAction>(
      tooltip: _tr(context, ar: 'خيارات', fr: 'Options', en: 'Options'),
      icon: Icon(Icons.more_vert_rounded, color: cs.onSurface.withAlpha(200)),
      onSelected: run,
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: _ReceiptMenuAction.view,
          child: Text(_tr(ctx,
              ar: 'عرض الفاتورة', fr: 'Voir le reçu', en: 'View invoice')),
        ),
        PopupMenuItem(
          value: _ReceiptMenuAction.share,
          child: Text(
              _tr(ctx, ar: 'مشاركة PDF', fr: 'Partager PDF', en: 'Share PDF')),
        ),
        PopupMenuItem(
          value: _ReceiptMenuAction.print,
          child: Text(_tr(ctx, ar: 'طباعة', fr: 'Imprimer', en: 'Print')),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cs.primary.withAlpha(18),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(Icons.receipt_long_rounded, color: cs.primary),
            ),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withAlpha(170),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded),
              label: Text(actionLabel),
            )
          ],
        ),
      ),
    );
  }
}
