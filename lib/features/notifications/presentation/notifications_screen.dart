import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/app_notification.dart';
import '../shared/notifications_i18n.dart';
import 'notifications_controller.dart';

Future<void> _showNotificationDetails(BuildContext context, AppNotification n) {
  final title = n.title.pick(context);
  final body = n.body.pick(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body.isEmpty ? tr(ctx, ar: '—', fr: '—', en: '—') : body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(tr(ctx, ar: 'إغلاق', fr: 'Fermer', en: 'Close')),
        ),
      ],
    ),
  );
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsControllerProvider);
    final controller = ref.read(notificationsControllerProvider.notifier);

    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context,
            ar: 'الإشعارات', fr: 'Notifications', en: 'Notifications')),
        actions: [
          IconButton(
            tooltip: tr(context,
                ar: 'تحديد كمقروء', fr: 'Tout lire', en: 'Mark all read'),
            icon: const Icon(Icons.done_all),
            onPressed: state.items.isEmpty ? null : controller.markAllRead,
          ),
        ],
      ),
      body: Column(
        children: [
          // Enable card (in-app only, no push yet)
          if (!state.inAppNotificationsEnabled && !state.hasSeenEnableCard)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: _EnableCard(
                onEnable: () async {
                  await controller.enableInAppNotifications();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(tr(
                        context,
                        ar: 'تم تفعيل إشعارات داخل التطبيق. إشعارات الهاتف (Push) نضيفها لاحقًا.',
                        fr: "Notifications dans l’app activées. Les push viendront plus tard.",
                        en: 'In-app notifications enabled. Push notifications will be added later.',
                      )),
                    ),
                  );
                },
                onDismiss: () => controller.dismissEnableCard(),
              ),
            ),

          // Filter chips (NO chat/messages)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: tr(context, ar: 'الكل', fr: 'Tout', en: 'All'),
                    selected: state.filter == null,
                    onTap: () => controller.setFilter(null),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label:
                        tr(context, ar: 'التخفيضات', fr: 'Promos', en: 'Deals'),
                    selected: state.filter == AppNotificationType.deals,
                    onTap: () =>
                        controller.setFilter(AppNotificationType.deals),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: tr(context,
                        ar: 'إعلاناتي', fr: 'Mes annonces', en: 'My listings'),
                    selected: state.filter == AppNotificationType.sales,
                    onTap: () =>
                        controller.setFilter(AppNotificationType.sales),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label:
                        tr(context, ar: 'النظام', fr: 'Système', en: 'System'),
                    selected: state.filter == AppNotificationType.system,
                    onTap: () =>
                        controller.setFilter(AppNotificationType.system),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 4),

          Expanded(
            child: state.filtered.isEmpty
                ? _EmptyState(
                    title: tr(context,
                        ar: 'لا توجد إشعارات بعد',
                        fr: 'Aucune notification',
                        en: 'No notifications yet'),
                    subtitle: tr(
                      context,
                      ar: 'سيظهر هنا كل جديد: تخفيضات، تنبيهات، حالة إعلاناتك…',
                      fr: 'Vous verrez ici les nouveautés: promos, alertes, statut de vos annonces…',
                      en: 'You’ll see updates here: deals, alerts, your listings status…',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                    itemCount: state.filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final n = state.filtered[index];
                      return Dismissible(
                        key: ValueKey(n.id),
                        direction: DismissDirection.horizontal,
                        onDismissed: (_) => controller.delete(n.id),
                        background: _DismissBg(isRtl: isRtl),
                        secondaryBackground: _DismissBg(isRtl: isRtl),
                        child: _NotificationTile(
                          notification: n,
                          onTap: () async {
                            await controller.markRead(n.id);

                            final r = (n.targetRoute ?? '').trim();
                            String _decorate(String raw) {
                              try {
                                final uri = Uri.parse(raw);
                                final p = uri.path;
                                final needsFrom = p.startsWith('/product/') ||
                                    p.startsWith('/promo-ads') ||
                                    p.startsWith('/seller/');
                                if (!needsFrom) return raw;
                                final qp = <String, String>{
                                  ...uri.queryParameters
                                };
                                qp.putIfAbsent('from', () => 'notif');
                                return uri
                                    .replace(queryParameters: qp)
                                    .toString();
                              } catch (_) {
                                return raw;
                              }
                            }

                            final target = _decorate(r);

                            if (r.isEmpty) {
                              await _showNotificationDetails(context, n);
                              return;
                            }

                            try {
                              final go = GoRouter.maybeOf(context);
                              if (go != null) {
                                // Use go_router push so the target screen is on top of Notifications (back works).
                                context.push(target);
                              } else {
                                Navigator.of(context).pushNamed(r);
                              }
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(tr(
                                    context,
                                    ar: 'الوجهة غير مهيأة بعد. اربط routes أو غيّر targetRoute.',
                                    fr: "Destination non configurée. Reliez les routes.",
                                    en: 'Destination not configured. Hook up your routes.',
                                  )),
                                ),
                              );
                            }
                          },
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

class _EnableCard extends StatelessWidget {
  final VoidCallback onEnable;
  final VoidCallback onDismiss;

  const _EnableCard({required this.onEnable, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Theme.of(context).dividerColor.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr(
              context,
              ar: 'فعّل الإشعارات ليصلك كل جديد داخل التطبيق.',
              fr: 'Activez les notifications pour recevoir les nouveautés.',
              en: 'Enable notifications to get updates in the app.',
            )),
          ),
          const SizedBox(width: 8),
          TextButton(
              onPressed: onDismiss,
              child: Text(
                  tr(context, ar: 'لاحقًا', fr: 'Plus tard', en: 'Later'))),
          const SizedBox(width: 4),
          ElevatedButton(
              onPressed: onEnable,
              child:
                  Text(tr(context, ar: 'تفعيل', fr: 'Activer', en: 'Enable'))),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.black12),
        ),
        child: Text(label,
            style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final arrow = isRtl ? Icons.chevron_left : Icons.chevron_right;

    final title = notification.title.pick(context);
    final body = notification.body.pick(context);

    final icon = switch (notification.type) {
      AppNotificationType.sales => Icons.storefront_outlined,
      AppNotificationType.deals => Icons.local_offer_outlined,
      AppNotificationType.system => Icons.info_outline,
    };

    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: Theme.of(context).dividerColor.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      Theme.of(context).colorScheme.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: notification.isRead
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                                ),
                          ),
                        ),
                        if (!notification.isRead) ...[
                          const SizedBox(width: 8),
                          Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: Colors.red, shape: BoxShape.circle)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: onSurface.withOpacity(0.82)),
                    ),
                    const SizedBox(height: 6),
                    _TimeText(date: notification.createdAt),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(arrow, color: onSurface.withOpacity(0.55)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeText extends StatelessWidget {
  final DateTime date;
  const _TimeText({required this.date});

  @override
  Widget build(BuildContext context) {
    final diff = DateTime.now().difference(date);

    String text;
    if (diff.inMinutes < 60) {
      text = tr(context,
          ar: 'قبل ${diff.inMinutes} د',
          fr: 'il y a ${diff.inMinutes} min',
          en: '${diff.inMinutes}m ago');
    } else if (diff.inHours < 24) {
      text = tr(context,
          ar: 'قبل ${diff.inHours} س',
          fr: 'il y a ${diff.inHours} h',
          en: '${diff.inHours}h ago');
    } else {
      text = tr(context,
          ar: 'قبل ${diff.inDays} يوم',
          fr: 'il y a ${diff.inDays} j',
          en: '${diff.inDays}d ago');
    }

    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.60)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: onSurface.withOpacity(0.70)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DismissBg extends StatelessWidget {
  final bool isRtl;
  const _DismissBg({required this.isRtl});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: isRtl ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Icon(Icons.delete_outline, color: Colors.red),
    );
  }
}
