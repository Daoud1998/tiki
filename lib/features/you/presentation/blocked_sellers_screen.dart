import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/localization/l10n.dart';
import '../../../core/state/blocked_sellers_controller.dart';

class BlockedSellersScreen extends ConsumerWidget {
  const BlockedSellersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final blocked = ref.watch(blockedSellersProvider).toList()..sort();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.blockedSellers),
        actions: [
          if (blocked.isNotEmpty)
            TextButton(
              onPressed: () async {
                await ref.read(blockedSellersProvider.notifier).clear();
              },
              child: Text(
                _tr(context, ar: 'مسح الكل', fr: 'Tout effacer', en: 'Clear'),
              ),
            ),
        ],
      ),
      body: blocked.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _tr(context,
                      ar: 'لا يوجد محظورون بعد',
                      fr: 'Aucun vendeur bloqué',
                      en: 'No blocked sellers yet'),
                  style: TextStyle(color: cs.onSurface.withOpacity(0.75)),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: blocked.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final phone = blocked[i];
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: cs.outline.withOpacity(0.25)),
                  ),
                  child: ListTile(
                    title: Text(phone,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      _tr(context,
                          ar: 'لن تظهر منتجات هذا الرقم داخل التطبيق',
                          fr: 'Ses annonces ne s\'afficheront plus',
                          en: 'Their items will be hidden'),
                    ),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        await ref
                            .read(blockedSellersProvider.notifier)
                            .unblock(phone);
                      },
                      child: Text(s.unblock),
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _tr(BuildContext c,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'fr') return fr;
    if (code == 'en') return en;
    return ar;
  }
}
