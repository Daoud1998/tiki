import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../../app/localization/l10n.dart';
import '../../../core/data/ma_catalog.dart';
import '../../../core/data/ma_neighborhood_suggestions.dart';
import '../../../core/data/ma_suggestions.dart';
import '../../../core/state/auth_state.dart' as auth;
import '../../kyc/data/kyc_settings_repository.dart';
import '../../kyc/domain/kyc_models.dart';

/// Edit account screen (Firestore-backed profile via AuthController.updateProfile):
/// - Works for Phone OTP accounts (no in-app password)
/// - Saves displayName + optional email to Firestore users/{uid}
///
/// Mauritania-first additions:
/// - Optional wilaya preference saved to users/{uid}.wilayaId
/// - Clear explanation why phone number isn't editable + support shortcut
class EditAccountScreen extends ConsumerStatefulWidget {
  const EditAccountScreen({super.key});

  @override
  ConsumerState<EditAccountScreen> createState() => _EditAccountScreenState();
}

class _EditAccountScreenState extends ConsumerState<EditAccountScreen> {
  final _nameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  bool _prefilled = false;

  bool _saving = false;

  // Extra profile fields stored directly in Firestore.
  bool _extraLoaded = false;
  bool _extraLoading = false;
  String? _wilayaId;
  String? _moughataaId;
  String? _neighborhoodId;
  final _neighborhoodCtl = TextEditingController();

  static const _nouakchott =
      L10n3(ar: 'نواكشوط', fr: 'Nouakchott', en: 'Nouakchott');

  Future<void> _openHelpChangeNumber(AppStrings s) async {
    // Prefer the admin-controlled WhatsApp number from `app_settings/kyc`.
    final uiAsync = ref.read(kycVerificationUiSettingsProvider);
    final ui = uiAsync.asData?.value ?? KycVerificationUiSettings.defaults();

    // If WhatsApp verification is disabled by Admin, fallback to the support page.
    if (!ui.allowWhatsApp) {
      if (mounted) context.go('/you/support');
      return;
    }

    final a = ref.read(auth.authControllerProvider);

    final uid = (a.userId ?? '').trim();
    final name = (a.name ?? _nameCtl.text).trim();
    final phoneNow = (a.phoneE164 ?? '').trim();

    final message = s.isAr
        ? 'السلام عليكم، أريد تغيير رقم الهاتف لحسابي في تيكي.\n'
            'UID: $uid\n'
            'الاسم: $name\n'
            'رقمي الحالي: $phoneNow\n'
            'الرقم الجديد: (اكتب الرقم هنا)\n'
            'شكراً.'
        : s.isFr
            ? 'Bonjour, je souhaite changer le numéro de téléphone de mon compte Tkii.\n'
                'UID: $uid\n'
                'Nom: $name\n'
                'Numéro actuel: $phoneNow\n'
                'Nouveau numéro: (écrivez le numéro ici)\n'
                'Merci.'
            : 'Hi, I want to change the phone number for my Tkii account.\n'
                'UID: $uid\n'
                'Name: $name\n'
                'Current phone: $phoneNow\n'
                'New phone: (type the number here)\n'
                'Thanks.';

    final phone = ui.whatsAppNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final digits = phone.replaceAll('+', '').trim();
    if (digits.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.isAr
                ? 'رقم واتساب الدعم غير مضبوط'
                : s.isFr
                    ? 'Numéro WhatsApp du support manquant'
                    : 'Support WhatsApp number is missing'),
          ),
        );
        context.go('/you/support');
      }
      return;
    }

    final uri =
        Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(message)}');
    final ok = await canLaunchUrl(uri);
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.isAr
                ? 'تعذر فتح واتساب'
                : s.isFr
                    ? "Impossible d'ouvrir WhatsApp"
                    : 'Cannot open WhatsApp'),
          ),
        );
        context.go('/you/support');
      }
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    _neighborhoodCtl.dispose();
    super.dispose();
  }

  void _prefill(auth.AuthState a) {
    if (_prefilled) return;
    _prefilled = true;
    _nameCtl.text = (a.name ?? '').trim();
    _emailCtl.text = (a.email ?? '').trim();
  }

  Future<void> _loadExtra(String uid) async {
    if (_extraLoaded || _extraLoading) return;
    _extraLoading = true;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!snap.exists) {
        _extraLoaded = true;
        return;
      }
      final data = snap.data() ?? <String, dynamic>{};

      // Accept a few legacy keys if any exist.
      final wid =
          (data['wilayaId'] ?? data['wilaya_id'] ?? data['wilaya'] ?? '')
              .toString()
              .trim();
      if (wid.isNotEmpty) {
        _wilayaId = wid;
      }

      final mid = (data['moughataaId'] ??
              data['moughataa_id'] ??
              data['moughataa'] ??
              '')
          .toString()
          .trim();
      if (mid.isNotEmpty) {
        _moughataaId = mid;
      }

      final nid = (data['neighborhoodId'] ??
              data['neighborhood_id'] ??
              data['neighborhoodId'] ??
              '')
          .toString()
          .trim();
      final ntext = (data['neighborhood'] ?? '').toString().trim();
      if (nid.isNotEmpty) {
        _neighborhoodId = nid;
      }
      _neighborhoodCtl.text = ntext;

      _extraLoaded = true;
    } catch (_) {
      // Non-fatal.
      _extraLoaded = true;
    } finally {
      _extraLoading = false;
      if (mounted) setState(() {});
    }
  }

  List<_WilayaOption> _wilayaOptions(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return maWilayas
        .map((w) => _WilayaOption(w.id, w.name.ofLocale(locale)))
        .toList(growable: false);
  }

  List<_MoughataaOption> _moughataaOptions(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final wId = (_wilayaId ?? '').trim();
    final w = wId.isEmpty ? null : findWilayaById(wId);
    final list = w?.moughataas ?? const <Moughataa>[];
    return list
        .map((m) => _MoughataaOption(m.id, m.name.ofLocale(locale)))
        .toList(growable: false);
  }

  static const String _kManualPick = '__manual__';

  Future<void> _pickNeighborhood(BuildContext context) async {
    final s = AppStrings.of(context);
    final wId = (_wilayaId ?? '').trim();
    final mId = (_moughataaId ?? '').trim();
    if (wId.isEmpty || mId.isEmpty) return;

    final list = neighborhoodSuggestionsFor(wilayaId: wId, moughataaId: mId);
    final title = s.isAr
        ? 'الحي/المنطقة (اختياري)'
        : s.isFr
            ? 'Quartier (optionnel)'
            : 'Neighborhood (optional)';

    if (list.isEmpty) {
      await _openManualEntry(context, title: title);
      return;
    }

    final picked = await _openSuggestionPicker(context,
        title: title,
        suggestions: list,
        initialQuery: _neighborhoodCtl.text.trim());

    if (!mounted || picked == null) return;

    if (picked is String && picked == _kManualPick) {
      await _openManualEntry(context, title: title);
      return;
    }

    if (picked is MaSuggestion) {
      setState(() {
        _neighborhoodId = picked.id;
        _neighborhoodCtl.text = picked.display(context);
      });
    }
  }

  Future<void> _openManualEntry(BuildContext context,
      {required String title}) async {
    final s = AppStrings.of(context);
    final ctl = TextEditingController(text: _neighborhoodCtl.text.trim());
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctl,
            decoration: InputDecoration(
              hintText: s.isAr
                  ? 'اكتب اسم الحي'
                  : s.isFr
                      ? 'Saisissez le quartier'
                      : 'Type neighborhood',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: Text(s.isAr
                  ? 'إلغاء'
                  : s.isFr
                      ? 'Annuler'
                      : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dctx).pop(true),
              child: Text(s.isAr
                  ? 'حفظ'
                  : s.isFr
                      ? 'Enregistrer'
                      : 'Save'),
            ),
          ],
        );
      },
    );
    if (ok == true && mounted) {
      setState(() {
        _neighborhoodId = null;
        _neighborhoodCtl.text = ctl.text.trim();
      });
    }
  }

  Future<Object?> _openSuggestionPicker(
    BuildContext context, {
    required String title,
    required List<MaSuggestion> suggestions,
    String initialQuery = '',
  }) async {
    return showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final q = TextEditingController(text: initialQuery);
        return StatefulBuilder(
          builder: (ctx, setS) {
            final query = q.text.trim().toLowerCase();
            final filtered = query.isEmpty
                ? suggestions
                : suggestions
                    .where((sug) => sug.matches(query))
                    .toList(growable: false);

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(ctx).bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.sizeOf(ctx).height * 0.72,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(title,
                                  style: Theme.of(ctx).textTheme.titleMedium),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(ctx).pop(_kManualPick),
                              child: Text(AppStrings.of(ctx).isAr
                                  ? 'إدخال يدوي'
                                  : AppStrings.of(ctx).isFr
                                      ? 'Saisie manuelle'
                                      : 'Manual'),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: TextField(
                          controller: q,
                          onChanged: (_) => setS(() {}),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: AppStrings.of(ctx).isAr
                                ? 'ابحث...'
                                : AppStrings.of(ctx).isFr
                                    ? 'Rechercher...'
                                    : 'Search...',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final sug = filtered[i];
                            return ListTile(
                              title: Text(sug.display(ctx)),
                              onTap: () => Navigator.of(ctx).pop(sug),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _save() async {
    final s = AppStrings.of(context);
    final a = ref.read(auth.authControllerProvider);

    if (!a.isSignedIn) {
      context.push('/auth?next=${Uri.encodeComponent('/account/edit')}');
      return;
    }

    final name = _nameCtl.text.trim();
    final email = _emailCtl.text.trim(); // optional

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.isAr
                ? 'أدخل الاسم'
                : s.isFr
                    ? 'Entrez le nom'
                    : 'Enter a name',
          ),
        ),
      );
      return;
    }

    if (_saving) return;
    setState(() => _saving = true);

    // Pass '' to clear email in Firestore; pass a value to set.
    final err =
        await ref.read(auth.authControllerProvider.notifier).updateProfile(
              name: name,
              email: email.isEmpty ? '' : email,
            );

    if (!mounted) return;

    if (err == null) {
      // Save wilaya preference directly in Firestore.
      try {
        final uid = (a.userId ?? FirebaseAuth.instance.currentUser?.uid);
        if (uid != null && uid.isNotEmpty) {
          final refDoc =
              FirebaseFirestore.instance.collection('users').doc(uid);
          await refDoc.set(
            {
              'wilayaId': (_wilayaId ?? '').trim().isEmpty
                  ? FieldValue.delete()
                  : (_wilayaId ?? '').trim(),
              'moughataaId': (_moughataaId ?? '').trim().isEmpty
                  ? FieldValue.delete()
                  : (_moughataaId ?? '').trim(),
              'neighborhoodId': (_neighborhoodId ?? '').trim().isEmpty
                  ? FieldValue.delete()
                  : (_neighborhoodId ?? '').trim(),
              'neighborhood': _neighborhoodCtl.text.trim().isEmpty
                  ? FieldValue.delete()
                  : _neighborhoodCtl.text.trim(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      } catch (_) {
        // Ignore; not critical for account save.
      }
    }

    setState(() => _saving = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            s.isAr
                ? 'تعذر حفظ الحساب'
                : s.isFr
                    ? 'Impossible d’enregistrer'
                    : 'Could not save',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          s.isAr
              ? 'تم حفظ الحساب ✅'
              : s.isFr
                  ? 'Enregistré ✅'
                  : 'Saved ✅',
        ),
      ),
    );

    if (context.canPop()) {
      context.pop(true);
    } else {
      context.go('/you');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final a = ref.watch(auth.authControllerProvider);

    if (a.isSignedIn) {
      _prefill(a);

      // Load extra profile fields (wilaya) once.
      final uid =
          ((a.userId ?? FirebaseAuth.instance.currentUser?.uid) ?? '').trim();
      if (uid.isNotEmpty && !_extraLoaded && !_extraLoading) {
        // Avoid setState during build.
        Future.microtask(() => _loadExtra(uid));
      }
    }

    final phone = (a.phoneE164 ?? '').trim();
    String ltr(String v) => '\u2066$v\u2069';

    final wilayaOptions = _wilayaOptions(context);
    final moughataaOptions = _moughataaOptions(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          s.isAr
              ? 'تعديل الحساب'
              : s.isFr
                  ? 'Modifier le compte'
                  : 'Edit account',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        children: [
          if (!a.isSignedIn)
            _GuestNote(
              title: s.isAr
                  ? 'أنت الآن زائر'
                  : s.isFr
                      ? 'Vous êtes invité'
                      : 'You are a guest',
              subtitle: s.isAr
                  ? 'سجّل الدخول لتعديل حسابك وحفظ بياناتك.'
                  : s.isFr
                      ? 'Connectez-vous pour modifier et sauvegarder.'
                      : 'Sign in to edit and save your account.',
              onTap: () => context
                  .push('/auth?next=${Uri.encodeComponent('/account/edit')}'),
              buttonText: s.isAr
                  ? 'تسجيل الدخول'
                  : s.isFr
                      ? 'Connexion'
                      : 'Sign in',
            ),
          const SizedBox(height: 12),
          _Field(
            label: s.isAr
                ? 'الاسم'
                : s.isFr
                    ? 'Nom'
                    : 'Name',
            controller: _nameCtl,
            enabled: a.isSignedIn && !_saving,
            icon: Icons.badge_outlined,
          ),
          const SizedBox(height: 12),
          _Field(
            label: s.isAr
                ? 'البريد (اختياري)'
                : s.isFr
                    ? 'Email (optionnel)'
                    : 'Email (optional)',
            controller: _emailCtl,
            enabled: a.isSignedIn && !_saving,
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),

          // Optional wilaya preference
          DropdownButtonFormField<String>(
            value: (_wilayaId ?? '').trim().isEmpty ? null : _wilayaId,
            items: wilayaOptions
                .map(
                  (o) => DropdownMenuItem<String>(
                    value: o.id,
                    child: Text(o.label),
                  ),
                )
                .toList(growable: false),
            onChanged: a.isSignedIn && !_saving
                ? (v) => setState(() {
                      _wilayaId = v;
                      _moughataaId = null;
                      _neighborhoodId = null;
                      _neighborhoodCtl.text = '';
                    })
                : null,
            decoration: InputDecoration(
              labelText: s.isAr
                  ? 'الولاية (اختياري)'
                  : s.isFr
                      ? 'Wilaya (optionnel)'
                      : 'Wilaya (optional)',
              prefixIcon: const Icon(Icons.location_on_outlined),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),

          const SizedBox(height: 12),

          // Optional moughataa (depends on wilaya)
          DropdownButtonFormField<String>(
            value: (_moughataaId ?? '').trim().isEmpty ? null : _moughataaId,
            items: moughataaOptions
                .map(
                  (o) => DropdownMenuItem<String>(
                    value: o.id,
                    child: Text(o.label),
                  ),
                )
                .toList(growable: false),
            onChanged: a.isSignedIn && !_saving
                ? (v) => setState(() {
                      _moughataaId = v;
                      _neighborhoodId = null;
                      _neighborhoodCtl.text = '';
                    })
                : null,
            decoration: InputDecoration(
              labelText: s.isAr
                  ? 'المقاطعة (اختياري)'
                  : s.isFr
                      ? 'Moughataa (optionnel)'
                      : 'Moughataa (optional)',
              prefixIcon: const Icon(Icons.map_outlined),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),

          const SizedBox(height: 12),

          // Optional neighborhood (Nouakchott + Nouadhibou)
          Builder(builder: (context) {
            final wId = (_wilayaId ?? '').trim();
            final showNeighborhood =
                wId.startsWith('nouakchott_') || wId == 'dakhlet_nouadhibou';

            if (!showNeighborhood) return const SizedBox.shrink();

            return TextFormField(
              controller: _neighborhoodCtl,
              readOnly: true,
              onTap: a.isSignedIn && !_saving
                  ? () async {
                      if (((_moughataaId ?? '').trim()).isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(s.isAr
                                ? 'اختر المقاطعة أولاً'
                                : s.isFr
                                    ? 'Choisissez d’abord la moughataa'
                                    : 'Choose moughataa first'),
                            duration: const Duration(milliseconds: 1200),
                          ),
                        );
                        return;
                      }
                      await _pickNeighborhood(context);
                    }
                  : null,
              decoration: InputDecoration(
                labelText: s.isAr
                    ? 'الحي/المنطقة (اختياري)'
                    : s.isFr
                        ? 'Quartier (optionnel)'
                        : 'Neighborhood (optional)',
                hintText: ((_moughataaId ?? '').trim()).isEmpty
                    ? (s.isAr
                        ? 'اختر المقاطعة أولاً'
                        : s.isFr
                            ? 'Choisissez d’abord la moughataa'
                            : 'Choose moughataa first')
                    : (s.isAr
                        ? 'اختر من القائمة أو اكتب يدوياً'
                        : s.isFr
                            ? 'Choisissez ou saisissez'
                            : 'Pick or type'),
                prefixIcon: const Icon(Icons.home_work_outlined),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            );
          }),

          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.phone_outlined),
            title: Text(
              s.isAr
                  ? 'الهاتف'
                  : s.isFr
                      ? 'Téléphone'
                      : 'Phone',
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ltr(phone.isEmpty ? '—' : phone)),
                const SizedBox(height: 6),
                Text(
                  s.isAr
                      ? 'تغيير رقم الهاتف يحتاج تحقق جديد لحماية الحساب.'
                      : s.isFr
                          ? 'Changer de numéro nécessite une nouvelle vérification pour protéger le compte.'
                          : 'Changing phone requires re-verification to protect the account.',
                  style: TextStyle(
                    color:
                        Theme.of(context).colorScheme.onSurface.withAlpha(170),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            trailing: a.isSignedIn
                ? Text(
                    s.isAr
                        ? 'غير قابل للتعديل'
                        : s.isFr
                            ? 'Non modifiable'
                            : 'Not editable',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withAlpha(150),
                    ),
                  )
                : null,
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _openHelpChangeNumber(s),
              icon: const Icon(Icons.support_agent_outlined),
              label: Text(
                s.isAr
                    ? 'مساعدة / تغيير الرقم'
                    : s.isFr
                        ? 'Aide / changer de numéro'
                        : 'Help / change number',
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Password note (Phone OTP accounts have no in-app password).
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withAlpha(110),
              border: Border.all(
                color:
                    Theme.of(context).colorScheme.outlineVariant.withAlpha(150),
              ),
            ),
            child: Text(
              s.isAr
                  ? 'ملاحظة: هذا الحساب يستخدم تسجيل الدخول عبر الهاتف (OTP)، لذلك لا توجد كلمة مرور داخل التطبيق.'
                  : s.isFr
                      ? "Note: ce compte utilise l’OTP par téléphone, donc il n’y a pas de mot de passe dans l’application."
                      : 'Note: This account uses phone OTP, so there is no in-app password.',
              style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withAlpha(190)),
            ),
          ),

          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: a.isSignedIn && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(
              s.isAr
                  ? 'حفظ'
                  : s.isFr
                      ? 'Enregistrer'
                      : 'Save',
            ),
          ),
        ],
      ),
    );
  }
}

class _MoughataaOption {
  const _MoughataaOption(this.id, this.label);
  final String id;
  final String label;
}

class _WilayaOption {
  const _WilayaOption(this.id, this.label);
  final String id;
  final String label;
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.enabled,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: cs.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class _GuestNote extends StatelessWidget {
  const _GuestNote({
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String buttonText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withAlpha(160)),
      ),
      child: Row(
        children: [
          Icon(Icons.person_outline_rounded, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(color: cs.onSurface.withAlpha(180)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonal(onPressed: onTap, child: Text(buttonText)),
        ],
      ),
    );
  }
}
