import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n/tikki_tr.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/widgets/dir_chevrons.dart';

import '../data/kyc_repository.dart';
import '../data/kyc_settings_repository.dart';
import '../domain/kyc_models.dart';
import '../state/kyc_controller.dart';
import 'kyc_ui.dart';

class KycSubmitScreen extends ConsumerStatefulWidget {
  const KycSubmitScreen({super.key});

  @override
  ConsumerState<KycSubmitScreen> createState() => _KycSubmitScreenState();
}

class _KycSubmitScreenState extends ConsumerState<KycSubmitScreen> {
  final _nameCtl = TextEditingController();
  final _idCtl = TextEditingController();
  final _notesCtl = TextEditingController();

  String _docType = 'national_id';

  XFile? _doc;
  XFile? _selfie;

  Uint8List? _docBytes;
  Uint8List? _selfieBytes;

  bool _submitting = false;

  @override
  void dispose() {
    _nameCtl.dispose();
    _idCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  Future<XFile?> _pickImage() async {
    final picker = ImagePicker();
    try {
      return await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 80);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickAndSet({
    required void Function(XFile f, Uint8List bytes) onPicked,
  }) async {
    final f = await _pickImage();
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    setState(() => onPicked(f, bytes));
  }

  Widget _thumb(Uint8List? bytes) {
    if (bytes == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.memory(bytes, height: 48, width: 48, fit: BoxFit.cover),
    );
  }

  InputDecoration _fieldDec({
    required String label,
    String? hint,
    IconData? icon,
  }) {
    final t = Theme.of(context);
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: t.colorScheme.outlineVariant),
    );

    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: t.colorScheme.surfaceVariant,
      prefixIcon: icon != null ? Icon(icon) : null,
      border: baseBorder,
      enabledBorder: baseBorder,
      focusedBorder: baseBorder.copyWith(
        borderSide: BorderSide(color: t.colorScheme.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  String _docTypeLabel(String id) {
    switch (id) {
      case 'national_id':
        return tikkiTr(context,
            ar: 'بطاقة وطنية', fr: 'Carte ID', en: 'National ID');
      case 'driver_license':
        return tikkiTr(context,
            ar: 'رخصة سياقة', fr: 'Permis', en: 'Driver license');
      case 'residence':
        return tikkiTr(context, ar: 'إقامة', fr: 'Résidence', en: 'Residence');
      default:
        return id;
    }
  }

  Future<void> _submit(KycVerificationUiSettings ui) async {
    final auth = ref.read(authControllerProvider);
    final uid = (auth.userId ?? '').trim();

    if (uid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tikkiTr(context,
              ar: 'سجّل الدخول أولاً',
              fr: 'Connectez-vous',
              en: 'Sign in first')),
        ),
      );
      return;
    }

    if (!ui.allowInApp) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tikkiTr(context,
              ar: 'التوثيق داخل التطبيق غير متاح حالياً.',
              fr: 'Indisponible.',
              en: 'Unavailable.')),
        ),
      );
      return;
    }

    if (_doc == null || _selfie == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tikkiTr(
            context,
            ar: 'أضف صورة الوثيقة + سيلفي',
            fr: 'Ajoutez document + selfie',
            en: 'Add document + selfie',
          )),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final repo = ref.read(kycRepositoryProvider);
      await repo.submitIdRequest(
        userId: uid,
        statusWhenSubmitted: 'pending',
        fullName: _nameCtl.text,
        nationalId: _idCtl.text,
        phoneE164: auth.phoneE164,
        notes: _notesCtl.text,
        documentType: _docType,
        document: _doc!,
        selfie: _selfie!,
      );

      await ref.read(kycControllerProvider.notifier).setStatus('pending');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tikkiTr(context,
              ar: 'تم إرسال طلب التوثيق ✅',
              fr: 'Demande envoyée ✅',
              en: 'Request sent ✅')),
        ),
      );
      context.pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tikkiTr(
            context,
            ar: 'تعذر إرسال الطلب. تحقق من الإعدادات والاتصال.',
            fr: "Impossible d'envoyer. Vérifiez.",
            en: 'Failed to submit. Check connection/config.',
          )),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = tikkiTr(context,
        ar: 'توثيق داخل التطبيق',
        fr: "Vérification",
        en: 'In-app verification');
    final uiAsync = ref.watch(kycVerificationUiSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
            icon: DirChevrons.backIos(context), onPressed: () => context.pop()),
      ),
      body: uiAsync.when(
        data: (KycVerificationUiSettings ui) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              KycHintCard(
                icon: Icons.privacy_tip_outlined,
                text: tikkiTr(
                  context,
                  ar: 'ارفع صورة واضحة للوثيقة + سيلفي. هويتك لا تظهر للمستخدمين.',
                  fr: 'Téléversez document + selfie. Identité privée.',
                  en: 'Upload document + selfie. Your identity is private.',
                ),
              ),
              const SizedBox(height: 14),
              KycSection(
                title: tikkiTr(context,
                    ar: 'نوع الوثيقة', fr: 'Document', en: 'Document type'),
                subtitle: tikkiTr(context,
                    ar: 'اختر واحداً', fr: 'Choisissez', en: 'Choose one'),
                icon: Icons.badge_outlined,
                child: Card(
                  elevation: 0,
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        value: 'national_id',
                        groupValue: _docType,
                        title: Text(_docTypeLabel('national_id')),
                        onChanged: (v) =>
                            setState(() => _docType = v ?? _docType),
                      ),
                      const Divider(height: 1),
                      RadioListTile<String>(
                        value: 'driver_license',
                        groupValue: _docType,
                        title: Text(_docTypeLabel('driver_license')),
                        onChanged: (v) =>
                            setState(() => _docType = v ?? _docType),
                      ),
                      const Divider(height: 1),
                      RadioListTile<String>(
                        value: 'residence',
                        groupValue: _docType,
                        title: Text(_docTypeLabel('residence')),
                        onChanged: (v) =>
                            setState(() => _docType = v ?? _docType),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              KycSection(
                title: tikkiTr(context,
                    ar: 'الصور المطلوبة',
                    fr: 'Photos requises',
                    en: 'Required photos'),
                subtitle: tikkiTr(context,
                    ar: 'وثيقة + سيلفي',
                    fr: 'Document + selfie',
                    en: 'Document + selfie'),
                icon: Icons.photo_camera_outlined,
                child: Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.badge_outlined),
                          title: Text(tikkiTr(context,
                              ar: 'صورة الوثيقة',
                              fr: 'Document',
                              en: 'Document photo')),
                          subtitle: Text(tikkiTr(context,
                              ar: 'ارفع صورة واضحة',
                              fr: 'Photo claire',
                              en: 'Clear photo')),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _thumb(_docBytes),
                              const SizedBox(width: 8),
                              FilledButton.tonal(
                                onPressed: _submitting
                                    ? null
                                    : () => _pickAndSet(
                                          onPicked: (f, b) {
                                            _doc = f;
                                            _docBytes = b;
                                          },
                                        ),
                                child: Text(tikkiTr(context,
                                    ar: 'اختيار', fr: 'Choisir', en: 'Pick')),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.face_rounded),
                          title: Text(tikkiTr(context,
                              ar: 'سيلفي', fr: 'Selfie', en: 'Selfie')),
                          subtitle: Text(tikkiTr(context,
                              ar: 'التقط/ارفع صورة واضحة لوجهك',
                              fr: 'Photo claire',
                              en: 'Clear face photo')),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _thumb(_selfieBytes),
                              const SizedBox(width: 8),
                              FilledButton.tonal(
                                onPressed: _submitting
                                    ? null
                                    : () => _pickAndSet(
                                          onPicked: (f, b) {
                                            _selfie = f;
                                            _selfieBytes = b;
                                          },
                                        ),
                                child: Text(tikkiTr(context,
                                    ar: 'اختيار', fr: 'Choisir', en: 'Pick')),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              KycSection(
                title: tikkiTr(context,
                    ar: 'معلومات (اختيارية)',
                    fr: 'Infos (optionnel)',
                    en: 'Info (optional)'),
                subtitle: tikkiTr(context,
                    ar: 'تساعد الإدارة في المراجعة السريعة.',
                    fr: "Aide pour la revue.",
                    en: 'Helps admin review faster.'),
                icon: Icons.edit_note_rounded,
                child: Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _nameCtl,
                          decoration: _fieldDec(
                            label: tikkiTr(context,
                                ar: 'الاسم الكامل',
                                fr: 'Nom complet',
                                en: 'Full name'),
                            icon: Icons.person_outline,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _idCtl,
                          decoration: _fieldDec(
                            label: tikkiTr(context,
                                ar: 'رقم الوثيقة',
                                fr: "Numéro",
                                en: 'Document number'),
                            icon: Icons.confirmation_number_outlined,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notesCtl,
                          maxLines: 3,
                          decoration: _fieldDec(
                            label: tikkiTr(context,
                                ar: 'ملاحظة', fr: 'Note', en: 'Note'),
                            icon: Icons.notes_outlined,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _submitting ? null : () => _submit(ui),
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(tikkiTr(context,
                        ar: 'إرسال الطلب', fr: 'Envoyer', en: 'Submit')),
              ),
            ],
          );
        },
        loading: () => const Center(
            child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator())),
        error: (e, _) => Center(child: Text(e.toString())),
      ),
    );
  }
}
