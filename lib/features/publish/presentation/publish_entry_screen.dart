import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../product/domain/app_product.dart';
import 'publish_drafts_controller.dart';

/// Entry screen for publishing.
///
/// UX change: when the user taps "Publish", we start directly from the
/// categories step (wizard step 0), instead of showing the drafts list.
class PublishEntryScreen extends ConsumerStatefulWidget {
  const PublishEntryScreen({super.key, this.extra});
  final Object? extra;

  @override
  ConsumerState<PublishEntryScreen> createState() => _PublishEntryScreenState();
}

class _PublishEntryScreenState extends ConsumerState<PublishEntryScreen> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ex = widget.extra;

      // If caller passed a product to edit, create an edit draft and open wizard.
      if (ex is AppProduct) {
        final id = await ref
            .read(publishDraftsControllerProvider.notifier)
            .createEditFromAppProduct(ex);
        if (!mounted) return;
        context.go('/publish/wizard/$id', extra: ex);
        return;
      }

      // Default: create a blank draft and start wizard from categories.
      final id = await ref
          .read(publishDraftsControllerProvider.notifier)
          .createBlank(kind: 'product');
      if (!mounted) return;
      context.go('/publish/wizard/$id');
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}
