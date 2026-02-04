import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tiki/app/localization/l10n.dart';
import 'package:tiki/features/admin/data/products_migrator.dart';

String _pick3(AppStrings s,
    {required String ar, required String fr, required String en}) {
  if (s.isFr) return fr;
  if (s.isAr) return ar;
  return en;
}

class ProductsMigrationSheet extends ConsumerStatefulWidget {
  const ProductsMigrationSheet({super.key});

  @override
  ConsumerState<ProductsMigrationSheet> createState() =>
      _ProductsMigrationSheetState();
}

class _ProductsMigrationSheetState extends ConsumerState<ProductsMigrationSheet> {
  bool _running = false;
  bool _cancel = false;

  bool _dryRun = true;
  bool _rebuildTokens = true;
  bool _forceStatusActive = false;
  bool _backfillPhoneTail8 = true;

  ProductsMigrationStats _stats = ProductsMigrationStats(dryRun: true);
  final _logs = <String>[];

  void _log(String msg) {
    _logs.insert(0, msg);
    if (_logs.length > 40) _logs.removeRange(40, _logs.length);
  }

  Future<void> _run() async {
    if (_running) return;

    setState(() {
      _running = true;
      _cancel = false;
      _stats = ProductsMigrationStats(dryRun: _dryRun);
      _logs.clear();
    });

    const migrator = ProductsMigrator();
    try {
      await migrator.run(
        dryRun: _dryRun,
        forceRebuildSearchTokens: _rebuildTokens,
        forceStatusActive: _forceStatusActive,
        backfillPhoneTail8: _backfillPhoneTail8,
        isCancelled: () => _cancel,
        onProgress: (s) {
          if (!mounted) return;
          setState(() => _stats = s);
        },
        onLog: (m) {
          if (!mounted) return;
          setState(() => _log(m));
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stats.failed++;
        _stats.lastError = e.toString();
        _log('FAILED: ${e.toString().split('\n').first}');
      });
    }

    if (!mounted) return;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _pick3(s,
                            ar: 'صيانة المنتجات (Firestore)',
                            fr: 'Maintenance des produits',
                            en: 'Products maintenance'),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: _running ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _pick3(s,
                      ar:
                          'هذه الأداة تصلح الحقول الضرورية للبحث والصفحة الرئيسية: status / publishedAt / title / searchTokens / phoneTail8…',
                      fr:
                          'Cet outil complète les champs nécessaires: status / publishedAt / title / searchTokens / phoneTail8…',
                      en:
                          'This tool backfills required fields: status / publishedAt / title / searchTokens / phoneTail8…'),
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  value: _dryRun,
                  onChanged:
                      _running ? null : (v) => setState(() => _dryRun = v),
                  title: Text(_pick3(s,
                      ar: 'Dry run (بدون كتابة)',
                      fr: 'Dry run (sans écriture)',
                      en: 'Dry run (no writes)')),
                  subtitle: Text(_pick3(s,
                      ar: 'جرّب أولاً، ثم أوقفه لتطبيق التعديلات.',
                      fr: 'Testez d’abord, puis désactivez pour appliquer.',
                      en: 'Test first, then turn off to apply changes.')),
                ),
                SwitchListTile(
                  value: _rebuildTokens,
                  onChanged: _running
                      ? null
                      : (v) => setState(() => _rebuildTokens = v),
                  title: Text(_pick3(s,
                      ar: 'إعادة بناء searchTokens',
                      fr: 'Rebâtir searchTokens',
                      en: 'Rebuild searchTokens')),
                  subtitle: Text(_pick3(s,
                      ar: 'مهم إذا كانت منتجات Firestore لا تظهر في البحث.',
                      fr:
                          'Utile si vos produits Firestore ne sortent pas dans la recherche.',
                      en:
                          'Recommended if Firestore products are not showing in search.')),
                ),
                SwitchListTile(
                  value: _backfillPhoneTail8,
                  onChanged: _running
                      ? null
                      : (v) => setState(() => _backfillPhoneTail8 = v),
                  title: Text(_pick3(s,
                      ar: 'تفعيل بحث الهاتف (آخر 8 أرقام)',
                      fr: 'Recherche téléphone (8 derniers chiffres)',
                      en: 'Phone search (last 8 digits)')),
                  subtitle: Text(_pick3(s,
                      ar:
                          'يضيف/يحدّث الحقل phoneTail8 من رقم الهاتف حتى يعمل البحث بالأرقام.',
                      fr:
                          'Ajoute/met à jour phoneTail8 à partir du numéro pour activer la recherche.',
                      en:
                          'Adds/updates phoneTail8 from phone number to enable digit search.')),
                ),
                SwitchListTile(
                  value: _forceStatusActive,
                  onChanged: _running
                      ? null
                      : (v) => setState(() => _forceStatusActive = v),
                  title: Text(_pick3(s,
                      ar: 'فرض status=active',
                      fr: 'Forcer status=active',
                      en: 'Force status=active')),
                  subtitle: Text(_pick3(s,
                      ar: 'يستثني sold. استخدمه فقط لو كانت حالتك غير صحيحة.',
                      fr: 'Ignore sold. À utiliser seulement si nécessaire.',
                      en: 'Keeps sold. Use only if needed.')),
                ),
                const SizedBox(height: 8),
                if (_running) const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('Scanned', _stats.scanned, cs),
                    _chip(_dryRun ? 'Would update' : 'Updated', _stats.updated,
                        cs),
                    _chip('Skipped', _stats.skipped, cs),
                    _chip('Failed', _stats.failed, cs,
                        danger: _stats.failed > 0),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _running ? null : _run,
                        icon: const Icon(Icons.auto_fix_high_rounded),
                        label: Text(_pick3(s,
                            ar: 'تشغيل', fr: 'Démarrer', en: 'Run')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _running
                            ? () => setState(() => _cancel = true)
                            : null,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: Text(_pick3(s,
                            ar: 'إيقاف', fr: 'Arrêter', en: 'Stop')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if ((_stats.lastId).isNotEmpty)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'last: ${_stats.lastId}',
                      style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                if (_logs.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _pick3(s, ar: 'السجل', fr: 'Journal', en: 'Log'),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        ..._logs.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                e,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface.withValues(alpha: 0.85),
                                ),
                              ),
                            )),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static Widget _chip(String label, int value, ColorScheme cs,
      {bool danger = false}) {
    final bg = danger
        ? cs.error.withOpacity(0.12)
        : cs.primary.withOpacity(0.08);
    final fg = danger ? cs.error : cs.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 11,
              color: fg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$value',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
