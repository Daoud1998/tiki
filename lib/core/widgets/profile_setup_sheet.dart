import 'package:flutter/material.dart';

import '../../app/localization/l10n.dart';
import '../data/ma_catalog.dart';
import '../state/profile_state.dart';

Future<UserProfile?> showProfileSetupSheet(
  BuildContext context, {
  UserProfile? initial,
}) {
  return showModalBottomSheet<UserProfile?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => _ProfileSetupSheet(initial: initial),
  );
}

class _ProfileSetupSheet extends StatefulWidget {
  const _ProfileSetupSheet({this.initial});
  final UserProfile? initial;

  @override
  State<_ProfileSetupSheet> createState() => _ProfileSetupSheetState();
}

class _ProfileSetupSheetState extends State<_ProfileSetupSheet> {
  late final TextEditingController _nameCtl;
  String? _wilayaId;
  String? _moughataaId;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.initial?.name ?? '');
    _wilayaId = widget.initial?.wilayaId;
    _moughataaId = widget.initial?.moughataaId;
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final loc = Localizations.localeOf(context);
    final s = context.s;

    final w = (_wilayaId == null) ? null : findWilayaById(_wilayaId!);
    final mList = w?.moughataas ?? const <Moughataa>[];

    final pad = MediaQuery.viewInsetsOf(context).bottom;

    // Avoid deprecated withOpacity (precision loss). Use alpha directly.
    final onSurface70 = cs.onSurface.withAlpha((0.70 * 255).round());
    final fill45 = cs.surfaceContainerHighest.withAlpha((0.45 * 255).round());

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + pad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.person_pin_circle_outlined, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.profileSetupTitle,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            s.profileSetupSubtitle,
            style: TextStyle(color: onSurface70, height: 1.35),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameCtl,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: s.yourName,
              prefixIcon: const Icon(Icons.badge_outlined),
              filled: true,
              fillColor: fill45,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _wilayaId,
            items: [
              for (final wi in maWilayas)
                DropdownMenuItem(
                  value: wi.id,
                  child: Text(wi.name.ofLocale(loc)),
                ),
            ],
            onChanged: (v) {
              setState(() {
                _wilayaId = v;
                _moughataaId = null;
              });
            },
            decoration: InputDecoration(
              labelText: s.profileWilaya,
              prefixIcon: const Icon(Icons.map_outlined),
              filled: true,
              fillColor: fill45,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _moughataaId,
            items: [
              for (final mi in mList)
                DropdownMenuItem(
                  value: mi.id,
                  child: Text(mi.name.ofLocale(loc)),
                ),
            ],
            onChanged: (v) => setState(() => _moughataaId = v),
            decoration: InputDecoration(
              labelText: s.profileMoughataa,
              prefixIcon: const Icon(Icons.place_outlined),
              filled: true,
              fillColor: fill45,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop<UserProfile?>(null),
                  icon: const Icon(Icons.close_rounded),
                  label: Text(s.later),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    final name = _nameCtl.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.profileEnterNameOrLater)),
                      );
                      return;
                    }
                    Navigator.of(context).pop<UserProfile?>(
                      UserProfile(
                        name: name,
                        wilayaId: _wilayaId,
                        moughataaId: _moughataaId,
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: Text(s.save),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
