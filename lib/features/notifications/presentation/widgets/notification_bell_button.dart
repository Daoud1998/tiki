import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/localization/l10n.dart';

import '../notifications_controller.dart';

class NotificationBellButton extends ConsumerWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsControllerProvider);
    final unread = state.unreadCount;

    return IconButton(
      tooltip: context.tr('notifications.title'),
      onPressed: () {
        final go = GoRouter.maybeOf(context);
        if (go != null) {
          final loc = go.routerDelegate.currentConfiguration.uri.toString();
          if (loc.startsWith('/notifications')) return;
          // Use push so back returns to the previous page (e.g., You/Home).
          context.push('/notifications');
        } else {
          Navigator.of(context).pushNamed('/notifications');
        }
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none),
          if (unread > 0)
            Positioned(
              top: -2,
              right: -2,
              child: _Badge(count: unread),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final int count;
  const _Badge({required this.count});

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : '$count';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      constraints: const BoxConstraints(minWidth: 18),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
