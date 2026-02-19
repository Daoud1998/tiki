import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/support_contacts.dart';
import '../../../core/data/ma_catalog.dart';
import '../../../core/data/ma_suggestions.dart';
import '../../../core/data/ma_model_suggestions.dart';
import '../../../core/data/ma_neighborhood_suggestions.dart';
import '../../../core/storage/local_store.dart';
import '../../../core/state/auth_state.dart';
import '../../../core/data/publish_taxonomy.dart';
import '../../../core/data/country_codes.dart';
import '../../kyc/data/kyc_settings_repository.dart' as kyc_settings;
import '../../kyc/domain/kyc_models.dart' as kyc_models;
import '../../kyc/state/kyc_controller.dart' as kyc_state;

import '../../notifications/domain/app_notification.dart';
import '../../notifications/presentation/notifications_controller.dart';
import '../../product/data/products_repository.dart';
import '../../product/domain/app_product.dart';
import 'domain/publish_draft.dart';
import 'publish_drafts_controller.dart';

// UI helper for localized labels stored as L10n3.
extension L10n3UiX on L10n3 {
  String tr(BuildContext context) => of(context);
}

class PublishWizardScreen extends ConsumerStatefulWidget {
  const PublishWizardScreen({super.key, this.draftId});

  /// If provided, the wizard loads/saves a resumable local draft.
  final String? draftId;

  @override
  ConsumerState<PublishWizardScreen> createState() =>
      _PublishWizardScreenState();
}

class _PublishWizardScreenState extends ConsumerState<PublishWizardScreen> {
  bool _submitting = false;

  final _pageCtl = PageController();
  int _step = 0;
  static const int _maxStep = 5;

  // Form keys
  final _basicKey = GlobalKey<FormState>();
  final _contactKey = GlobalKey<FormState>();
  final _locationKey = GlobalKey<FormState>();
  final _categoryKey = GlobalKey<FormState>();

  // Controllers
  final _titleCtl = TextEditingController();
  final _detailsCtl = TextEditingController();
  final _priceCtl = TextEditingController();
  final _neighborhoodCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _subOtherCtl = TextEditingController();
  final _typeOtherCtl = TextEditingController();
  final _modelCtl = TextEditingController();
  final _languagesOtherCtl = TextEditingController();
  final _skillsOtherCtl = TextEditingController();

  static const SubCategory _otherSub = SubCategory(
      id: 'other', name: L10n3(ar: 'أخرى', fr: 'Autre', en: 'Other'));

  // Selection
  CategoryNode? _category;
  SubCategory? _subCategory;
  Wilaya? _wilaya;
  Moughataa? _moughataa;

  // Outside Mauritania publishing (for diaspora)
  bool _outsideMa = false;
  CountryCode? _outsideCountry;
  final _outsideCityCtl = TextEditingController();
  final _locationNoteCtl = TextEditingController();

  // Contact
  bool _allowWhatsApp = true;
  bool _allowCall = true;

  // Delivery (optional)
  bool _deliveryEnabled = false;
  final _deliveryFeeCtl = TextEditingController();
  final _deliveryNoteCtl = TextEditingController();

  // Media
  final List<String> _images = <String>[]; // local file paths

  // Smart fields (optional)
  final Map<String, String> _attrs = <String, String>{};

  // Warranty (optional)
  bool _hasWarranty = false;

  // Flexible warranty duration: value + unit (hours/days/weeks/months)
  int _warrantyValue = 0;
  String _warrantyUnit = 'months';
  bool _warrantyCustom = false;
  final _warrantyCustomValueCtl = TextEditingController();

  String _warrantyType = 'seller'; // seller | brand

  // VIP / Promo (optional)
  bool _vipRequested = false;
  String _vipTier = 'boost'; // boost | featured | top
  int _vipDays = 7;

  final _picker = ImagePicker();

  // Edit mode
  AppProduct? _editing;
  bool _prefilled = false;
  Locale? _lastLocale;

  // Draft persistence
  Timer? _autosaveTimer;
  bool _loadingDraft = false;
  bool _savingDraft = false;

  // Option A behavior: we hide fields when category changes, but we don't
  // wipe unrelated values in memory. Only the saved payload is sanitized.

  @override
  void initState() {
    super.initState();
    // Prefill phone from auth state.
    final a = ref.read(authControllerProvider);
    if ((a.phoneE164 ?? '').trim().isNotEmpty) {
      _phoneCtl.text = a.phoneE164!.trim();
    }

    // Draft auto-save (debounced)
    for (final ctl in <TextEditingController>[
      _titleCtl,
      _detailsCtl,
      _priceCtl,
      _neighborhoodCtl,
      _phoneCtl,
      _subOtherCtl,
      _typeOtherCtl,
      _outsideCityCtl,
      _locationNoteCtl,
      _modelCtl,
      _languagesOtherCtl,
      _skillsOtherCtl,
      _deliveryFeeCtl,
      _deliveryNoteCtl,
      _warrantyCustomValueCtl,
    ]) {
      ctl.addListener(_scheduleAutosave);
    }

    // Keep "Other" texts in sync with selected chips.
    _languagesOtherCtl.addListener(_syncMultiOtherTextToAttrs);
    _skillsOtherCtl.addListener(_syncMultiOtherTextToAttrs);

    // Read extra after first frame (GoRouter state is available then).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final extra = GoRouterState.of(context).extra;
      final draftId = (widget.draftId ?? '').trim();
      if (draftId.isNotEmpty) {
        _loadDraft(draftId, extra);
        return;
      }
      if (extra is AppProduct) {
        _editing = extra;
        _prefillFromProduct(extra);
        _scheduleAutosave();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = Localizations.localeOf(context);
    if (_lastLocale == loc) return;
    _lastLocale = loc;

    // When the user switches AR/FR/EN, normalize stored attrs again so
    // we never keep localized strings in the saved payload.
    final before = Map<String, String>.from(_attrs);
    _normalizeAttrsForSelection();
    if (!mapEquals(before, _attrs)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _setStateAndSave(() {});
      });
    }
  }

  void _setStateAndSave(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    _scheduleAutosave();
  }

  void _scheduleAutosave() {
    final id = (widget.draftId ?? '').trim();
    if (id.isEmpty) return;
    if (_loadingDraft) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 650), () {
      _saveDraftNow(id);
    });
  }

  Future<bool> _ensureKycAllowed() async {
    // If KYC feature is not available yet (no settings), default to allowed.
    kyc_models.KycSettings settings;
    try {
      settings = await ref.read(kyc_settings.kycSettingsProvider.future);
    } catch (_) {
      return true;
    }

    final local = ref.read(kyc_state.kycControllerProvider);
    final price = _parsePrice();

    final decision = kyc_models.KycPolicy.decide(
      settings: settings,
      categoryId: _category?.id,
      priceMru: price > 0 ? price : null,
      publishedCount: local.myPublishCount,
      kycStatus: local.status,
    );

    if (!decision.required) return true;
    if (!mounted) return false;

    // New behavior: allow publishing, but the listing may go "pending" for review.
    // Offer the user to verify for instant publishing.
    final choice = await showDialog<String>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: Text(_tr(
                ar: 'الحساب غير موثّق',
                fr: 'Compte non vérifié',
                en: 'Unverified account',
              )),
              content: Text(_tr(
                ar: '''يمكنك نشر الإعلان الآن، لكن سيتم إرساله للمراجعة ولن يظهر للناس حتى تتم الموافقة عليه من الإدارة.
وثّق حسابك ليتم نشر إعلاناتك مباشرة بدون مراجعة.''',
                fr: '''Vous pouvez publier maintenant, mais l'annonce sera envoyée en validation et ne sera visible qu'après approbation.
Vérifiez votre compte pour publier instantanément.''',
                en: '''You can publish now, but your listing will be sent for review and won't be visible until approved.
Verify your account to publish instantly.''',
              )),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop('cancel'),
                  child: Text(_tr(ar: 'إلغاء', fr: 'Annuler', en: 'Cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop('continue'),
                  child: Text(_tr(
                    ar: 'متابعة وإرسال للمراجعة',
                    fr: 'Continuer (validation)',
                    en: 'Continue (review)',
                  )),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop('verify'),
                  child:
                      Text(_tr(ar: 'توثيق الآن', fr: 'Vérifier', en: 'Verify')),
                ),
              ],
            );
          },
        ) ??
        'cancel';

    if (choice == 'continue') return true;
    if (choice == 'verify' && mounted) {
      context.push('/you/verify');
    }
    return false;
  }

  Future<void> _saveDraftNow(String id) async {
    if (!mounted) return;
    final draftId = id.trim();
    if (draftId.isEmpty) return;

    // Prevent aggressive loops while we are applying a draft.
    if (_loadingDraft) return;

    final ctl = ref.read(publishDraftsControllerProvider.notifier);
    await ctl.load();

    // Normalize again so we never store localized labels.
    _normalizeAttrsForSelection();

    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = ctl.byId(draftId);

    final mode = _editing == null ? 'create' : 'edit';
    final targetId = _editing?.id ?? existing?.targetId;

    final draft = PublishDraft(
      id: draftId,
      kind: existing?.kind ?? 'product',
      mode: mode,
      targetId: targetId,
      name: existing?.name,
      step: _step,
      createdAtMs: existing?.createdAtMs ?? now,
      updatedAtMs: now,
      schemaVersion: (existing?.schemaVersion ?? 1) < 2
          ? 2
          : (existing?.schemaVersion ?? 1),
      data: _buildDraftData(),
    );

    if (mounted) {
      setState(() {
        _savingDraft = true;
      });
    }
    await ctl.upsert(draft);
    if (!mounted) return;
    setState(() {
      _savingDraft = false;
    });
  }

  Future<void> _loadDraft(String id, Object? extra) async {
    final draftId = id.trim();
    if (draftId.isEmpty) return;

    setState(() {
      _loadingDraft = true;
    });

    final ctl = ref.read(publishDraftsControllerProvider.notifier);
    await ctl.load();
    PublishDraft? d = ctl.byId(draftId);

    // If the draft is missing for some reason, create a blank one.
    if (d == null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      d = PublishDraft(
        id: draftId,
        kind: 'product',
        mode: (extra is AppProduct) ? 'edit' : 'create',
        targetId: (extra is AppProduct) ? extra.id : null,
        name: null,
        step: 0,
        createdAtMs: now,
        updatedAtMs: now,
        schemaVersion: 2,
        data: const <String, dynamic>{},
      );
      await ctl.upsert(d);
    }

    _applyDraft(d);

    // If this is an edit draft and we didn't receive the product object as `extra`,
    // fetch it from Firestore once so the wizard can update instead of creating.
    final targetId = (d.targetId ?? '').trim();
    if (d.mode == 'edit' && targetId.isNotEmpty && _editing == null) {
      try {
        final repo = ref.read(productsRepositoryProvider);
        final prod = await repo.getById(targetId);
        if (mounted && prod != null) {
          setState(() => _editing = prod);
        }
      } catch (_) {
        // ignore
      }
    }

    if (extra is AppProduct && d.mode == 'edit' && _editing == null) {
      // Safety: if draft is edit-mode but target product isn't loaded.
      _editing = extra;
      _prefillFromProduct(extra);
    }

    if (!mounted) return;
    setState(() {
      _loadingDraft = false;
    });

    await ctl.setLastDraftId(draftId);
    _scheduleAutosave();
  }

  void _applyDraft(PublishDraft draft) {
    final d = draft.data;

    // Editing target: handled by `_loadOrCreateDraft` (load from Firestore) or via `extra`.

    _titleCtl.text = (d['title'] ?? '').toString();
    _detailsCtl.text = (d['details'] ?? '').toString();
    _priceCtl.text = (d['price'] ?? '').toString();
    _neighborhoodCtl.text = (d['neighborhood'] ?? '').toString();
    _phoneCtl.text = (d['phone'] ?? '').toString();

    _subOtherCtl.text = (d['subOther'] ?? '').toString();
    _typeOtherCtl.text = (d['typeOther'] ?? '').toString();
    _modelCtl.text = (d['model'] ?? '').toString();
    _languagesOtherCtl.text = (d['languagesOther'] ?? '').toString();
    _skillsOtherCtl.text = (d['skillsOther'] ?? '').toString();
    _outsideCityCtl.text = (d['outsideCity'] ?? '').toString();
    _locationNoteCtl.text = (d['locationNote'] ?? '').toString();

    _allowWhatsApp = _toBool(d['allowWhatsApp'], fallback: true);
    _allowCall = _toBool(d['allowCall'], fallback: true);
    _vipRequested = _toBool(d['vipRequested'], fallback: false);

    final tierRaw = (d['vipTier'] ?? '').toString().trim();
    if (tierRaw.isNotEmpty) _vipTier = tierRaw;

    final daysRaw = (d['vipDays'] ?? '').toString().trim();
    final parsedDays = int.tryParse(daysRaw);
    if (parsedDays != null && parsedDays > 0) _vipDays = parsedDays;

// Legacy drafts: vipPlanId like vip_7d
    final legacy = (d['vipPlanId'] ?? '').toString().trim().toLowerCase();
    if (legacy.isNotEmpty && (tierRaw.isEmpty || parsedDays == null)) {
      if (legacy.startsWith('top_')) {
        _vipTier = 'top';
      } else if (legacy.startsWith('featured_')) {
        _vipTier = 'featured';
      } else {
        _vipTier = 'boost';
      }
      final m = RegExp(r'(\d+)d').firstMatch(legacy);
      if (m != null) _vipDays = int.tryParse(m.group(1) ?? '') ?? _vipDays;
    }

    _hasWarranty = _toBool(d['hasWarranty'], fallback: false);

    final wVal = _toInt(d['warrantyValue'], fallback: 0);
    final wUnitRaw = (d['warrantyUnit'] ?? '').toString().trim().toLowerCase();
    final legacyMonths = _toInt(d['warrantyMonths'], fallback: 0);

    _warrantyType = (d['warrantyType'] ?? 'seller').toString();

    if (_hasWarranty) {
      if (wVal > 0 && {'hours', 'days', 'weeks', 'months'}.contains(wUnitRaw)) {
        _warrantyValue = wVal;
        _warrantyUnit = wUnitRaw;
      } else if (legacyMonths > 0) {
        _warrantyValue = legacyMonths;
        _warrantyUnit = 'months';
      } else {
        _warrantyValue = 0;
        _warrantyUnit = 'months';
      }
      _warrantyCustom = _isWarrantyCustom(_warrantyValue, _warrantyUnit);
      _warrantyCustomValueCtl.text =
          _warrantyValue > 0 ? _warrantyValue.toString() : '';
    } else {
      _warrantyValue = 0;
      _warrantyUnit = 'months';
      _warrantyCustom = false;
      _warrantyCustomValueCtl.text = '';
    }

    _outsideMa = _toBool(d['outsideMa'], fallback: false);

    final outsideIso2 = (d['outsideCountryIso2'] ?? '').toString().trim();
    _outsideCountry = outsideIso2.isEmpty
        ? null
        : kCountryCodes.where((c) => c.iso2 == outsideIso2).isNotEmpty
            ? kCountryCodes.firstWhere((c) => c.iso2 == outsideIso2)
            : null;

    // Images
    _images
      ..clear()
      ..addAll(_asStringList(d['images']));

    // Category + subcategory
    final catAny = (d['categoryId'] ?? '').toString();
    final subAny = (d['subCategoryId'] ?? '').toString();
    final catId = resolveCategoryIdAny(catAny);
    CategoryNode? cat;
    if (catId != null && catId.isNotEmpty) {
      for (final c in maCategories) {
        if (c.id == catId) {
          cat = c;
          break;
        }
      }
    }
    _category = cat;

    final subId = resolveSubCategoryIdAny(subAny);
    if (_category != null && subId != null && subId.isNotEmpty) {
      final subs = withOtherSubcategory(_category!.sub);
      _subCategory = subs.cast<SubCategory?>().firstWhere(
            (s) => (s?.id ?? '') == subId,
            orElse: () => null,
          );
    } else {
      _subCategory = null;
    }

    // Local location
    final wilayaId = (d['wilayaId'] ?? '').toString().trim();
    final moughataaId = (d['moughataaId'] ?? '').toString().trim();

    if (!_outsideMa) {
      _wilaya = wilayaId.isEmpty
          ? null
          : maWilayas.cast<Wilaya?>().firstWhere(
                (w) => (w?.id ?? '') == wilayaId,
                orElse: () => null,
              );
      if (_wilaya != null && moughataaId.isNotEmpty) {
        _moughataa = _wilaya!.moughataas.cast<Moughataa?>().firstWhere(
              (m) => (m?.id ?? '') == moughataaId,
              orElse: () => null,
            );
      } else {
        _moughataa = null;
      }
    } else {
      _wilaya = null;
      _moughataa = null;
    }

    // attrs map
    final attrs = <String, String>{};
    final rawAttrs = d['attrs'];
    if (rawAttrs is Map) {
      for (final e in rawAttrs.entries) {
        final k = (e.key ?? '').toString().trim();
        if (k.isEmpty) continue;
        attrs[k] = (e.value ?? '').toString();
      }
    }
    _attrs
      ..clear()
      ..addAll(attrs);

    // Delivery
    _deliveryEnabled = ((_attrs['delivery_enabled'] ?? '').trim() == 'true');
    if (!_deliveryApplicable()) {
      _deliveryEnabled = false;
      _deliveryFeeCtl.text = '';
      _deliveryNoteCtl.text = '';
      _attrs['delivery_enabled'] = 'false';
      _attrs.remove('delivery_fee_mru');
      _attrs.remove('delivery_note');
    }
    _deliveryFeeCtl.text = (_attrs['delivery_fee_mru'] ?? '').trim();
    _deliveryNoteCtl.text = (_attrs['delivery_note'] ?? '').trim();

    // Force sanitization after apply.
    _normalizeAttrsForSelection();

    // Restore wizard step.
    // Important: Always start from Category (step 0) so the user can confirm
    // category/subcategory before photos & other fields (and to compute limits).
    _step = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _goTo(0);
    });
  }

  Map<String, dynamic> _buildDraftData() {
    // Ensure UI fields that live inside attrs are synced before saving.
    _syncDeliveryAttrs();
    return <String, dynamic>{
      'title': _titleCtl.text,
      'details': _detailsCtl.text,
      'price': _priceCtl.text,
      'neighborhood': _neighborhoodCtl.text,
      'phone': _phoneCtl.text,
      'allowWhatsApp': _allowWhatsApp,
      'allowCall': _allowCall,
      'hasWarranty': _hasWarranty,
      'warrantyValue': _warrantyValue,
      'warrantyUnit': _warrantyUnit,
      // legacy (months-only) key for backward compatibility
      'warrantyMonths': _warrantyUnit == 'months' ? _warrantyValue : 0,
      'warrantyType': _warrantyType,
      'warrantyCustom': _warrantyCustom,
      'categoryId': _category?.id,
      'subCategoryId': _subCategory?.id,
      'subOther': _subOtherCtl.text,
      'typeOther': _typeOtherCtl.text,
      'model': _modelCtl.text,
      'languagesOther': _languagesOtherCtl.text,
      'skillsOther': _skillsOtherCtl.text,
      'outsideMa': _outsideMa,
      'outsideCountryIso2': _outsideCountry?.iso2,
      'outsideCity': _outsideCityCtl.text,
      'locationNote': _locationNoteCtl.text,
      'wilayaId': _wilaya?.id,
      'moughataaId': _moughataa?.id,
      'images': List<String>.from(_images),
      'attrs': Map<String, String>.from(_attrs),
      'vipRequested': _vipRequested,
      'vipTier': _vipTier,
      'vipDays': _vipDays,
    };
  }

  static bool _toBool(dynamic v, {required bool fallback}) {
    if (v is bool) return v;
    final s = (v ?? '').toString().toLowerCase().trim();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return fallback;
  }

  static int _toInt(dynamic v, {required int fallback}) {
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? fallback;
  }

  static List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => (e ?? '').toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  void _prefillFromProduct(AppProduct p) {
    if (_prefilled) return;
    _prefilled = true;
    _titleCtl.text = p.title;
    _detailsCtl.text = p.details ?? (p.description ?? '');
    _priceCtl.text = p.price > 0 ? p.price.toString() : '';
    _neighborhoodCtl.text = p.neighborhood;
    _phoneCtl.text = (p.phone ?? '').trim();
    _allowWhatsApp = p.allowWhatsApp;
    _allowCall = p.allowCall;

    // Warranty + quick attrs
    _hasWarranty = p.hasWarranty;
    _warrantyValue = (p.hasWarranty ? (p.warrantyValue ?? 0) : 0);
    _warrantyUnit =
        ((p.warrantyUnit ?? 'months').toString().trim().toLowerCase());
    if (_warrantyUnit.isEmpty) _warrantyUnit = 'months';
    _warrantyType = (p.warrantyType ?? 'seller');
    _warrantyCustom =
        _hasWarranty && _isWarrantyCustom(_warrantyValue, _warrantyUnit);
    _warrantyCustomValueCtl.text =
        _warrantyValue > 0 ? _warrantyValue.toString() : '';
    _attrs
      ..clear()
      ..addAll(p.attrs);

    final _ps = (p.attrs['promo_status'] ?? '').toString().trim();
    _vipRequested = (_ps == 'pending' || _ps == 'approved');

    final _pkg =
        (p.attrs['promo_pkg_id'] ?? '').toString().trim().toLowerCase();
    final _daysRaw = (p.attrs['promo_days'] ?? '').toString().trim();
    final days = int.tryParse(_daysRaw) ?? 0;

    if (_pkg.isNotEmpty) {
      if (_pkg.startsWith('top_')) {
        _vipTier = 'top';
      } else if (_pkg.startsWith('featured_')) {
        _vipTier = 'featured';
      } else {
        _vipTier = 'boost';
      }

      if (days > 0) {
        _vipDays = days;
      } else {
        final m = RegExp(r'(\d+)d').firstMatch(_pkg);
        if (m != null) _vipDays = int.tryParse(m.group(1) ?? '') ?? _vipDays;
      }
    }

    // Delivery
    _deliveryEnabled = ((_attrs['delivery_enabled'] ?? '').trim() == 'true');
    if (!_deliveryApplicable()) {
      _deliveryEnabled = false;
      _deliveryFeeCtl.text = '';
      _deliveryNoteCtl.text = '';
      _attrs['delivery_enabled'] = 'false';
      _attrs.remove('delivery_fee_mru');
      _attrs.remove('delivery_note');
    }
    _deliveryFeeCtl.text = (_attrs['delivery_fee_mru'] ?? '').trim();
    _deliveryNoteCtl.text = (_attrs['delivery_note'] ?? '').trim();

    // Custom "Other" fields (kept as-is, not auto-translated).
    _subOtherCtl.text = (_attrs['sub_other'] ?? '').trim();
    _typeOtherCtl.text = (_attrs['type_other'] ?? '').trim();
    _modelCtl.text = (_attrs['model'] ?? '').trim();
    _languagesOtherCtl.text = (_attrs['languages_other'] ?? '').trim();
    _skillsOtherCtl.text = (_attrs['skills_other'] ?? '').trim();

    // Media
    _images
      ..clear()
      ..addAll(p.images);

    // Category selection
    if ((p.category ?? '').isNotEmpty) {
      _category = maCategories
          .cast<CategoryNode?>()
          .firstWhere((c) => c!.id == p.category, orElse: () => null);
    }
    if (_category != null && (p.subCategory ?? '').isNotEmpty) {
      final sid = (p.subCategory ?? '').trim();
      if (sid == _otherSub.id) {
        _subCategory = _otherSub;
      } else {
        _subCategory = _category!.sub
            .cast<SubCategory?>()
            .firstWhere((s) => s!.id == sid, orElse: () => null);
      }
    }

    // Location selection
    _outsideMa = false;
    _outsideCountry = null;
    _outsideCityCtl.text = '';
    _locationNoteCtl.text = (_attrs['location_note'] ?? '').trim();

    final iso2 = (_attrs['outside_country_iso2'] ?? '').trim().toUpperCase();
    final outsideFlag =
        ((_attrs['outside_ma'] ?? '').trim() == 'true') || iso2.isNotEmpty;

    if (outsideFlag) {
      _outsideMa = true;
      if (iso2.isNotEmpty) {
        _outsideCountry = kCountryCodes.cast<CountryCode?>().firstWhere(
              (c) => c!.iso2 == iso2,
              orElse: () => null,
            );
      }

      if (_outsideCountry == null) {
        final name = p.wilaya.trim();
        if (name.isNotEmpty) {
          _outsideCountry = kCountryCodes.cast<CountryCode?>().firstWhere(
                (c) =>
                    c!.nameAr == name || c.nameFr == name || c.nameEn == name,
                orElse: () => null,
              );
        }
      }

      _outsideCityCtl.text = (_attrs['outside_city'] ?? '').trim().isNotEmpty
          ? (_attrs['outside_city'] ?? '').trim()
          : p.neighborhood;

      _wilaya = null;
      _moughataa = null;
    } else {
      // Match MR wilaya/moughataa.
      // Prefer stable ids if present (newer listings), then fall back to stored labels (older listings).
      final wid = (_attrs['wilaya_id'] ?? '').trim();
      final mid = (_attrs['moughataa_id'] ?? '').trim();

      _wilaya = (wid.isNotEmpty)
          ? maWilayas
              .cast<Wilaya?>()
              .firstWhere((w) => w!.id == wid, orElse: () => null)
          : null;

      // Back-compat: some old mock items stored a city label (e.g. 'نواكشوط', 'نواذيبو') or localized wilaya label.
      _wilaya ??= maWilayas.cast<Wilaya?>().firstWhere(
            (w) =>
                w!.id == p.wilaya ||
                w.name.ar == p.wilaya ||
                w.name.fr == p.wilaya ||
                w.name.en == p.wilaya,
            orElse: () => null,
          );

      if (_wilaya != null) {
        _moughataa = (mid.isNotEmpty)
            ? _wilaya!.moughataas.cast<Moughataa?>().firstWhere(
                  (m) => m!.id == mid,
                  orElse: () => null,
                )
            : null;

        _moughataa ??= _wilaya!.moughataas.cast<Moughataa?>().firstWhere(
              (m) =>
                  m!.id == p.moughataa ||
                  m.name.ar == p.moughataa ||
                  m.name.fr == p.moughataa ||
                  m.name.en == p.moughataa,
              orElse: () => null,
            );
      }
    }

    _normalizeAttrsForSelection();
    setState(() {});
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _pageCtl.dispose();
    _titleCtl.dispose();
    _detailsCtl.dispose();
    _priceCtl.dispose();
    _neighborhoodCtl.dispose();
    _phoneCtl.dispose();
    _subOtherCtl.dispose();
    _typeOtherCtl.dispose();
    _outsideCityCtl.dispose();
    _locationNoteCtl.dispose();
    _modelCtl.dispose();
    _languagesOtherCtl.dispose();
    _skillsOtherCtl.dispose();
    _deliveryFeeCtl.dispose();
    _deliveryNoteCtl.dispose();
    _warrantyCustomValueCtl.dispose();
    super.dispose();
  }

  String _tr({required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'fr') return fr;
    if (code == 'en') return en;
    return ar;
  }

  String _warrantyLabel(int value, String unit) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    final u = unit.trim().toLowerCase();
    String arUnit(int v) {
      if (u == 'hours') return v == 1 ? 'ساعة' : 'ساعة';
      if (u == 'days') return v == 1 ? 'يوم' : 'يوم';
      if (u == 'weeks') return v == 1 ? 'أسبوع' : 'أسابيع';
      return v == 1 ? 'شهر' : 'شهر';
    }

    String frUnit(int v) {
      if (u == 'hours') return v == 1 ? 'heure' : 'heures';
      if (u == 'days') return v == 1 ? 'jour' : 'jours';
      if (u == 'weeks') return v == 1 ? 'semaine' : 'semaines';
      return v == 1 ? 'mois' : 'mois';
    }

    String enUnit(int v) {
      if (u == 'hours') return v == 1 ? 'hour' : 'hours';
      if (u == 'days') return v == 1 ? 'day' : 'days';
      if (u == 'weeks') return v == 1 ? 'week' : 'weeks';
      return v == 1 ? 'month' : 'months';
    }

    if (code == 'fr') return '$value ${frUnit(value)}';
    if (code == 'en') return '$value ${enUnit(value)}';
    return '$value ${arUnit(value)}';
  }

  bool _isWarrantyCustom(int value, String unit) {
    final u = unit.trim().toLowerCase();
    final presets = <String>{
      'hours:24',
      'weeks:1',
      'months:1',
      'months:3',
      'months:6',
      'months:12',
    };
    return !presets.contains('$u:$value');
  }

  List<String> _warrantyUnitOrder() =>
      const ['hours', 'days', 'weeks', 'months'];

  String _warrantyUnitUiLabel(String unit) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    final u = unit.trim().toLowerCase();
    if (code == 'fr') {
      if (u == 'hours') return 'Heures';
      if (u == 'days') return 'Jours';
      if (u == 'weeks') return 'Semaines';
      return 'Mois';
    }
    if (code == 'en') {
      if (u == 'hours') return 'Hours';
      if (u == 'days') return 'Days';
      if (u == 'weeks') return 'Weeks';
      return 'Months';
    }
    if (u == 'hours') return 'ساعات';
    if (u == 'days') return 'أيام';
    if (u == 'weeks') return 'أسابيع';
    return 'أشهر';
  }

  bool _deliveryApplicable() {
    final cat = (_category?.id ?? '').trim().toLowerCase();
    final sub = (_subCategory?.id ?? '').trim().toLowerCase();

    // Primary rules (human-like): services, jobs, real-estate do not ship.
    if (cat == 'services' || cat == 'jobs' || cat == 'real_estate')
      return false;

    // Defensive rules (in case ids change/mismatch)
    if (cat.contains('service') ||
        cat.contains('job') ||
        cat.contains('real_estate')) return false;
    if (sub.startsWith('jobs_') ||
        sub.contains('service') ||
        sub.contains('real_estate')) return false;

    return true;
  }

  Set<String> _primaryQuickKeys({
    required PublishKind kind,
    required String? categoryId,
    required String? subCategoryId,
  }) {
    final cat = (categoryId ?? '').trim().toLowerCase();
    final sub = (subCategoryId ?? '').trim().toLowerCase();

    // Cars / vehicles
    if (sub == 'car' || sub.contains('car') || cat.contains('auto')) {
      return <String>{
        'condition',
        'year',
        'mileage_km',
        'fuel',
        'transmission',
        'origin',
        'paper',
      };
    }

    // Real estate
    if (cat == 'real_estate' ||
        sub == 'apartment' ||
        sub == 'house' ||
        sub == 'land' ||
        sub.contains('apartment') ||
        sub.contains('house')) {
      return <String>{'rooms', 'area_m2', 'furnished'};
    }

    // Jobs
    if (cat == 'jobs' || sub.startsWith('jobs_') || sub.contains('job')) {
      return <String>{
        'contract',
        'experience',
        'work_mode',
        'availability',
        'education',
        'languages',
        'license',
        'company',
      };
    }

    // Phones / electronics (best-effort)
    if (sub.contains('phone') ||
        sub.contains('laptop') ||
        sub.contains('computer') ||
        sub.contains('tablet') ||
        cat.contains('elect')) {
      return <String>{'condition', 'storage', 'ram', 'color', 'compatibility'};
    }

    // Clothing / fashion
    if (sub.contains('clo') ||
        sub.contains('shoe') ||
        cat.contains('fashion')) {
      return <String>{'size', 'color', 'fabric'};
    }

    // Default: keep empty (means: show everything without splitting)
    return const <String>{};
  }

  Set<String> _selectedLanguageIds() {
    final raw = (_attrs['languages'] ?? '').trim();
    if (raw.isEmpty) return <String>{};
    return raw
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  void _setSelectedLanguageIds(Set<String> ids) {
    final cleaned =
        ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    cleaned.sort();
    if (cleaned.isEmpty) {
      _attrs.remove('languages');
    } else {
      _attrs['languages'] = cleaned.join('|');
    }
  }

  Set<String> _selectedSkillIds() {
    final raw = (_attrs['skills'] ?? '').trim();
    if (raw.isEmpty) return <String>{};
    return raw
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  void _setSelectedSkillIds(Set<String> ids) {
    final cleaned =
        ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    cleaned.sort();
    if (cleaned.isEmpty) {
      _attrs.remove('skills');
    } else {
      _attrs['skills'] = cleaned.join('|');
    }
  }

  List<L10n3> _defaultJobSkills() {
    return <L10n3>[
      L10n3(ar: 'خدمة العملاء', fr: 'Service client', en: 'Customer service'),
      L10n3(ar: 'مبيعات', fr: 'Vente', en: 'Sales'),
      L10n3(ar: 'محاسبة', fr: 'Comptabilité', en: 'Accounting'),
      L10n3(ar: 'Word', fr: 'Word', en: 'Word'),
      L10n3(ar: 'Excel', fr: 'Excel', en: 'Excel'),
      L10n3(ar: 'تصميم', fr: 'Design', en: 'Design'),
      L10n3(ar: 'سياقة', fr: 'Conduite', en: 'Driving'),
      L10n3(ar: 'طبخ', fr: 'Cuisine', en: 'Cooking'),
      L10n3(ar: 'حراسة', fr: 'Sécurité', en: 'Security'),
      L10n3(ar: 'تدريس', fr: 'Enseignement', en: 'Teaching'),
      L10n3(ar: 'صيانة', fr: 'Maintenance', en: 'Maintenance'),
      L10n3(ar: 'برمجة', fr: 'Programmation', en: 'Programming'),
      L10n3(ar: 'أخرى', fr: 'Autre', en: 'Other'),
    ];
  }

  List<L10n3> _expandLanguageOptions(List<L10n3> base) {
    final cat = (_category?.id ?? '').trim().toLowerCase();
    final sub = (_subCategory?.id ?? '').trim().toLowerCase();
    final isJobs = cat == 'jobs' || sub.startsWith('jobs_');
    if (!isJobs) return base;

    final extras = <L10n3>[
      L10n3(ar: 'البولارية', fr: 'Pulaar', en: 'Pulaar'),
      L10n3(ar: 'السوننكية', fr: 'Soninké', en: 'Soninke'),
      L10n3(ar: 'الولوفية', fr: 'Wolof', en: 'Wolof'),
    ];

    final byId = <String, L10n3>{};
    for (final o in base) {
      byId[o.en] = o;
    }
    for (final e in extras) {
      byId.putIfAbsent(e.en, () => e);
    }

    // Prefer a human order, then add any remaining values.
    final order = <String>[
      'Arabic',
      'French',
      'English',
      'Pulaar',
      'Soninke',
      'Wolof',
      'Other',
    ];
    final out = <L10n3>[];
    for (final id in order) {
      final v = byId[id];
      if (v != null) out.add(v);
    }
    for (final e in byId.entries) {
      if (!order.contains(e.key)) out.add(e.value);
    }
    return out;
  }

  void _syncDeliveryAttrs() {
    if (!_deliveryApplicable()) {
      _deliveryEnabled = false;
      _deliveryFeeCtl.text = '';
      _deliveryNoteCtl.text = '';
      _attrs['delivery_enabled'] = 'false';
      _attrs.remove('delivery_fee_mru');
      _attrs.remove('delivery_note');
      return;
    }

    // Persist delivery choices inside attrs so they survive drafts.
    _attrs['delivery_enabled'] = _deliveryEnabled ? 'true' : 'false';

    if (!_deliveryEnabled) {
      _attrs.remove('delivery_fee_mru');
      _attrs.remove('delivery_note');
      return;
    }

    final fee = _deliveryFeeCtl.text.trim();
    if (fee.isEmpty) {
      _attrs.remove('delivery_fee_mru');
    } else {
      _attrs['delivery_fee_mru'] = fee;
    }

    final note = _deliveryNoteCtl.text.trim();
    if (note.isEmpty) {
      _attrs.remove('delivery_note');
    } else {
      _attrs['delivery_note'] = note;
    }
  }

  void _syncMultiOtherTextToAttrs() {
    // Languages "Other" text
    final langIds = _selectedLanguageIds();
    final langOther = _languagesOtherCtl.text.trim();
    if (langIds.contains('Other') && langOther.isNotEmpty) {
      _attrs['languages_other'] = langOther;
    } else {
      _attrs.remove('languages_other');
    }

    // Skills "Other" text
    final skillIds = _selectedSkillIds();
    final skillOther = _skillsOtherCtl.text.trim();
    if (skillIds.contains('Other') && skillOther.isNotEmpty) {
      _attrs['skills_other'] = skillOther;
    } else {
      _attrs.remove('skills_other');
    }
  }

  TextInputType? _keyboardTypeForQuickKey(String key) {
    // Keep input friendly: numeric keyboard for numeric fields.
    const numericKeys = <String>{
      'year',
      'mileage_km',
      'area_m2',
      'delivery_fee_mru',
      'rooms',
    };
    if (numericKeys.contains(key)) return TextInputType.number;
    if (key.endsWith('_km') || key.endsWith('_m2')) return TextInputType.number;
    return null;
  }

  Widget _quickFieldWidget(QuickFieldDef q) {
    if (q.key == 'languages') {
      return _LanguagesMultiField(
        label: q.label.of(context),
        options: _expandLanguageOptions(q.options),
        selectedIds: _selectedLanguageIds(),
        otherController: _languagesOtherCtl,
        onChanged: (ids) => _setStateAndSave(() {
          _setSelectedLanguageIds(ids);
          _syncMultiOtherTextToAttrs();
        }),
      );
    }

    if (q.key == 'year') {
      return _YearDropdownField(
        label: q.label.of(context),
        value: (_attrs['year'] ?? '').trim(),
        onChanged: (v) => _setStateAndSave(() {
          final s = (v ?? '').trim();
          if (s.isEmpty) {
            _attrs.remove('year');
          } else {
            _attrs['year'] = s;
          }
        }),
      );
    }

    if (q.options.isNotEmpty) {
      return DropdownButtonFormField<String>(
        key: ValueKey('q_${q.key}_${_category?.id}_${_subCategory?.id}'),
        initialValue: _safeId(
          _normalizeStoredOptionToId(_attrs[q.key], q.options),
          q.options,
        ),
        isExpanded: true,
        menuMaxHeight: 320,
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
        items: q.options
            .map((o) => DropdownMenuItem<String>(
                  value: o.en,
                  child: Text(_humanizeOptionLabel(
                      key: q.key, id: o.en, options: q.options)),
                ))
            .toList(growable: false),
        onChanged: (v) => setState(() {
          if (v == null || v.trim().isEmpty) {
            _attrs.remove(q.key);
          } else {
            _attrs[q.key] = v.trim();
          }
        }),
        decoration: _decor(
          label: q.label.of(context),
          prefixIcon: Icon(q.icon),
        ),
      );
    }

    return TextFormField(
      initialValue: _attrs[q.key] ?? '',
      keyboardType: _keyboardTypeForQuickKey(q.key),
      onChanged: (v) => _attrs[q.key] = v.trim(),
      decoration: _decor(
        label: q.label.of(context),
        prefixIcon: Icon(q.icon),
      ),
    );
  }

  /// Normalizes a stored attribute value (possibly saved in AR/FR/EN) into a stable id (EN).
  /// Returns null if the stored value does not match any option.
  String? _normalizeStoredOptionToId(String? stored, List<L10n3> options) {
    if (stored == null) return null;
    final s = stored.trim();
    if (s.isEmpty) return null;
    final sl = s.toLowerCase();
    // Backward-compat: some older builds stored iPhone as a brand option.
    // IMPORTANT: do NOT blindly map iPhone -> Apple for every dropdown.
    // Only do it when the current options contain Apple but *not* iPhone.
    final hasApple = options.any((o) => o.en.toLowerCase() == 'apple');
    final hasIphone = options.any((o) => o.en.toLowerCase() == 'iphone');
    if (sl == 'iphone' || s == 'آيفون') {
      if (hasIphone) return 'iPhone';
      if (hasApple && !hasIphone) return 'Apple';
      // Otherwise: keep searching normally.
    }
    for (final o in options) {
      if (s == o.en || s == o.ar || s == o.fr) return o.en;
      final enl = o.en.toLowerCase();
      final arl = o.ar.toLowerCase();
      final frl = o.fr.toLowerCase();
      if (sl == enl || sl == arl || sl == frl) return o.en;
    }
    return null;
  }

  String? _safeId(String? id, List<L10n3> options) {
    if (id == null) return null;
    return options.any((o) => o.en == id) ? id : null;
  }

  String _labelForOptionId(String id, List<L10n3> options) {
    final cleaned = id.trim();
    if (cleaned.isEmpty) return '';
    for (final o in options) {
      if (o.en == cleaned) return o.of(context);
    }
    return cleaned;
  }

  String _humanizeOptionLabel({
    required String key,
    required String id,
    required List<L10n3> options,
  }) {
    final base = _labelForOptionId(id, options);

    // Rooms: turn "1" into "1 غرفة" (and handle 5+)
    if (key == 'rooms') {
      final s = id.trim();
      if (s == '1') return _tr(ar: '1 غرفة', fr: '1 pièce', en: '1 room');
      if (s == '2') return _tr(ar: '2 غرف', fr: '2 pièces', en: '2 rooms');
      if (s == '3') return _tr(ar: '3 غرف', fr: '3 pièces', en: '3 rooms');
      if (s == '4') return _tr(ar: '4 غرف', fr: '4 pièces', en: '4 rooms');
      if (s == '5+' || s == '5')
        return _tr(ar: '5+ غرف', fr: '5+ pièces', en: '5+ rooms');
      // Otherwise keep localized base.
      return base.isEmpty ? s : base;
    }

    return base;
  }

  void _normalizeAttrsForSelection() {
    // Quick fields (condition, storage, color, etc.)
    final quick = quickFieldsFor(
      context,
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );
    for (final q in quick) {
      // Multi-select fields need per-item normalization (not whole-string).
      if (q.key == 'languages') {
        final raw = (_attrs[q.key] ?? '').toString().trim();
        if (raw.isEmpty) {
          _attrs.remove(q.key);
        } else {
          final opts = _expandLanguageOptions(q.options);
          final parts =
              raw.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty);

          final out = <String>{};
          for (final p in parts) {
            final id = _normalizeStoredOptionToId(p, opts);
            if (id != null) out.add(id);
          }

          if (out.isEmpty) {
            _attrs.remove(q.key);
          } else {
            // Keep a human order when possible.
            final ordered = <String>[];
            for (final o in opts) {
              if (out.contains(o.en)) ordered.add(o.en);
            }
            for (final x in out) {
              if (!ordered.contains(x)) ordered.add(x);
            }
            _attrs[q.key] = ordered.join('|');
          }
        }
        continue;
      }

      if (q.options.isEmpty) continue;
      final id = _normalizeStoredOptionToId(_attrs[q.key], q.options);
      if (id == null) {
        _attrs.remove(q.key);
      } else {
        _attrs[q.key] = id;
      }
    }

    // Skills (multi) may be stored in AR/FR in older drafts, normalize to stable ids.
    final skillRaw = (_attrs['skills'] ?? '').toString().trim();
    if (skillRaw.isNotEmpty) {
      final opts = _defaultJobSkills();
      final parts =
          skillRaw.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty);
      final out = <String>{};
      for (final p in parts) {
        final id = _normalizeStoredOptionToId(p, opts);
        if (id != null) out.add(id);
      }
      if (out.isEmpty) {
        _attrs.remove('skills');
      } else {
        final ordered = <String>[];
        for (final o in opts) {
          if (out.contains(o.en)) ordered.add(o.en);
        }
        for (final x in out) {
          if (!ordered.contains(x)) ordered.add(x);
        }
        _attrs['skills'] = ordered.join('|');
      }
    }

    // Keep *_other keys consistent with selections.
    _syncMultiOtherTextToAttrs();

    // Variant/type
    final vDefs = variantDefsFor(
      context,
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );
    if (vDefs.isNotEmpty) {
      final id = _normalizeStoredOptionToId(_attrs['type'], vDefs);
      if (id == null) {
        _attrs.remove('type');
      } else {
        _attrs['type'] = id;
      }
    } else {
      _attrs.remove('type');
    }

    // Model/series free text (phones/cars)
    final allowModel = supportsModelFieldFor(
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );
    if (!allowModel) {
      _attrs.remove('model');
      _modelCtl.clear();
    } else {
      final v = _modelCtl.text.trim();
      if (v.isEmpty) {
        _attrs.remove('model');
      } else {
        _attrs['model'] = v;
      }
    }
  }

  void _wipeOnCategoryOrSubChange({
    required bool changedMainCategory,
    required bool changedSubCategory,
  }) {
    // Always reset variant/type when taxonomy changes.
    _attrs.remove('type');
    _attrs.remove('type_other');
    _typeOtherCtl.clear();

    // Clear "Other sub" if we are no longer on Other, or main category changed.
    if (changedMainCategory || (_subCategory?.id != _otherSub.id)) {
      _attrs.remove('sub_other');
      _subOtherCtl.clear();
    }

    // Avoid confusing carry-over: clear model on any main category change.
    if (changedMainCategory) {
      _attrs.remove('model');
      _modelCtl.clear();
    }

    // If warranty is not applicable anymore, reset it.
    if (changedMainCategory) {
      _hasWarranty = false;
      _warrantyValue = 0;
      _warrantyType = 'seller';
    }

    // Remove quick-field values that do not belong to the new category/subcategory.
    final allowedQuickKeys = quickFieldsFor(
      context,
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    ).map((q) => q.key).toSet();

    const keepKeys = <String>{
      // Location + meta
      'outside_ma',
      'outside_country_iso2',
      'outside_city',
      'location_note',
      'wilaya_id',
      'moughataa_id',
      'neighborhood_id',
      // Promo/system keys (if any)
      'promo_status',
      'promo_pkg_id',
      'promo_tx_id',
      'promo_req_at_ms',
      'promo_appr_at_ms',
      'promo_until_ms',
      'promo_days',
      'promo_price_mru',
      'promo_tier',
      'promo_rank',
    };

    _attrs.removeWhere((k, v) {
      if (keepKeys.contains(k)) return false;
      if (k == 'type' || k == 'type_other' || k == 'model' || k == 'sub_other')
        return true;
      // Drop anything not explicitly allowed for this selection.
      return !allowedQuickKeys.contains(k);
    });

    // Ensure remaining options are valid (prevents Dropdown crashes).
    _normalizeAttrsForSelection();
  }

  static const String _kManualPick = '__manual__';

  Future<void> _openManualEntry({
    required String title,
    required String hint,
    required String initialValue,
    required void Function(String value) onSaved,
  }) async {
    final ctl = TextEditingController(text: initialValue);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctl,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(_tr(ar: 'إلغاء', fr: 'Annuler', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctl.text.trim()),
              child: Text(_tr(ar: 'حفظ', fr: 'Enregistrer', en: 'Save')),
            ),
          ],
        );
      },
    );

    if (saved == null) return;
    onSaved(saved);
  }

  Future<String?> _openSuggestionPicker({
    required String title,
    required List<MaSuggestion> suggestions,
    String? initialQuery,
  }) async {
    final searchCtl = TextEditingController(text: (initialQuery ?? '').trim());

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setModalState) {
              final q = searchCtl.text.trim();
              final filtered = suggestions
                  .where((s) => s.matches(q))
                  .toList(growable: false);

              return Padding(
                padding: EdgeInsets.only(
                  left: 14,
                  right: 14,
                  top: 6,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: searchCtl,
                      onChanged: (_) => setModalState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: _tr(
                            ar: 'ابحث...',
                            fr: 'Rechercher...',
                            en: 'Search...'),
                        filled: true,
                        fillColor: cs.surface,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1, color: cs.outlineVariant.withAlpha(140)),
                        itemBuilder: (ctx, i) {
                          final it = filtered[i];
                          return ListTile(
                            dense: true,
                            title: Text(it.display(ctx),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.of(ctx).pop(it.display(ctx)),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Text('✏️'),
                        label: Text(_tr(
                          ar: 'كتابة يدوية',
                          fr: 'Saisie manuelle',
                          en: 'Manual entry',
                        )),
                        onPressed: () => Navigator.of(ctx).pop(_kManualPick),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openModelPicker() async {
    final title = modelFieldLabelFor(
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    ).of(context);

    final typeHint = ((_attrs['type'] ?? '').trim().isNotEmpty)
        ? (_attrs['type'] ?? '').trim()
        : _typeOtherCtl.text.trim();

    final list = modelSuggestionsFor(
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
      typeIdOrLabel: typeHint,
    );

    if (list.isEmpty) {
      await _openManualEntry(
        title: title,
        hint: modelFieldHintFor(
          categoryId: _category?.id,
          subCategoryId: _subCategory?.id,
        ).of(context),
        initialValue: _modelCtl.text.trim(),
        onSaved: (v) => _setStateAndSave(() {
          final vv = v.trim();
          _modelCtl.text = vv;
          if (vv.isEmpty) {
            _attrs.remove('model');
          } else {
            _attrs['model'] = vv;
          }
        }),
      );
      return;
    }

    final picked = await _openSuggestionPicker(
      title: title,
      suggestions: list,
      initialQuery: _modelCtl.text.trim(),
    );

    if (!mounted || picked == null) return;

    if (picked == _kManualPick) {
      await _openManualEntry(
        title: title,
        hint: modelFieldHintFor(
          categoryId: _category?.id,
          subCategoryId: _subCategory?.id,
        ).of(context),
        initialValue: _modelCtl.text.trim(),
        onSaved: (v) => _setStateAndSave(() {
          final vv = v.trim();
          _modelCtl.text = vv;
          if (vv.isEmpty) {
            _attrs.remove('model');
          } else {
            _attrs['model'] = vv;
          }
        }),
      );
      return;
    }

    _setStateAndSave(() {
      final vv = picked.trim();
      _modelCtl.text = vv;
      if (vv.isEmpty) {
        _attrs.remove('model');
      } else {
        _attrs['model'] = vv;
      }
    });
  }

  Future<void> _openNeighborhoodPicker() async {
    final title = _tr(ar: 'الحي/المنطقة', fr: 'Quartier', en: 'Neighborhood');
    final hint = _tr(
      ar: 'اختر من القائمة أو اكتب يدوياً',
      fr: 'Choisissez dans la liste ou saisissez',
      en: 'Pick from the list or type manually',
    );

    // Nouakchott + Nouadhibou: neighborhoods depend on the chosen moughataa.
    final mid = (_moughataa?.id ?? '').trim();
    final wid = (_wilaya?.id ?? '').trim();
    final needsMoughataa =
        wid.startsWith('nouakchott_') || wid == 'dakhlet_nouadhibou';

    if (needsMoughataa && mid.isEmpty) {
      _snack(_tr(
        ar: 'اختر المقاطعة أولاً لتظهر الأحياء',
        fr: 'Choisissez d’abord la moughataa pour afficher les quartiers',
        en: 'Choose a moughataa first to see neighborhoods',
      ));
      return;
    }

    final list = mid.isEmpty
        ? const <MaSuggestion>[]
        : neighborhoodSuggestionsFor(wilayaId: wid, moughataaId: mid);

    if (list.isEmpty) {
      await _openManualEntry(
        title: title,
        hint: hint,
        initialValue: _neighborhoodCtl.text.trim(),
        onSaved: (v) => _setStateAndSave(() {
          final vv = v.trim();
          _neighborhoodCtl.text = vv;
          // Manual entry => no stable id
          _attrs.remove('neighborhood_id');
        }),
      );
      return;
    }

    final pickedLabel = await _openSuggestionPicker(
      title: title,
      suggestions: list,
      initialQuery: _neighborhoodCtl.text.trim(),
    );

    if (!mounted || pickedLabel == null) return;

    if (pickedLabel == _kManualPick) {
      await _openManualEntry(
        title: title,
        hint: hint,
        initialValue: _neighborhoodCtl.text.trim(),
        onSaved: (v) => _setStateAndSave(() {
          final vv = v.trim();
          _neighborhoodCtl.text = vv;
          _attrs.remove('neighborhood_id');
        }),
      );
      return;
    }

    _setStateAndSave(() {
      final vv = pickedLabel.trim();
      _neighborhoodCtl.text = vv;

      // Save stable neighborhood id when the pick matches a known suggestion.
      final q = MaSuggestionNorm.norm(vv);
      MaSuggestion? sel;
      for (final s in list) {
        final ar = MaSuggestionNorm.norm(s.label.ar);
        final fr = MaSuggestionNorm.norm(s.label.fr);
        final en = MaSuggestionNorm.norm(s.label.en);
        if (q == ar || q == fr || q == en) {
          sel = s;
          break;
        }
      }
      if (sel != null) {
        _attrs['neighborhood_id'] = sel.id;
      } else {
        _attrs.remove('neighborhood_id');
      }
    });
  }

  Future<void> _openAdminWhatsApp() async {
    final phone = kSupportWhatsApp.replaceAll(RegExp(r'\s+'), '');
    final text = Uri.encodeComponent(_tr(
      ar: 'مرحبا، أريد تفعيل باقة VIP لإعلاني لكن نسيت إضافة السعر.',
      fr: 'Bonjour, je veux activer le VIP pour mon annonce mais j\'ai oublié le prix.',
      en: 'Hi, I want to activate VIP for my listing but I forgot to add the price.',
    ));
    final uri = Uri.parse('https://wa.me/$phone?text=$text');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _pushVipNeedsPriceNotification({required String productId}) {
    try {
      ref.read(notificationsControllerProvider.notifier).pushText(
            type: AppNotificationType.system,
            arTitle: 'تعذر تفعيل VIP',
            frTitle: 'VIP non activé',
            enTitle: 'VIP not activated',
            arBody:
                'تعذر تفعيل الباقة لأن السعر غير مذكور. تواصل مع المشرف عبر واتساب.',
            frBody:
                'Impossible d\'activer le VIP car le prix est manquant. Contactez l\'admin sur WhatsApp.',
            enBody:
                'Could not activate VIP because price is missing. Contact admin on WhatsApp.',
            targetRoute: '/product/$productId',
            id: 'vip_needs_price_$productId',
          );
    } catch (_) {}
  }

  Future<void> _showVipNeedsPriceDialog({required String productId}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr(ar: 'تنبيه VIP', fr: 'Alerte VIP', en: 'VIP warning')),
        content: Text(_tr(
          ar: 'تم نشر إعلانك ✅ لكن تعذر تفعيل باقة VIP لأن السعر غير مذكور. يمكنك التواصل مع المشرف عبر واتساب.',
          fr: 'Votre annonce a été publiée ✅ mais le VIP n\'a pas pu être activé car le prix est manquant. Contactez l\'admin sur WhatsApp.',
          en: 'Your listing is published ✅ but VIP could not be activated because price is missing. Contact admin on WhatsApp.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_tr(ar: 'حسنا', fr: 'OK', en: 'OK')),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await _openAdminWhatsApp();
            },
            icon: const Icon(Icons.chat_outlined),
            label: Text(_tr(
                ar: 'واتساب المشرف',
                fr: 'WhatsApp admin',
                en: 'WhatsApp admin')),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
          content: Text(msg), duration: const Duration(milliseconds: 1200)),
    );
  }

  Future<void> _pickFromGallery() async {
    try {
      final items = await _picker.pickMultiImage(imageQuality: 82);
      if (!mounted) return;
      if (items.isEmpty) return;

      final max = _photoMaxForSelection();
      final remaining = max - _images.length;
      if (remaining <= 0) {
        _snack(_tr(
            ar: 'بلغت الحد الأقصى للصور ($max)',
            fr: 'Limite atteinte ($max)',
            en: 'Max images reached ($max)'));
        return;
      }

      final limited = items.take(remaining);
      setState(() {
        for (final x in limited) {
          if (x.path.trim().isNotEmpty) _images.add(x.path.trim());
        }
      });
    } catch (_) {
      if (!mounted) return;
      _snack(_tr(
          ar: 'تعذر فتح المعرض',
          fr: 'Galerie indisponible',
          en: 'Cannot open gallery'));
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final max = _photoMaxForSelection();
      if (_images.length >= max) {
        _snack(_tr(
            ar: 'بلغت الحد الأقصى للصور ($max)',
            fr: 'Limite atteinte ($max)',
            en: 'Max images reached ($max)'));
        return;
      }

      final x =
          await _picker.pickImage(source: ImageSource.camera, imageQuality: 82);
      if (!mounted) return;
      if (x == null || x.path.trim().isEmpty) return;
      setState(() => _images.add(x.path.trim()));
    } catch (_) {
      if (!mounted) return;
      _snack(_tr(
          ar: 'تعذر فتح الكاميرا',
          fr: 'Caméra indisponible',
          en: 'Cannot open camera'));
    }
  }

  Future<void> _openMediaSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _tr(
                      ar: 'إضافة صور',
                      fr: 'Ajouter des photos',
                      en: 'Add photos'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16),
                  textAlign: TextAlign.start,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _pickFromCamera();
                  },
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(
                      _tr(ar: 'التقاط بالكاميرا', fr: 'Caméra', en: 'Camera')),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _pickFromGallery();
                  },
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(_tr(
                      ar: 'اختيار من المعرض', fr: 'Galerie', en: 'Gallery')),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close_rounded),
                  label: Text(_tr(ar: 'إغلاق', fr: 'Fermer', en: 'Close')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _goTo(int next) async {
    if (!mounted) return;
    if (!_pageCtl.hasClients) {
      setState(() => _step = next);
      return;
    }
    setState(() => _step = next);
    await _pageCtl.animateToPage(
      next,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _onBackPressed() async {
    // If a menu/sheet is open, close it first.
    if (_step > 0) {
      await _goTo(_step - 1);
    } else {
      if (context.canPop()) {
        context.pop();
      } else {
        // Fallback for cases where Publish is a root route.
        context.go('/home');
      }
    }
  }

  bool _validateStep(int step) {
    // 0: category
    if (step == 0) {
      if (_category == null || _subCategory == null) {
        _snack(_tr(
            ar: 'اختر الفئة أولاً',
            fr: 'Choisissez d\'abord la catégorie',
            en: 'Choose a category first'));
        return false;
      }
      return true;
    }

    // 1: media (min/max depends on category)
    if (step == 1) {
      final max = _photoMaxForSelection();
      if (_images.length > max) {
        _snack(_tr(
            ar: 'عدد الصور أكبر من الحد المسموح ($max)',
            fr: 'Trop de photos (max $max)',
            en: 'Too many photos (max $max)'));
        return false;
      }

      final kind = publishKindFor(
        categoryId: _category?.id,
        subCategoryId: _subCategory?.id,
      );
      final requiresPhoto =
          kind != PublishKind.jobs && kind != PublishKind.services;

      if (requiresPhoto && _images.isEmpty) {
        _snack(_tr(
          ar: 'أضف صورة واحدة على الأقل',
          fr: 'Ajoutez au moins une photo',
          en: 'Add at least one photo',
        ));
        return false;
      }

      return true;
    }

    // 2: basic
    if (step == 2) {
      if (!(_basicKey.currentState?.validate() ?? false)) {
        _snack(_tr(
          ar: 'أكمل الحقول المطلوبة',
          fr: 'Complétez les champs requis',
          en: 'Please fill required fields',
        ));
        return false;
      }
      if (_category == null || _subCategory == null) {
        _snack(_tr(
            ar: 'اختر الفئة',
            fr: 'Choisissez une catégorie',
            en: 'Choose a category'));
        return false;
      }

      // If category changed after adding photos, enforce max again.
      final maxPhotos = _photoMaxForSelection();
      if (_images.length > maxPhotos) {
        _snack(_tr(
            ar: 'عدد الصور أكبر من الحد المسموح ($maxPhotos)',
            fr: 'Trop de photos (max $maxPhotos)',
            en: 'Too many photos (max $maxPhotos)'));
        return false;
      }

      return true;
    }

    // 3: location
    if (step == 3) {
      final formOk = (_locationKey.currentState?.validate() ?? true);
      final ok = _outsideMa
          ? (formOk && _outsideCountry != null)
          : (formOk && _wilaya != null);
      if (!ok) {
        _snack(_tr(
          ar: _outsideMa ? 'اختر الدولة' : 'اختر الولاية',
          fr: _outsideMa ? 'Choisissez le pays' : 'Choisissez la wilaya',
          en: _outsideMa ? 'Choose a country' : 'Choose a wilaya',
        ));
        return false;
      }
      return true;
    }

    // 4: contact
    if (step == 4) {
      final ok = (_contactKey.currentState?.validate() ?? true) &&
          _phoneCtl.text.trim().isNotEmpty;
      if (!ok) {
        _snack(_tr(
          ar: 'أدخل رقم الهاتف',
          fr: 'Entrez le téléphone',
          en: 'Enter phone number',
        ));
        return false;
      }
      if (!_allowWhatsApp && !_allowCall) {
        _snack(_tr(
          ar: 'اختر واتساب أو اتصال',
          fr: 'Choisissez WhatsApp ou Appel',
          en: 'Choose WhatsApp or Call',
        ));
        return false;
      }
      return true;
    }

    // 5: preview
    if (step == 5) return true;

    return true;
  }

  Future<void> _runPublishSafely() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await _publishOrUpdate();
    } catch (e, st) {
      debugPrint('Publish failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr(
            ar: 'تعذر النشر. تحقق من الإنترنت وإعدادات Firebase Storage ثم حاول مرة أخرى.',
            fr: 'Échec de publication. Vérifiez Internet et Firebase Storage puis réessayez.',
            en: 'Publish failed. Check internet and Firebase Storage then try again.',
          )),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _onNextPressed() async {
    if (!_validateStep(_step)) return;

    final maxStep = _maxStep;

    if (_step < maxStep) {
      await _goTo(_step + 1);
      return;
    }

    await _runPublishSafely();
  }

  int _parsePrice() {
    final raw = _priceCtl.text.trim();
    if (raw.isEmpty) return 0;
    final cleaned = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(cleaned) ?? 0;
  }

  static const List<_VipPlan> _vipPlans = <_VipPlan>[
    // Boost
    _VipPlan(id: 'boost_1d', tier: 'boost', rank: 1, days: 1, priceMru: 50),
    _VipPlan(id: 'boost_3d', tier: 'boost', rank: 1, days: 3, priceMru: 120),
    _VipPlan(id: 'boost_7d', tier: 'boost', rank: 1, days: 7, priceMru: 150),
    _VipPlan(id: 'boost_15d', tier: 'boost', rank: 1, days: 15, priceMru: 280),
    _VipPlan(id: 'boost_30d', tier: 'boost', rank: 1, days: 30, priceMru: 500),

    // Featured
    _VipPlan(
        id: 'featured_1d', tier: 'featured', rank: 2, days: 1, priceMru: 80),
    _VipPlan(
        id: 'featured_3d', tier: 'featured', rank: 2, days: 3, priceMru: 180),
    _VipPlan(
        id: 'featured_7d', tier: 'featured', rank: 2, days: 7, priceMru: 250),
    _VipPlan(
        id: 'featured_15d', tier: 'featured', rank: 2, days: 15, priceMru: 450),
    _VipPlan(
        id: 'featured_30d', tier: 'featured', rank: 2, days: 30, priceMru: 800),

    // Top
    _VipPlan(id: 'top_1d', tier: 'top', rank: 3, days: 1, priceMru: 120),
    _VipPlan(id: 'top_3d', tier: 'top', rank: 3, days: 3, priceMru: 250),
    _VipPlan(id: 'top_7d', tier: 'top', rank: 3, days: 7, priceMru: 400),
    _VipPlan(id: 'top_15d', tier: 'top', rank: 3, days: 15, priceMru: 650),
    _VipPlan(id: 'top_30d', tier: 'top', rank: 3, days: 30, priceMru: 1000),
  ];

  _VipPlan get _selectedVipPlan {
    for (final p in _vipPlans) {
      if (p.tier == _vipTier && p.days == _vipDays) return p;
    }
    return _vipPlans.first;
  }

  Widget _vipSection(ColorScheme cs) {
    final isEditing = _editing != null;
    final promoStatus =
        isEditing ? (_editing!.attrs['promo_status'] ?? '') : '';
    final promoApproved = promoStatus == 'approved';

    String tierLabel(String tier) => _tr(
          ar: tier == 'top'
              ? 'Top'
              : tier == 'featured'
                  ? 'Featured'
                  : 'Boost',
          fr: tier == 'top'
              ? 'Top'
              : tier == 'featured'
                  ? 'En vedette'
                  : 'Boost',
          en: tier == 'top'
              ? 'Top'
              : tier == 'featured'
                  ? 'Featured'
                  : 'Boost',
        );

    const tierOptions = ['boost', 'featured', 'top'];
    const dayOptions = [1, 3, 7, 15, 30];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: promoApproved ? true : _vipRequested,
          onChanged: promoApproved
              ? null
              : (v) => _setStateAndSave(() => _vipRequested = v),
          title: Text(_tr(
            ar: 'إعلان VIP (اختياري)',
            fr: 'Annonce VIP (optionnel)',
            en: 'VIP listing (optional)',
          )),
          subtitle: Text(
            promoApproved
                ? _tr(
                    ar: 'هذا الإعلان VIP بالفعل.',
                    fr: 'Cette annonce est déjà VIP.',
                    en: 'This listing is already VIP.',
                  )
                : _tr(
                    ar: 'اختر النوع والمدة. سيتم تفعيل VIP بعد مراجعة الإدارة.',
                    fr: "Choisissez le type et la durée. Le VIP s'active après validation.",
                    en: 'Choose type and duration. VIP activates after admin review.',
                  ),
          ),
        ),
        if (!promoApproved && _vipRequested) ...[
          const SizedBox(height: 8),
          Text(
            _tr(ar: 'نوع VIP', fr: 'Type VIP', en: 'VIP type'),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: cs.onSurface.withAlpha(200),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tierOptions.map((t) {
              final selected = _vipTier == t;
              return ChoiceChip(
                label: Text(tierLabel(t)),
                selected: selected,
                onSelected: (_) => _setStateAndSave(() => _vipTier = t),
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 12),
          Text(
            _tr(ar: 'المدة', fr: 'Durée', en: 'Duration'),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: cs.onSurface.withAlpha(200),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: dayOptions.map((d) {
              final selected = _vipDays == d;
              final label = _tr(
                ar: d == 1 ? '24 ساعة' : '$d أيام',
                fr: d == 1 ? '24h' : '$d j',
                en: d == 1 ? '24h' : '$d d',
              );
              return ChoiceChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) => _setStateAndSave(() => _vipDays = d),
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 10),
          Builder(builder: (_) {
            final sel = _selectedVipPlan;
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _tr(
                        ar: 'السعر: MRU ${sel.priceMru}  |  ${tierLabel(sel.tier)}  |  ${sel.days == 1 ? '24 ساعة' : '${sel.days} أيام'}',
                        fr: 'Prix: MRU ${sel.priceMru}  |  ${tierLabel(sel.tier)}  |  ${sel.days == 1 ? '24h' : '${sel.days}j'}',
                        en: 'Price: MRU ${sel.priceMru}  |  ${tierLabel(sel.tier)}  |  ${sel.days == 1 ? '24h' : '${sel.days}d'}',
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface.withAlpha(220),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Text(
            _tr(
              ar: 'سيظهر طلب VIP كـ "قيد المراجعة" حتى الموافقة.',
              fr: 'La demande VIP apparaîtra "en attente" jusqu’à validation.',
              en: 'VIP request will show as "pending" until approved.',
            ),
            style: TextStyle(
              color: cs.onSurface.withAlpha(170),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _publishOrUpdate() async {
    // Ensure we persist fields stored inside attrs (delivery, etc.)
    _syncDeliveryAttrs();
    _syncMultiOtherTextToAttrs();

    // Enforce KYC policy (admin-controlled).
    final allowed = await _ensureKycAllowed();
    if (!allowed) return;

    final a = ref.read(authControllerProvider);
    final rawUid =
        (FirebaseAuth.instance.currentUser?.uid ?? a.userId ?? 'guest').trim();
    final sellerId = rawUid.isEmpty ? 'guest' : rawUid;
    final sellerName = (a.name ?? '').trim().isEmpty
        ? _tr(ar: 'مستخدم', fr: 'Utilisateur', en: 'User')
        : a.name!.trim();

    final newPrice = _parsePrice();
    final title = _titleCtl.text.trim();
    final details = _detailsCtl.text.trim();
    final neighborhood =
        _outsideMa ? _outsideCityCtl.text.trim() : _neighborhoodCtl.text.trim();
    final phone = _phoneCtl.text.trim();

    // Option A: keep user inputs in memory, but don't save incompatible fields.
    final attrsForSave = Map<String, String>.from(_attrs);

    final allowedQuickKeys = quickFieldsFor(
      context,
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    ).map((q) => q.key).toSet();

    final allowType = variantDefsFor(
      context,
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    ).isNotEmpty;

    final allowModelSave = supportsModelFieldFor(
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );

    final supportsWarranty = supportsWarrantyFor(
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );

    // Only persist warranty when it makes sense.
    final saveHasWarranty = supportsWarranty &&
        _hasWarranty &&
        _warrantyValue > 0 &&
        _warrantyUnit.trim().isNotEmpty;

    const alwaysKeepAttrKeys = <String>{
      // taxonomy meta
      'sub_other',
      'type',
      'type_other',
      // location meta
      'outside_ma',
      'outside_country_iso2',
      'outside_country_dial',
      'outside_country_name_ar',
      'outside_country_name_fr',
      'outside_country_name_en',
      'outside_city',
      'location_note',
      // VIP/promo keys (owner-only details)
      'promo_status',
      'promo_pkg_id',
      'promo_tx_id',
      'promo_req_at_ms',
      'promo_appr_at_ms',
      'promo_until_ms',
      'promo_days',
      'promo_price_mru',
      'promo_tier',
      'promo_rank',
    };

    for (final k in List<String>.from(attrsForSave.keys)) {
      if (alwaysKeepAttrKeys.contains(k)) continue;
      // If it's a known quick-field key but NOT allowed for this category/subcategory,
      // remove it from what we save (but keep it in memory).
      if (kKnownQuickAttrKeys.contains(k) && !allowedQuickKeys.contains(k)) {
        attrsForSave.remove(k);
      }
    }

    if (!allowType) {
      attrsForSave.remove('type');
      attrsForSave.remove('type_other');
    }

    if (!allowModelSave) {
      attrsForSave.remove('model');
    } else {
      final model = _modelCtl.text.trim();
      if (model.isEmpty) {
        attrsForSave.remove('model');
      } else {
        attrsForSave['model'] = model;
      }
    }

    String wilayaStr;
    String moughataaStr;

    if (_outsideMa) {
      final cc = _outsideCountry;
      final locale = Localizations.localeOf(context);
      wilayaStr = (cc == null)
          ? _tr(ar: 'خارج موريتانيا', fr: 'Hors Mauritanie', en: 'Outside MR')
          : cc.nameFor(locale);
      moughataaStr = _tr(
          ar: 'خارج موريتانيا',
          fr: 'Hors Mauritanie',
          en: 'Outside Mauritania');

      // Ensure MR location ids are not set when publishing abroad.
      attrsForSave.remove('wilaya_id');
      attrsForSave.remove('moughataa_id');
      attrsForSave.remove('neighborhood_id');

      attrsForSave['outside_ma'] = 'true';
      if (cc != null) {
        attrsForSave['outside_country_iso2'] = cc.iso2;
        attrsForSave['outside_country_dial'] = cc.dialCode;
        attrsForSave['outside_country_name_ar'] = cc.nameAr;
        attrsForSave['outside_country_name_fr'] = cc.nameFr;
        attrsForSave['outside_country_name_en'] = cc.nameEn;
      }

      final city = _outsideCityCtl.text.trim();
      if (city.isNotEmpty) {
        attrsForSave['outside_city'] = city;
      } else {
        attrsForSave.remove('outside_city');
      }
    } else {
      wilayaStr = _wilaya!.name.of(context);
      moughataaStr = _moughataa?.name.of(context) ?? '';

      // Save stable ids as well (used to localize labels when user switches language).
      attrsForSave['wilaya_id'] = _wilaya!.id;
      if (_moughataa != null && _moughataa!.id.trim().isNotEmpty) {
        attrsForSave['moughataa_id'] = _moughataa!.id;
      } else {
        attrsForSave.remove('moughataa_id');
      }

      attrsForSave.remove('outside_ma');
      attrsForSave.remove('outside_country_iso2');
      attrsForSave.remove('outside_country_dial');
      attrsForSave.remove('outside_country_name_ar');
      attrsForSave.remove('outside_country_name_fr');
      attrsForSave.remove('outside_country_name_en');
      attrsForSave.remove('outside_city');
    }

    final locNote = _locationNoteCtl.text.trim();
    if (locNote.isNotEmpty) {
      attrsForSave['location_note'] = locNote;
    } else {
      attrsForSave.remove('location_note');
    }
    // VIP is no longer requested from the publish wizard.
    // We keep existing promo_* fields when editing, but ensure new listings
    // don't accidentally carry stale promo fields from old drafts.
    if (_editing == null) {
      attrsForSave.remove('promo_status');
      attrsForSave.remove('promo_pkg_id');
      attrsForSave.remove('promo_tx_id');
      attrsForSave.remove('promo_req_at_ms');
      attrsForSave.remove('promo_appr_at_ms');
      attrsForSave.remove('promo_until_ms');
      attrsForSave.remove('promo_days');
      attrsForSave.remove('promo_price_mru');
      attrsForSave.remove('promo_tier');
      attrsForSave.remove('promo_rank');
    }

    final store = ref.read(localStoreProvider);
    final now = DateTime.now();

    if (_editing != null) {
      final current = _editing!;
      int? oldPrice = current.oldPrice;
      // Set old price if changed.
      if (current.price != newPrice && current.price > 0 && newPrice > 0) {
        oldPrice = current.price;
      }

      final repo = ref.read(productsRepositoryProvider);
      final uploadedImages = await repo.uploadProductImages(
        productId: current.id,
        imagePathsOrUrls: List<String>.from(_images),
      );

      final searchText = <String>[
        title,
        sellerName,
        wilayaStr,
        moughataaStr,
        neighborhood,
        details,
        if ((_category?.id ?? '').trim().isNotEmpty) _category!.id,
        if ((_subCategory?.id ?? '').trim().isNotEmpty) _subCategory!.id,
        ...attrsForSave.values,
      ].where((s) => s.trim().isNotEmpty).join(' ');

      final published = current.publishedAt;
      final data = <String, dynamic>{
        'id': current.id,
        'title': title,
        'sellerId': sellerId,
        'sellerName': sellerName,
        'price': newPrice,
        'oldPrice': oldPrice,
        'images': uploadedImages,
        'wilaya': wilayaStr,
        'moughataa': moughataaStr,
        'neighborhood': neighborhood,
        'publishedAt': Timestamp.fromDate(published),
        'details': details.isEmpty ? null : details,
        'description': details.isEmpty ? null : details,
        'phone': phone.isEmpty ? null : phone,
        'allowWhatsApp': _allowWhatsApp,
        'allowCall': _allowCall,
        'category': _category?.id,
        'subCategory': _subCategory?.id,
        'hasWarranty': saveHasWarranty,
        'warrantyValue': saveHasWarranty ? _warrantyValue : null,
        'warrantyUnit': saveHasWarranty ? _warrantyUnit : null,
        'warrantyType': saveHasWarranty ? _warrantyType : null,
        'attrs': Map<String, String>.from(attrsForSave),
        // IMPORTANT: Don't force 'active' on edit.
        // Some listings can be 'pending' (awaiting review) or 'paused'/'deleted'.
        // Forcing 'active' can be rejected by Firestore rules and makes "Edit" work
        // for some listings but not others.
        'status': (current.status.trim().isEmpty)
            ? (current.isSold ? 'sold' : 'active')
            : current.status,
        'searchTokens': repo.buildSearchTokens(searchText),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await repo.upsertProduct(id: current.id, data: data, merge: true);

      if (!mounted) return;

      _snack(_tr(
        ar: 'تم تحديث إعلانك ✅',
        fr: 'Annonce mise à jour ✅',
        en: 'Listing updated ✅',
      ));

      final token = DateTime.now().millisecondsSinceEpoch.toString();
      context.go('/you/listings?r=$token');
      return;
    }

    final id =
        'p_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

    final repo = ref.read(productsRepositoryProvider);
    final uploadedImages = await repo.uploadProductImages(
      productId: id,
      imagePathsOrUrls: List<String>.from(_images),
    );

    final searchText = <String>[
      title,
      sellerName,
      wilayaStr,
      moughataaStr,
      neighborhood,
      details,
      if ((_category?.id ?? '').trim().isNotEmpty) _category!.id,
      if ((_subCategory?.id ?? '').trim().isNotEmpty) _subCategory!.id,
      ...attrsForSave.values,
    ].where((s) => s.trim().isNotEmpty).join(' ');

// Build a JSON-serializable payload for Cloud Functions.
// NOTE: Do NOT include FieldValue / Timestamp objects in callable payloads.
    final data = <String, dynamic>{
      'id': id,
      'title': title,
      'sellerId': sellerId,
      'sellerName': sellerName,
      'price': newPrice,
      'oldPrice': null,
      'images': uploadedImages,
      'wilaya': wilayaStr,
      'moughataa': moughataaStr,
      'neighborhood': neighborhood,
      'publishedAtMs': now.millisecondsSinceEpoch,
      'details': details.isEmpty ? null : details,
      'description': details.isEmpty ? null : details,
      'phone': phone.isEmpty ? null : phone,
      'allowWhatsApp': _allowWhatsApp,
      'allowCall': _allowCall,
      'category': _category?.id,
      'subCategory': _subCategory?.id,
      'hasWarranty': saveHasWarranty,
      'warrantyValue': saveHasWarranty ? _warrantyValue : null,
      'warrantyUnit': saveHasWarranty ? _warrantyUnit : null,
      'warrantyType': saveHasWarranty ? _warrantyType : null,
      'attrs': Map<String, String>.from(attrsForSave),
      // Server decides final status based on verification + category.
      'status': 'pending',
      'viewCount': 0,
      'searchTokens': repo.buildSearchTokens(searchText),
    }..removeWhere((_, v) => v == null);

    String createdStatus = 'pending';
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('createProduct');
      final res = await callable.call(<String, dynamic>{
        'productId': id,
        'data': data,
      });

      final out = (res.data is Map)
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};

      createdStatus = (out['status'] ?? 'pending').toString();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;

      final code = e.code.toLowerCase();
      if (code == 'resource-exhausted') {
        final details = (e.details is Map)
            ? Map<String, dynamic>.from(e.details as Map)
            : <String, dynamic>{};
        final reason = (details['reason'] ?? '').toString();
        final maxActive = details['maxActive'];
        final dailyLimit = details['dailyLimit'];

        final msg = reason == 'max_active'
            ? _tr(
                ar: 'لقد وصلت إلى الحد الأقصى للمنشورات المتاحة لغير الموثّق (${maxActive ?? ''}).وثّق حسابك للنشر بلا حدود.',
                fr: "Vous avez atteint la limite d'annonces (non vérifié). Vérifiez votre compte.",
                en: 'You reached the posting limit (unverified). Verify your account for unlimited posting.',
              )
            : _tr(
                ar: 'لقد وصلت إلى الحد اليومي للنشر لغير الموثّق (${dailyLimit ?? ''}).وثّق حسابك للنشر بلا حدود.',
                fr: "Vous avez atteint la limite quotidienne (non vérifié). Vérifiez votre compte.",
                en: 'You reached the daily posting limit (unverified). Verify your account for unlimited posting.',
              );

        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(_tr(ar: 'حد النشر', fr: 'Limite', en: 'Limit')),
            content: Text(msg),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(_tr(ar: 'حسنًا', fr: 'OK', en: 'OK')),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.push('/you/verify');
                },
                child:
                    Text(_tr(ar: 'وثّق حسابك', fr: 'Vérifier', en: 'Verify')),
              ),
            ],
          ),
        );
        return;
      }

      _snack(_tr(
        ar: 'تعذر نشر إعلانك الآن. حاول مرة أخرى.',
        fr: "Impossible de publier الآن. Réessayez.",
        en: "Couldn't publish now. Try again.",
      ));
      return;
    } catch (_) {
      if (!mounted) return;
      _snack(_tr(
        ar: 'تعذر نشر إعلانك الآن. حاول مرة أخرى.',
        fr: "Impossible de publier الآن. Réessayez.",
        en: "Couldn't publish now. Try again.",
      ));
      return;
    }
    if (!mounted) return;

    _snack(_tr(
      ar: createdStatus == 'active'
          ? 'تم نشر إعلانك ✅'
          : 'تم إرسال إعلانك للمراجعة ✅',
      fr: createdStatus == 'active'
          ? 'Annonce publiée ✅'
          : 'Annonce en cours de validation ✅',
      en: createdStatus == 'active'
          ? 'Listing published ✅'
          : 'Listing sent for review ✅',
    ));

    final action = await showDialog<String>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: Text(
                createdStatus == 'active'
                    ? _tr(ar: 'تم النشر ✅', fr: 'Publié ✅', en: 'Published ✅')
                    : _tr(
                        ar: 'تم الإرسال للمراجعة ✅',
                        fr: 'En attente ✅',
                        en: 'Sent for review ✅',
                      ),
              ),
              content: Text(
                createdStatus == 'active'
                    ? _tr(
                        ar: 'سيظهر إعلانك الآن للناس ✅',
                        fr: 'Votre annonce est maintenant en ligne ✅',
                        en: 'Your listing is now live ✅',
                      )
                    : _tr(
                        ar: '''لن يظهر إعلانك للناس حتى يتم التأكد منه.
عادةً تتم المراجعة خلال 5 دقائق إلى 24 ساعة.
يمكنك متابعة الحالة من صفحة إعلاناتي.

وثّق حسابك ليُنشر إعلانك القادم مباشرة بدون مراجعة.''',
                        fr: '''Votre annonce ne sera pas visible avant validation.
Généralement: 5 minutes à 24 heures.
Vous pouvez suivre l'état dans Mes annonces.

Vérifiez votre compte pour publier instantanément la prochaine fois.''',
                        en: '''Your listing won't be visible until it's reviewed.
Usually 5 minutes to 24 hours.
You can track it in My listings.

Verify your account to publish instantly next time.''',
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop('home'),
                  child: Text(_tr(ar: 'الرئيسية', fr: 'Accueil', en: 'Home')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop('status'),
                  child: Text(_tr(
                      ar: 'متابعة الحالة',
                      fr: "Voir l'état",
                      en: 'View status')),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop('another'),
                  child: Text(_tr(
                      ar: 'نشر إعلان آخر',
                      fr: 'Publier encore',
                      en: 'Publish another')),
                ),
              ],
            );
          },
        ) ??
        'status';

    if (!mounted) return;

    if (action == 'another') {
      await _resetForNewPublish();
    } else if (action == 'verify') {
      context.push('/you/verify');
    } else if (action == 'home') {
      final token = DateTime.now().millisecondsSinceEpoch.toString();
      context.go('/home?r=$token');
    } else {
      final token = DateTime.now().millisecondsSinceEpoch.toString();
      context.go('/you/listings?r=$token');
    }
    return;
  }

  Future<void> _resetForNewPublish() async {
    _titleCtl.clear();
    _detailsCtl.clear();
    _priceCtl.clear();
    _neighborhoodCtl.clear();
    _subOtherCtl.clear();
    _typeOtherCtl.clear();
    _outsideCityCtl.clear();
    _locationNoteCtl.clear();

    setState(() {
      _step = 0;
      _images.clear();
      _category = null;
      _subCategory = null;
      _wilaya = null;
      _moughataa = null;
      _outsideMa = false;
      _outsideCountry = null;
      _attrs.clear();
      _vipRequested = false;
      _vipTier = 'boost';
      _vipDays = 7;
      _hasWarranty = false;
      _warrantyValue = 0;
      _warrantyType = 'seller';
      _allowWhatsApp = true;
      _allowCall = true;
      _vipRequested = false;
      _vipTier = 'boost';
      _vipDays = 7;
    });

    await _goTo(0);
  }

  Future<_CategoryPickResult?> _pickCategoryAndSub(
      List<CategoryNode> categories) async {
    if (!mounted) return null;
    return showModalBottomSheet<_CategoryPickResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _CategoryPickerSheet(
        categories: categories,
        initialCategory: _category,
        otherSub: _otherSub,
      ),
    );
  }

  InputDecoration _decor({
    required String label,
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: cs.surface,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.outlineVariant.withAlpha(170)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Future<void> _openPrivacy() async {}

  Future<void> _openTerms() async {}

  Future<void> _showLegalSheet({
    required String title,
    required String body,
    required VoidCallback onAccepted,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 10,
              bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                Container(
                  constraints: const BoxConstraints(maxHeight: 380),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant.withAlpha(140)),
                  ),
                  child: SingleChildScrollView(
                    child: Text(body,
                        style: TextStyle(color: cs.onSurface.withAlpha(210))),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: Text(_tr(ar: 'رجوع', fr: 'Retour', en: 'Back')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          onAccepted();
                          Navigator.of(ctx).pop();
                        },
                        child: Text(_tr(
                            ar: 'قرأت وأوافق',
                            fr: 'J’ai lu et j’accepte',
                            en: 'I read & accept')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stepPreview(ColorScheme cs) {
    final title = _titleCtl.text.trim().isEmpty ? '—' : _titleCtl.text.trim();
    final price = _parsePrice();
    final cat = _category?.name.of(context) ?? '—';
    final rawSub = _subCategory?.name.of(context) ?? '—';
    final sub = (_subCategory?.id == _otherSub.id &&
            _subOtherCtl.text.trim().isNotEmpty)
        ? _subOtherCtl.text.trim()
        : rawSub;

    final variantDefs = variantDefsFor(
      context,
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );

    final supportsWarranty = supportsWarrantyFor(
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );

    final typeId = _normalizeStoredOptionToId(_attrs['type'], variantDefs) ??
        (_attrs['type'] ?? '').trim();
    final typeLabel = typeId.isEmpty
        ? null
        : (typeId == 'Other' && _typeOtherCtl.text.trim().isNotEmpty)
            ? _typeOtherCtl.text.trim()
            : _labelForOptionId(typeId, variantDefs);

    final modelChip = (supportsModelFieldFor(
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    )
        ? (_attrs['model'] ?? '').trim()
        : '');
// Localized preview lines for quick attrs (condition, color, etc.)
    final quickDefs = quickFieldsFor(
      context,
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );
    final quickByKey = <String, QuickFieldDef>{
      for (final q in quickDefs) q.key: q,
    };

// We keep attrs in storage, but in preview we only show what is relevant
// to the currently selected category/subcategory.
    final allowedKeys = quickByKey.keys.toSet();
    const hiddenAttrKeys = <String>{
      'type',
      'sub_other',
      'type_other',
      'outside_ma',
      'outside_country_iso2',
      'outside_city',
      'location_note',
      // VIP / promo system keys (owner-only details)
      'promo_status',
      'promo_pkg_id',
      'promo_tx_id',
      'promo_req_at_ms',
      'promo_appr_at_ms',
      'promo_until_ms',
      'promo_days',
      'promo_price_mru',
      'promo_tier',
      'promo_rank',
    };
    final attrLines = <String>[];
    for (final e in _attrs.entries) {
      final k = e.key;
      final raw = e.value.trim();
      if (raw.isEmpty) continue;
      if (hiddenAttrKeys.contains(k)) continue;
      if (!allowedKeys.contains(k))
        continue; // hide incompatible fields (Option A)

      final q = quickByKey[k];
      if (q == null) continue;
      final label = q.label.of(context);
      if (q.options.isNotEmpty) {
        final id = _normalizeStoredOptionToId(raw, q.options) ?? raw;
        final v = _labelForOptionId(id, q.options);
        attrLines.add('• $label: $v');
      } else {
        attrLines.add('• $label: $raw');
      }
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        _tipCard(
          cs: cs,
          asset: 'assets/illustrations/publish/checklist.svg',
          title: _tr(
            ar: 'قبل النشر',
            fr: 'Avant de publier',
            en: 'Before you publish',
          ),
          subtitle: _tr(
            ar: 'راجع العنوان والسعر والصور ثم اضغط نشر. يمكنك التعديل لاحقًا.',
            fr: 'Vérifiez titre, prix et photos puis publiez. Vous pourrez modifier après.',
            en: 'Check title, price and photos then publish. You can edit later.',
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_tr(ar: 'معاينة قبل النشر', fr: 'Aperçu', en: 'Preview'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 12),
              if (_images.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 4 / 5,
                    child: PageView(
                      children: _images
                          .map((p) => _SmartImage(path: p, fit: BoxFit.cover))
                          .toList(),
                    ),
                  ),
                )
              else
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: cs.outlineVariant.withAlpha(140)),
                  ),
                  child: Center(
                    child: Text(
                      _tr(
                          ar: 'لا توجد صور (يمكنك المتابعة)',
                          fr: 'Aucune photo',
                          en: 'No photos (you can continue)'),
                      style: TextStyle(color: cs.onSurface.withAlpha(180)),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                price <= 0
                    ? _tr(
                        ar: 'السعر قابل للتفاوض',
                        fr: 'Prix négociable',
                        en: 'Negotiable')
                    : '$price MRU',
                style:
                    TextStyle(color: cs.primary, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(cs, cat),
                  _chip(cs, sub),
                  if ((typeLabel ?? '').trim().isNotEmpty)
                    _chip(cs, typeLabel!),
                  if (modelChip.isNotEmpty) _chip(cs, modelChip),
                  if (supportsWarranty && _hasWarranty && _warrantyValue > 0)
                    _chip(
                        cs,
                        _tr(
                            ar: 'ضمان $_warrantyValue شهر',
                            fr: 'Garantie $_warrantyValue mois',
                            en: '${_warrantyValue}m warranty')),
                ],
              ),
              if (attrLines.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final line in attrLines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      line,
                      style: TextStyle(color: cs.onSurface.withAlpha(230)),
                    ),
                  ),
              ],
            ],
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _tr(
                  ar: 'بالنشر أنت توافق ضمنيًا على الشروط والأحكام وسياسة الخصوصية.',
                  fr: 'En publiant, vous acceptez les conditions et la confidentialité.',
                  en: 'By publishing, you agree to the terms and privacy policy.',
                ),
                style: TextStyle(
                  color: cs.onSurface.withAlpha(190),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => context.push('/content/policies/terms'),
                    child: Text(_tr(
                      ar: 'الشروط والأحكام',
                      fr: 'Conditions',
                      en: 'Terms',
                    )),
                  ),
                  OutlinedButton(
                    onPressed: () => context.push('/content/policies/privacy'),
                    child: Text(_tr(
                      ar: 'سياسة الخصوصية',
                      fr: 'Confidentialité',
                      en: 'Privacy',
                    )),
                  ),
                  OutlinedButton(
                    onPressed: () => context.push('/content/policies'),
                    child: Text(_tr(
                      ar: 'المزيد',
                      fr: 'Plus',
                      en: 'More',
                    )),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(ColorScheme cs, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withAlpha(140)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEditing = _editing != null;
    final maxStep = _maxStep;
    final rtl = Directionality.of(context) == TextDirection.rtl ||
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

    return Stack(
      children: [
        PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _onBackPressed();
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(isEditing
                  ? _tr(ar: 'تعديل المنتج', fr: 'Modifier', en: 'Edit')
                  : _tr(ar: 'نشر منتج', fr: 'Publier', en: 'Publish')),
              leading: IconButton(
                onPressed: _onBackPressed,
                icon: const BackButtonIcon(),
              ),
            ),
            body: Column(
              children: [
                _Header(step: _step, totalSteps: maxStep),
                Expanded(
                  child: PageView(
                    controller: _pageCtl,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _stepCategory(cs),
                      _stepMedia(cs),
                      _stepBasic(cs),
                      _stepLocation(cs),
                      _stepContact(cs),
                      _stepPreview(cs),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _onBackPressed,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(rtl
                                    ? Icons.chevron_right_rounded
                                    : Icons.chevron_left_rounded),
                                const SizedBox(width: 8),
                                Text(_tr(
                                    ar: 'السابق', fr: 'Précédent', en: 'Back')),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _submitting ? null : _onNextPressed,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Builder(builder: (context) {
                              final done = _step == maxStep;
                              final label = done
                                  ? (isEditing
                                      ? _tr(
                                          ar: 'حفظ',
                                          fr: 'Enregistrer',
                                          en: 'Save')
                                      : _tr(
                                          ar: 'نشر',
                                          fr: 'Publier',
                                          en: 'Publish'))
                                  : _tr(
                                      ar: 'التالي', fr: 'Suivant', en: 'Next');
                              final icon = done
                                  ? Icons.check_rounded
                                  : (rtl
                                      ? Icons.chevron_left_rounded
                                      : Icons.chevron_right_rounded);
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(icon),
                                  const SizedBox(width: 8),
                                  Text(label),
                                ],
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_submitting)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black38,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 18,
                        spreadRadius: 2,
                        offset: Offset(0, 10),
                        color: Colors.black26,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(_tr(
                        ar: 'جاري النشر...',
                        fr: 'Publication...',
                        en: 'Publishing...',
                      )),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withAlpha(160)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _tipCard({
    required ColorScheme cs,
    required String asset,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withAlpha(150)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: cs.primary.withAlpha(22),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: SvgPicture.asset(
                asset,
                width: 26,
                height: 26,
                colorFilter: ColorFilter.mode(cs.primary, BlendMode.srcIn),
              ),
            ),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(Icons.lightbulb_outline,
                        size: 18, color: cs.onSurface.withAlpha(130)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: cs.onSurface.withAlpha(170),
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _photoMaxForSelection() {
    final kind = publishKindFor(
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );
    if (kind == PublishKind.jobs || kind == PublishKind.services) return 3;
    if (kind == PublishKind.vehicles || kind == PublishKind.realEstate)
      return 15;
    return 10;
  }

  String _photoPolicyHint() {
    final max = _photoMaxForSelection();
    final kind = publishKindFor(
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );
    if (kind == PublishKind.jobs || kind == PublishKind.services) {
      return _tr(
        ar: 'الصور اختيارية لهذا النوع (حتى $max صور).',
        fr: "Photos optionnelles pour ce type (max $max).",
        en: 'Photos are optional for this type (max $max).',
      );
    }
    if (kind == PublishKind.vehicles || kind == PublishKind.realEstate) {
      return _tr(
        ar: 'يمكنك إضافة حتى $max صورة (يفضل 5 صور أو أكثر).',
        fr: "Jusqu'à $max photos (5+ recommandées).",
        en: 'Up to $max photos (5+ recommended).',
      );
    }
    return _tr(
      ar: 'يمكنك إضافة حتى $max صور.',
      fr: "Jusqu'à $max photos.",
      en: 'You can add up to $max photos.',
    );
  }

  Widget _stepCategory(ColorScheme cs) {
    final categories = maCategories.where((c) => c.id != '__na__').toList();
    final cat = _category?.name.of(context);
    final sub = _subCategory?.name.of(context);
    final has = (cat != null && sub != null);

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        _tipCard(
          cs: cs,
          asset: 'assets/illustrations/publish/checklist.svg',
          title: _tr(
              ar: 'اختر الفئة أولاً',
              fr: 'Choisissez la catégorie',
              en: 'Pick category first'),
          subtitle: _tr(
            ar: 'بعد اختيار الفئة سنعرض لك خيارات مناسبة (مثل التوصيل/الضمان وحد الصور).',
            fr: 'Après le choix, nous adaptons les options (livraison, garantie, limites photos).',
            en: 'After selecting, we adapt options (delivery, warranty, photo limits).',
          ),
        ),
        _card(
          child: Form(
            key: _categoryKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr(ar: 'التصنيف', fr: 'Catégorie', en: 'Category'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 12),
                FormField<String>(
                  validator: (_) {
                    if (_category == null || _subCategory == null) {
                      return _tr(ar: 'مطلوب', fr: 'Requis', en: 'Required');
                    }
                    return null;
                  },
                  builder: (state) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        final picked = await _pickCategoryAndSub(categories);
                        if (!mounted || picked == null) return;
                        setState(() {
                          final prevCatId = _category?.id;
                          final prevSubId = _subCategory?.id;
                          final changedCat = (prevCatId != picked.category.id);
                          final changedSub = (prevSubId != picked.sub.id);

                          _category = picked.category;
                          _subCategory = picked.sub;

                          _wipeOnCategoryOrSubChange(
                            changedMainCategory: changedCat,
                            changedSubCategory: changedSub,
                          );

                          final max = _photoMaxForSelection();
                          if (_images.length > max) {
                            _images.removeRange(max, _images.length);
                          }
                        });
                        state.validate();
                      },
                      child: InputDecorator(
                        decoration: _decor(
                          label: _tr(
                              ar: 'الفئة والفئة الفرعية *',
                              fr: 'Catégorie & sous-catégorie *',
                              en: 'Category & subcategory *'),
                          hint: _tr(
                            ar: 'اضغط للاختيار',
                            fr: 'Appuyez pour choisir',
                            en: 'Tap to choose',
                          ),
                          prefixIcon: const Icon(Icons.category_outlined),
                        ).copyWith(errorText: state.errorText),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                has
                                    ? '$cat  •  $sub'
                                    : _tr(
                                        ar: 'اضغط للاختيار',
                                        fr: 'Choisir',
                                        en: 'Tap to choose'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: has ? null : cs.onSurfaceVariant,
                                  fontWeight:
                                      has ? FontWeight.w800 : FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  has
                      ? _photoPolicyHint()
                      : _tr(
                          ar: 'اختر الفئة لمعرفة حد الصور.',
                          fr: 'Choisissez pour voir la limite.',
                          en: 'Pick a category to see limits.'),
                  style: TextStyle(
                      color: cs.onSurface.withAlpha(170),
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepMedia(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        _tipCard(
          cs: cs,
          asset: 'assets/illustrations/publish/photo.svg',
          title: _tr(
            ar: 'نصيحة للصور',
            fr: 'Astuce photo',
            en: 'Photo tip',
          ),
          subtitle: _tr(
            ar: 'صوّر المنتج بإضاءة جيدة وخلفية بسيطة. 3 صور تكفي كبداية.',
            fr: 'Bonne lumière + fond simple. 3 photos suffisent au début.',
            en: 'Good light + clean background. 3 photos are a great start.',
          ),
        ),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _tr(ar: 'الصور', fr: 'Photos', en: 'Photos'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: (_category == null ? null : _openMediaSheet),
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(_tr(ar: 'إضافة', fr: 'Ajouter', en: 'Add')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final max = _photoMaxForSelection();
                return Text(
                  _tr(
                    ar: 'الحد الأقصى للصور: $max',
                    fr: 'Maximum de photos: $max',
                    en: 'Max photos: $max',
                  ),
                  style: TextStyle(color: cs.onSurface.withAlpha(170)),
                );
              }),
              const SizedBox(height: 12),
              if (_images.isEmpty)
                Container(
                  height: 130,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant.withAlpha(150)),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.image_outlined,
                          size: 34, color: cs.onSurface.withAlpha(120)),
                      const SizedBox(height: 8),
                      Text(_tr(
                          ar: 'لا توجد صور بعد',
                          fr: 'Aucune photo',
                          en: 'No photos yet')),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final path in _images)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              width: 92,
                              height: 92,
                              child: _SmartImage(path: path),
                            ),
                          ),
                          PositionedDirectional(
                            top: 6,
                            end: 6,
                            child: InkWell(
                              onTap: () => setState(() => _images.remove(path)),
                              child: Container(
                                height: 26,
                                width: 26,
                                decoration: BoxDecoration(
                                  color: cs.surface.withAlpha(240),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: cs.outlineVariant.withAlpha(160)),
                                ),
                                child:
                                    const Icon(Icons.close_rounded, size: 16),
                              ),
                            ),
                          )
                        ],
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _snack(_tr(
                    ar: 'ميزة الفيديو قريبًا 🎥',
                    fr: 'Vidéo bientôt 🎥',
                    en: 'Video coming soon 🎥')),
                icon: const Icon(Icons.videocam_outlined),
                label: Text(_tr(
                    ar: 'فيديو (قريبًا)',
                    fr: 'Vidéo (bientôt)',
                    en: 'Video (soon)')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepBasic(ColorScheme cs) {
    final quick = quickFieldsFor(
      context,
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );

    final kind = publishKindFor(
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );

    // Jobs seeker = category jobs + subcategory jobs_seek
    final isJobSeek =
        (_category?.id == 'jobs' && _subCategory?.id == 'jobs_seek');

    // Show the most important quick fields first, keep the rest under "More details".
    final primaryKeys = <String>{
      if (isJobSeek) ...{
        'availability',
        'experience',
        'education',
        'languages'
      },
      if (kind == PublishKind.vehicles) ...{
        'year',
        'mileage',
        'fuel',
        'gear',
        'transmission',
        'condition'
      },
      if (kind == PublishKind.realEstate) ...{
        'rooms',
        'area',
        'bathrooms',
        'furnished',
        'property_type'
      },
      if (kind == PublishKind.electronics) ...{
        'brand',
        'storage',
        'condition',
        'color'
      },
      if (kind == PublishKind.goods) ...{'condition', 'brand', 'size', 'color'},
    };

    final primaryQuick = <QuickFieldDef>[];
    final extraQuick = <QuickFieldDef>[];

    for (final q in quick) {
      if (primaryKeys.contains(q.key)) {
        primaryQuick.add(q);
      } else {
        extraQuick.add(q);
      }
    }

    // Fallback: if we didn't match keys (taxonomy differs), show first 4 as primary.
    if (primaryQuick.isEmpty && quick.isNotEmpty) {
      final takeN = quick.length >= 4 ? 4 : quick.length;
      primaryQuick
        ..clear()
        ..addAll(quick.take(takeN));
      extraQuick
        ..clear()
        ..addAll(quick.skip(takeN));
    }
    final variantDefs = variantDefsFor(
      context,
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );

    final supportsWarranty = supportsWarrantyFor(
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );
    final allowModel = supportsModelFieldFor(
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );

    final categories = maCategories.where((c) => c.id != '__na__').toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        _tipCard(
          cs: cs,
          asset: 'assets/illustrations/publish/price.svg',
          title: _tr(
            ar: 'نصيحة للسعر والعنوان',
            fr: 'Astuce titre & prix',
            en: 'Title & price tip',
          ),
          subtitle: _tr(
            ar: 'عنوان واضح + سعر صحيح يساعدان على البيع أسرع. مثال: MRU 4500.',
            fr: 'Un titre clair + un bon prix vend plus vite. Ex: MRU 4500.',
            en: 'Clear title + correct price sells faster. e.g. MRU 4500.',
          ),
        ),
        _card(
          child: Form(
            key: _basicKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr(
                      ar: 'معلومات المنتج',
                      fr: 'Infos produit',
                      en: 'Product info'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 14),

                // Title
                TextFormField(
                  controller: _titleCtl,
                  textInputAction: TextInputAction.next,
                  decoration: _decor(
                    label:
                        _tr(ar: 'عنوان المنتج *', fr: 'Titre *', en: 'Title *'),
                    hint: _tr(
                        ar: 'مثال: iPhone 13 Pro 256GB',
                        fr: 'Ex: iPhone 13 Pro 256GB',
                        en: 'e.g. iPhone 13 Pro 256GB'),
                    prefixIcon: const Icon(Icons.title_rounded),
                  ),
                  validator: (v) => ((v ?? '').trim().isEmpty)
                      ? _tr(ar: 'مطلوب', fr: 'Requis', en: 'Required')
                      : null,
                ),
                const SizedBox(height: 12),

                // Details
                TextFormField(
                  controller: _detailsCtl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: _decor(
                    label: _tr(
                        ar: 'تفاصيل (اختياري)',
                        fr: 'Détails (opt.)',
                        en: 'Details (optional)'),
                    hint: _tr(
                      ar: 'اذكر الحالة، المواصفات، الملحقات، سبب البيع...',
                      fr: 'Décrivez l’état, les specs, accessoires, raison...',
                      en: 'Describe condition, specs, accessories, reason...',
                    ),
                    prefixIcon: const Icon(Icons.subject_rounded),
                  ),
                ),
                const SizedBox(height: 12),

                // Temu-style category picker (grid)
                FormField<String>(
                  validator: (_) {
                    if (_category == null || _subCategory == null) {
                      return _tr(ar: 'مطلوب', fr: 'Requis', en: 'Required');
                    }
                    return null;
                  },
                  builder: (state) {
                    final cat = _category?.name.of(context);
                    final sub = _subCategory?.name.of(context);
                    final has = (cat != null && sub != null);
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        final picked = await _pickCategoryAndSub(categories);
                        if (!mounted || picked == null) return;
                        setState(() {
                          final prevCatId = _category?.id;
                          final prevSubId = _subCategory?.id;
                          final changedCat = (prevCatId != picked.category.id);
                          final changedSub = (prevSubId != picked.sub.id);

                          _category = picked.category;
                          _subCategory = picked.sub;

                          // Fix: wipe incompatible values immediately to prevent stale dropdown
                          // values (red screen) and confusing carry-over when editing.
                          _wipeOnCategoryOrSubChange(
                            changedMainCategory: changedCat,
                            changedSubCategory: changedSub,
                          );
                        });
                        state.validate();
                      },
                      child: InputDecorator(
                        decoration: _decor(
                          label: _tr(
                              ar: 'الفئة والفئة الفرعية *',
                              fr: 'Catégorie & sous-catégorie *',
                              en: 'Category & subcategory *'),
                          hint: _tr(
                            ar: 'اختر الفئة المناسبة',
                            fr: 'Choisissez une catégorie',
                            en: 'Choose a category',
                          ),
                          prefixIcon: const Icon(Icons.category_outlined),
                        ).copyWith(errorText: state.errorText),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                has
                                    ? '$cat  •  $sub'
                                    : _tr(
                                        ar: 'اضغط للاختيار',
                                        fr: 'Appuyez pour choisir',
                                        en: 'Tap to choose',
                                      ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: has ? null : cs.onSurfaceVariant,
                                  fontWeight: has ? FontWeight.w700 : null,
                                ),
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down_rounded),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // Custom subcategory when user chooses "Other"
                if (_subCategory?.id == _otherSub.id) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _subOtherCtl,
                    textInputAction: TextInputAction.next,
                    onChanged: (v) => _attrs['sub_other'] = v.trim(),
                    decoration: _decor(
                      label: _tr(
                          ar: 'اكتب الفئة الفرعية',
                          fr: 'Écrire la sous-catégorie',
                          en: 'Type the subcategory'),
                      hint: _tr(
                        ar: 'مثال: اكسسوارات غير مصنفة',
                        fr: 'Ex: Accessoires non classés',
                        en: 'e.g. Unclassified accessories',
                      ),
                      prefixIcon: const Icon(Icons.edit_note_rounded),
                    ),
                    validator: (v) {
                      if (_subCategory?.id != _otherSub.id) return null;
                      return ((v ?? '').trim().isEmpty)
                          ? _tr(ar: 'مطلوب', fr: 'Requis', en: 'Required')
                          : null;
                    },
                  ),
                ],

                // Variant/type dropdown (optional for all categories if taxonomy provides)
                if (variantDefs.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                        'variant_${_category?.id}_${_subCategory?.id}'),
                    initialValue: _safeId(
                        _normalizeStoredOptionToId(_attrs['type'], variantDefs),
                        variantDefs),
                    isExpanded: true,
                    menuMaxHeight: 360,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    items: variantDefs
                        .map((o) => DropdownMenuItem<String>(
                              value: o.en,
                              child: Text(o.of(context)),
                            ))
                        .toList(growable: false),
                    onChanged: (v) => setState(() {
                      if (v == null || v.trim().isEmpty) {
                        _attrs.remove('type');
                        _attrs.remove('type_other');
                        _typeOtherCtl.clear();
                      } else {
                        _attrs['type'] = v.trim();
                        if (v.trim() != 'Other') {
                          _attrs.remove('type_other');
                          _typeOtherCtl.clear();
                        }
                      }
                    }),
                    decoration: _decor(
                      label:
                          '${variantFieldLabelBaseFor(categoryId: _category?.id, subCategoryId: _subCategory?.id).of(context)} (${_tr(ar: 'اختياري', fr: 'opt.', en: 'optional')})',
                      hint: variantFieldHintFor(
                        categoryId: _category?.id,
                        subCategoryId: _subCategory?.id,
                      ).of(context),
                      prefixIcon: const Icon(Icons.tune_rounded),
                    ),
                  ),
                ],

                // Custom type when user chooses "Other"
                if ((_attrs['type'] ?? '').trim() == 'Other') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _typeOtherCtl,
                    textInputAction: TextInputAction.next,
                    onChanged: (v) => _attrs['type_other'] = v.trim(),
                    decoration: _decor(
                      label: variantOtherFieldLabelFor(
                        categoryId: _category?.id,
                        subCategoryId: _subCategory?.id,
                      ).of(context),
                      hint: variantOtherFieldHintFor(
                        categoryId: _category?.id,
                        subCategoryId: _subCategory?.id,
                      ).of(context),
                      prefixIcon: const Icon(Icons.edit_note_rounded),
                    ),
                    validator: (v) {
                      if ((_attrs['type'] ?? '').trim() != 'Other') return null;
                      return ((v ?? '').trim().isEmpty)
                          ? _tr(ar: 'مطلوب', fr: 'Requis', en: 'Required')
                          : null;
                    },
                  ),
                ],

                // Model/series (phones/cars)
                if (allowModel) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _modelCtl,
                    readOnly: true,
                    onTap: _openModelPicker,
                    decoration: _decor(
                      label:
                          '${modelFieldLabelFor(categoryId: _category?.id, subCategoryId: _subCategory?.id).of(context)} (${_tr(ar: 'اختياري', fr: 'opt.', en: 'optional')})',
                      hint: modelFieldHintFor(
                        categoryId: _category?.id,
                        subCategoryId: _subCategory?.id,
                      ).of(context),
                      prefixIcon: const Icon(Icons.tag_outlined),
                      suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ),
                ],
                const SizedBox(height: 12),

                // Price
                TextFormField(
                  controller: _priceCtl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: _decor(
                    label: _tr(
                        ar: 'السعر (MRU) (اختياري)',
                        fr: 'Prix (MRU) (optionnel)',
                        en: 'Price (MRU) (optional)'),
                    hint: _tr(
                        ar: 'مثال: 15000', fr: 'Ex: 15000', en: 'e.g. 15000'),
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                ),

// Warranty (optional, smart duration)
                if (supportsWarranty) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _hasWarranty,
                    onChanged: (v) => _setStateAndSave(() {
                      _hasWarranty = v;
                      if (!v) {
                        _warrantyValue = 0;
                        _warrantyUnit = 'months';
                        _warrantyCustom = false;
                        _warrantyCustomValueCtl.text = '';
                        _warrantyType = 'seller';
                      } else {
                        // sensible default: 24 hours
                        _warrantyValue = 24;
                        _warrantyUnit = 'hours';
                        _warrantyCustom = false;
                        _warrantyCustomValueCtl.text = '24';
                      }
                    }),
                    title: Text(_tr(
                      ar: 'يوجد ضمان (اختياري)',
                      fr: 'Garantie (optionnel)',
                      en: 'Warranty (optional)',
                    )),
                  ),
                  if (_hasWarranty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _tr(ar: 'مدة الضمان', fr: 'Durée', en: 'Duration'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(
                              _tr(ar: '24 ساعة', fr: '24 h', en: '24 hours')),
                          selected: !_warrantyCustom &&
                              _warrantyUnit == 'hours' &&
                              _warrantyValue == 24,
                          onSelected: (_) => _setStateAndSave(() {
                            _warrantyCustom = false;
                            _warrantyValue = 24;
                            _warrantyUnit = 'hours';
                            _warrantyCustomValueCtl.text = '24';
                          }),
                        ),
                        ChoiceChip(
                          label: Text(
                              _tr(ar: 'أسبوع', fr: '1 semaine', en: '1 week')),
                          selected: !_warrantyCustom &&
                              _warrantyUnit == 'weeks' &&
                              _warrantyValue == 1,
                          onSelected: (_) => _setStateAndSave(() {
                            _warrantyCustom = false;
                            _warrantyValue = 1;
                            _warrantyUnit = 'weeks';
                            _warrantyCustomValueCtl.text = '1';
                          }),
                        ),
                        ChoiceChip(
                          label:
                              Text(_tr(ar: 'شهر', fr: '1 mois', en: '1 month')),
                          selected: !_warrantyCustom &&
                              _warrantyUnit == 'months' &&
                              _warrantyValue == 1,
                          onSelected: (_) => _setStateAndSave(() {
                            _warrantyCustom = false;
                            _warrantyValue = 1;
                            _warrantyUnit = 'months';
                            _warrantyCustomValueCtl.text = '1';
                          }),
                        ),
                        ChoiceChip(
                          label: Text(
                              _tr(ar: '3 أشهر', fr: '3 mois', en: '3 months')),
                          selected: !_warrantyCustom &&
                              _warrantyUnit == 'months' &&
                              _warrantyValue == 3,
                          onSelected: (_) => _setStateAndSave(() {
                            _warrantyCustom = false;
                            _warrantyValue = 3;
                            _warrantyUnit = 'months';
                            _warrantyCustomValueCtl.text = '3';
                          }),
                        ),
                        ChoiceChip(
                          label: Text(
                              _tr(ar: '6 أشهر', fr: '6 mois', en: '6 months')),
                          selected: !_warrantyCustom &&
                              _warrantyUnit == 'months' &&
                              _warrantyValue == 6,
                          onSelected: (_) => _setStateAndSave(() {
                            _warrantyCustom = false;
                            _warrantyValue = 6;
                            _warrantyUnit = 'months';
                            _warrantyCustomValueCtl.text = '6';
                          }),
                        ),
                        ChoiceChip(
                          label: Text(_tr(
                              ar: '12 شهر', fr: '12 mois', en: '12 months')),
                          selected: !_warrantyCustom &&
                              _warrantyUnit == 'months' &&
                              _warrantyValue == 12,
                          onSelected: (_) => _setStateAndSave(() {
                            _warrantyCustom = false;
                            _warrantyValue = 12;
                            _warrantyUnit = 'months';
                            _warrantyCustomValueCtl.text = '12';
                          }),
                        ),
                        ChoiceChip(
                          label: Text(_tr(
                              ar: 'مخصص', fr: 'Personnalisé', en: 'Custom')),
                          selected: _warrantyCustom,
                          onSelected: (_) => _setStateAndSave(() {
                            _warrantyCustom = true;
                            if (_warrantyValue <= 0) {
                              _warrantyValue = 7;
                              _warrantyUnit = 'days';
                              _warrantyCustomValueCtl.text = '7';
                            }
                          }),
                        ),
                      ],
                    ),
                    if (_warrantyCustom) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _warrantyCustomValueCtl,
                              keyboardType: TextInputType.number,
                              textDirection: TextDirection.ltr,
                              decoration: _decor(
                                label:
                                    _tr(ar: 'المدة', fr: 'Valeur', en: 'Value'),
                                hint: _tr(
                                    ar: 'مثال: 10',
                                    fr: 'Ex: 10',
                                    en: 'e.g. 10'),
                                prefixIcon: const Icon(Icons.timelapse_rounded),
                              ),
                              onChanged: (s) {
                                final n = int.tryParse(s.trim()) ?? 0;
                                _setStateAndSave(() => _warrantyValue = n);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _warrantyUnit,
                              isExpanded: true,
                              items: _warrantyUnitOrder()
                                  .map((u) => DropdownMenuItem<String>(
                                        value: u,
                                        child: Text(_warrantyUnitUiLabel(u)),
                                      ))
                                  .toList(growable: false),
                              onChanged: (v) => _setStateAndSave(() {
                                _warrantyUnit =
                                    (v ?? 'days').trim().toLowerCase();
                              }),
                              decoration: _decor(
                                label:
                                    _tr(ar: 'الوحدة', fr: 'Unité', en: 'Unit'),
                                prefixIcon:
                                    const Icon(Icons.straighten_rounded),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                          'wtype_${_category?.id}_${_subCategory?.id}'),
                      initialValue: _warrantyType,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(
                          value: 'seller',
                          child: Text(_tr(
                              ar: 'ضمان البائع', fr: 'Vendeur', en: 'Seller')),
                        ),
                        DropdownMenuItem(
                          value: 'brand',
                          child: Text(
                              _tr(ar: 'ضمان شركة', fr: 'Marque', en: 'Brand')),
                        ),
                      ],
                      onChanged: (v) => _setStateAndSave(() {
                        _warrantyType = (v ?? 'seller').trim();
                      }),
                      decoration: _decor(
                        label: _tr(ar: 'نوع الضمان', fr: 'Type', en: 'Type'),
                        prefixIcon: const Icon(Icons.verified_outlined),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _tr(
                        ar: 'يمكنك اختيار مدة جاهزة أو إدخال مدة مخصصة.',
                        fr: 'Choisissez une durée ou saisissez une valeur personnalisée.',
                        en: 'Pick a preset or enter a custom duration.',
                      ),
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ],

// Quick fields (optional)
                if (quick.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    _tr(
                        ar: 'مواصفات سريعة (اختياري)',
                        fr: 'Champs rapides (opt.)',
                        en: 'Quick fields (optional)'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  for (final q in primaryQuick) ...[
                    _quickFieldWidget(q),
                    const SizedBox(height: 12),
                  ],

                  // Jobs seekers: add an extra "Skills" multi-select (human-friendly)
                  if (isJobSeek) ...[
                    _SkillsChipsField(
                      label: _tr(
                          ar: 'المهارات (اختياري)',
                          fr: 'Compétences (opt.)',
                          en: 'Skills (optional)'),
                      options: _defaultJobSkills(),
                      selectedIds: _selectedSkillIds(),
                      otherController: _skillsOtherCtl,
                      onChanged: (ids) => _setStateAndSave(() {
                        _setSelectedSkillIds(ids);
                        _syncMultiOtherTextToAttrs();
                      }),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Extra fields (kept out of the way)
                  if (extraQuick.isNotEmpty) ...[
                    Card(
                      elevation: 0,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceVariant
                          .withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        title: Text(
                          _tr(
                              ar: 'تفاصيل إضافية',
                              fr: 'Détails supplémentaires',
                              en: 'More details'),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          _tr(
                            ar: 'هذه الحقول تساعد الناس يفهمون إعلانك بسرعة.',
                            fr: 'Ces champs rendent votre annonce plus claire.',
                            en: 'These fields make your listing clearer.',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.65),
                          ),
                        ),
                        children: [
                          for (final q in extraQuick) ...[
                            _quickFieldWidget(q),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openLocationCountryPicker() async {
    final locale = Localizations.localeOf(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    final selected = await showModalBottomSheet<CountryCode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String query = '';
        const frequentIso2 = <String>[
          'MR',
          'FR',
          'ES',
          'DE',
          'NL',
          'BE',
          'IT',
          'GB'
        ];
        final frequent =
            kCountryCodes.where((c) => frequentIso2.contains(c.iso2)).toList();
        final rest =
            kCountryCodes.where((c) => !frequentIso2.contains(c.iso2)).toList();

        String pickText(
            {required String ar, required String fr, required String en}) {
          final code = locale.languageCode.toLowerCase();
          if (code == 'fr') return fr;
          if (code == 'en') return en;
          return ar;
        }

        bool matches(CountryCode c, String q) {
          final s = q.trim().toLowerCase();
          if (s.isEmpty) return true;
          return c.dialCode.toLowerCase().contains(s) ||
              c.nameAr.toLowerCase().contains(s) ||
              c.nameFr.toLowerCase().contains(s) ||
              c.nameEn.toLowerCase().contains(s) ||
              c.iso2.toLowerCase().contains(s);
        }

        Widget tile(CountryCode c) {
          final arrow = Icons.keyboard_arrow_down_rounded;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.10),
              child: Text(c.flagEmoji, style: const TextStyle(fontSize: 18)),
            ),
            title: Text(c.nameFor(locale),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(c.dialCode,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 4),
                Icon(arrow, color: Colors.black38),
              ],
            ),
            onTap: () => Navigator.of(ctx).pop(c),
          );
        }

        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.86,
              minChildSize: 0.55,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return StatefulBuilder(
                  builder: (context, setModal) {
                    final filteredFrequent =
                        frequent.where((c) => matches(c, query)).toList();
                    final filteredRest =
                        rest.where((c) => matches(c, query)).toList();

                    Widget sectionTitle(String ar, String fr, String en) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Text(
                          pickText(ar: ar, fr: fr, en: en),
                          style: Theme.of(ctx)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  pickText(
                                      ar: 'اختر الدولة',
                                      fr: 'Choisir un pays',
                                      en: 'Choose a country'),
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: TextField(
                            onChanged: (v) => setModal(() => query = v),
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: pickText(
                                  ar: 'ابحث عن دولة أو كود…',
                                  fr: 'Rechercher un pays ou un code…',
                                  en: 'Search country or code…'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide:
                                    const BorderSide(color: Colors.black12),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide:
                                    const BorderSide(color: Colors.black12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            controller: scrollController,
                            children: [
                              if (filteredFrequent.isNotEmpty) ...[
                                sectionTitle('الأكثر استخدامًا',
                                    'Les plus utilisés', 'Most used'),
                                ...filteredFrequent.map(tile),
                              ],
                              if (filteredRest.isNotEmpty) ...[
                                sectionTitle('كل الدول', 'Tous les pays',
                                    'All countries'),
                                ...filteredRest.map(tile),
                                const SizedBox(height: 16),
                              ],
                              if (filteredFrequent.isEmpty &&
                                  filteredRest.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Center(
                                    child: Text(pickText(
                                        ar: 'لا توجد نتائج',
                                        fr: 'Aucun résultat',
                                        en: 'No results')),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (selected != null) {
      setState(() => _outsideCountry = selected);
    }
  }

  Widget _insideOutsideSegment(ColorScheme cs) {
    final selectedBg = cs.primary.withValues(alpha: 0.12);
    final selectedBorder = cs.primary.withValues(alpha: 0.55);

    Widget seg({
      required bool selected,
      required String label,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: selected ? selectedBorder : Colors.black12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 18,
                    color: selected
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.65)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? cs.primary
                          : cs.onSurface.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          seg(
            selected: !_outsideMa,
            label:
                _tr(ar: 'داخل موريتانيا', fr: 'En Mauritanie', en: 'Inside MR'),
            icon: Icons.location_on_outlined,
            onTap: () => setState(() {
              _outsideMa = false;
              _outsideCountry = null;
              _outsideCityCtl.clear();
            }),
          ),
          const SizedBox(width: 8),
          seg(
            selected: _outsideMa,
            label: _tr(ar: 'خارج موريتانيا', fr: 'À l’étranger', en: 'Abroad'),
            icon: Icons.public,
            onTap: () => setState(() {
              _outsideMa = true;
              _wilaya = null;
              _moughataa = null;
              _neighborhoodCtl.clear();
            }),
          ),
        ],
      ),
    );
  }

  Widget _countryField(ColorScheme cs) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final arrow = Icons.keyboard_arrow_down_rounded;

    return FormField<CountryCode>(
      validator: (_) => (_outsideMa && _outsideCountry == null)
          ? _tr(ar: 'مطلوب', fr: 'Requis', en: 'Required')
          : null,
      builder: (state) {
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await _openLocationCountryPicker();
            state.validate();
          },
          child: InputDecorator(
            decoration: _decor(
              label: _tr(ar: 'الدولة *', fr: 'Pays *', en: 'Country *'),
              hint: _tr(
                  ar: 'اختر الدولة',
                  fr: 'Choisir le pays',
                  en: 'Choose a country'),
              prefixIcon: const Icon(Icons.public),
            ).copyWith(
              errorText: state.hasError ? state.errorText : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _outsideCountry == null
                        ? _tr(
                            ar: 'اختر الدولة',
                            fr: 'Choisir le pays',
                            en: 'Choose a country')
                        : _outsideCountry!
                            .nameFor(Localizations.localeOf(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: _outsideCountry == null
                          ? FontWeight.w600
                          : FontWeight.w900,
                    ),
                  ),
                ),
                if (_outsideCountry != null) ...[
                  const SizedBox(width: 8),
                  Text(_outsideCountry!.flagEmoji,
                      style: const TextStyle(fontSize: 18)),
                ],
                const SizedBox(width: 8),
                Icon(arrow, color: Colors.black38),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stepLocation(ColorScheme cs) {
    final cat = _category?.name.of(context) ?? '—';
    final rawSub = _subCategory?.name.of(context) ?? '—';
    final sub = (_subCategory?.id == _otherSub.id &&
            _subOtherCtl.text.trim().isNotEmpty)
        ? _subOtherCtl.text.trim()
        : rawSub;

    final needsMoughataa = !_outsideMa &&
        (((_wilaya?.id ?? '').trim().startsWith('nouakchott_')) ||
            ((_wilaya?.id ?? '').trim() == 'dakhlet_nouadhibou'));

    return ListView(padding: const EdgeInsets.only(bottom: 120), children: [
      _tipCard(
        cs: cs,
        asset: 'assets/illustrations/publish/location.svg',
        title: _tr(
          ar: 'نصيحة للموقع',
          fr: 'Astuce lieu',
          en: 'Location tip',
        ),
        subtitle: _tr(
          ar: 'اختيار الولاية والحي بدقة يساعد على وصول المشترين القريبين.',
          fr: 'Choisissez la wilaya et le quartier pour attirer les acheteurs proches.',
          en: 'Pick location details. If you are abroad, choose your country.',
        ),
      ),
      _card(
        child: Form(
          key: _locationKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _tr(ar: 'الموقع', fr: 'Lieu', en: 'Location'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              _tr(ar: 'التصنيف', fr: 'Catégorie', en: 'Category'),
              style: TextStyle(
                  color: cs.onSurface.withAlpha(180),
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(cs, cat),
                _chip(cs, sub),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _tr(ar: 'مكان المنتج', fr: 'Emplacement', en: 'Product location'),
              style: TextStyle(
                  color: cs.onSurface.withAlpha(180),
                  fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _insideOutsideSegment(cs),
            const SizedBox(height: 12),
            if (_outsideMa) ...[
              _countryField(cs),
              const SizedBox(height: 12),
              TextFormField(
                controller: _outsideCityCtl,
                textInputAction: TextInputAction.done,
                decoration: _decor(
                  label: _tr(
                      ar: 'المدينة (اختياري)',
                      fr: 'Ville (optionnel)',
                      en: 'City (optional)'),
                  hint: _tr(
                      ar: 'مثال: مدريد', fr: 'Ex: Madrid', en: 'e.g. Madrid'),
                  prefixIcon: const Icon(Icons.location_city_outlined),
                ),
              ),
            ] else ...[
              DropdownButtonFormField<Wilaya>(
                key: ValueKey('wilaya_${_editing?.id ?? "new"}'),
                initialValue: _wilaya,
                decoration: _decor(
                  label: _tr(ar: 'الولاية *', fr: 'Wilaya *', en: 'Wilaya *'),
                  hint: _tr(
                      ar: 'اختر الولاية',
                      fr: 'Choisissez la wilaya',
                      en: 'Select wilaya'),
                  prefixIcon: const Icon(Icons.location_on_outlined),
                ),
                isExpanded: true,
                menuMaxHeight: 360,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                items: [
                  for (final w in maWilayas.where((w) => w.id != '__na__'))
                    DropdownMenuItem(value: w, child: Text(w.name.of(context))),
                ],
                onChanged: (v) => setState(() {
                  _wilaya = v;
                  _moughataa = null;
                  _neighborhoodCtl.clear();
                  _attrs.remove('wilaya_id');
                  _attrs.remove('moughataa_id');
                  _attrs.remove('neighborhood_id');
                }),
                validator: (v) => (v == null)
                    ? _tr(ar: 'مطلوب', fr: 'Requis', en: 'Required')
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Moughataa>(
                key: ValueKey('moughataa_${_wilaya?.id ?? "none"}'),
                initialValue: _moughataa,
                decoration: _decor(
                  label: needsMoughataa
                      ? _tr(
                          ar: 'المقاطعة *',
                          fr: 'Moughataa *',
                          en: 'Moughataa *')
                      : _tr(
                          ar: 'المقاطعة (اختياري)',
                          fr: 'Moughataa (optionnel)',
                          en: 'Moughataa (optional)',
                        ),
                  hint: needsMoughataa
                      ? _tr(
                          ar: 'اختر المقاطعة لتظهر الأحياء',
                          fr: 'Choisissez la moughataa pour afficher les quartiers',
                          en: 'Select moughataa to see neighborhoods',
                        )
                      : _tr(
                          ar: 'اختياري: اختر المقاطعة إذا كانت متوفرة',
                          fr: 'Optionnel: choisissez la moughataa si disponible',
                          en: 'Optional: choose moughataa if available',
                        ),
                  prefixIcon: const Icon(Icons.map_outlined),
                ),
                isExpanded: true,
                menuMaxHeight: 360,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                items: _wilaya == null
                    ? const <DropdownMenuItem<Moughataa>>[]
                    : _wilaya!.moughataas
                        .where((m) => m.id != '__na__')
                        .map((m) => DropdownMenuItem(
                            value: m, child: Text(m.name.of(context))))
                        .toList(growable: false),
                onChanged: (v) => setState(() {
                  _moughataa = v;
                  _neighborhoodCtl.clear();
                  _attrs.remove('moughataa_id');
                  _attrs.remove('neighborhood_id');
                }),
                validator: (v) {
                  if (!needsMoughataa) return null;
                  if (v == null)
                    return _tr(ar: 'مطلوب', fr: 'Requis', en: 'Required');
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _neighborhoodCtl,
                readOnly: true,
                onTap: _openNeighborhoodPicker,
                decoration: _decor(
                  label: _tr(
                      ar: 'الحي/المنطقة', fr: 'Quartier', en: 'Neighborhood'),
                  hint: (needsMoughataa && _moughataa == null)
                      ? _tr(
                          ar: 'اختر المقاطعة أولاً',
                          fr: 'Choisissez d’abord la moughataa',
                          en: 'Choose a moughataa first',
                        )
                      : _tr(
                          ar: 'مثال: تفرغ زينة / عرفات',
                          fr: 'Ex: Tevragh Zeina / Arafat',
                          en: 'e.g. Tevragh Zeina / Arafat',
                        ),
                  prefixIcon: const Icon(Icons.home_work_outlined),
                  suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _locationNoteCtl,
              textInputAction: TextInputAction.newline,
              maxLines: 2,
              decoration: _decor(
                label: _tr(
                    ar: 'ملاحظة (اختياري)',
                    fr: 'Note (optionnel)',
                    en: 'Note (optional)'),
                hint: _tr(
                    ar: 'أي تفاصيل إضافية تساعد المشتري',
                    fr: 'Détails utiles pour l’acheteur',
                    en: 'Extra details for buyers'),
                prefixIcon: const Icon(Icons.notes_outlined),
              ),
            ),
          ]),
        ),
      )
    ]);
  }

  Widget _stepContact(ColorScheme cs) {
    final kind = publishKindFor(
      categoryId: _category?.id,
      subCategoryId: _subCategory?.id,
    );
    final deliveryAllowed = _deliveryApplicable();
// If category doesn't support delivery, force-disable it safely.
    if (!deliveryAllowed && _deliveryEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _deliveryEnabled = false;
          _syncDeliveryAttrs();
        });
      });
    }

    return ListView(padding: const EdgeInsets.only(bottom: 120), children: [
      _tipCard(
        cs: cs,
        asset: 'assets/illustrations/publish/contact.svg',
        title: _tr(
          ar: 'نصيحة للتواصل',
          fr: 'Astuce contact',
          en: 'Contact tip',
        ),
        subtitle: _tr(
          ar: 'اكتب رقمًا صحيحًا وفعل واتساب أو الاتصال لتسهيل التواصل مع المشترين.',
          fr: 'Ajoutez un numéro valide et activez WhatsApp/Appel pour faciliter le contact.',
          en: 'Use a valid number and enable WhatsApp/calls to make it easy for buyers.',
        ),
      ),
      _card(
          child: Form(
              key: _contactKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr(ar: 'التواصل', fr: 'Contact', en: 'Contact'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 14),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: TextFormField(
                        controller: _phoneCtl,
                        keyboardType: TextInputType.phone,
                        decoration: _decor(
                          label: _tr(
                              ar: 'رقم الهاتف / واتساب *',
                              fr: 'Téléphone / WhatsApp *',
                              en: 'Phone / WhatsApp *'),
                          hint: _tr(
                            ar: 'مثال: +222 36 52 66 26',
                            fr: 'Ex: +222 36 52 66 26',
                            en: 'e.g. +222 36 52 66 26',
                          ),
                          prefixIcon: const Icon(Icons.phone_outlined),
                        ),
                        validator: (v) {
                          final t = (v ?? '').trim();
                          if (t.isEmpty) {
                            return _tr(
                                ar: 'الرقم مطلوب',
                                fr: 'Numéro requis',
                                en: 'Phone is required');
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _ToggleTile(
                            icon: Icons.telegram,
                            title: _tr(
                                ar: 'واتساب', fr: 'WhatsApp', en: 'WhatsApp'),
                            value: _allowWhatsApp,
                            onChanged: (v) =>
                                _setStateAndSave(() => _allowWhatsApp = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ToggleTile(
                            icon: Icons.call_outlined,
                            title: _tr(ar: 'اتصال', fr: 'Appel', en: 'Call'),
                            value: _allowCall,
                            onChanged: (v) =>
                                _setStateAndSave(() => _allowCall = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (deliveryAllowed) ...[
                      _ToggleTile(
                        icon: Icons.local_shipping_outlined,
                        title: _tr(
                          ar: 'توصيل عبر Tkii (اختياري)',
                          fr: 'Livraison via Tkii (opt.)',
                          en: 'Delivery via Tkii (optional)',
                        ),
                        value: _deliveryEnabled,
                        onChanged: (v) => _setStateAndSave(() {
                          _deliveryEnabled = v;
                          _syncDeliveryAttrs();
                        }),
                      ),
                    ],
                    if (deliveryAllowed && _deliveryEnabled) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _deliveryFeeCtl,
                        keyboardType: TextInputType.number,
                        decoration: _decor(
                          label: _tr(
                            ar: 'رسوم التوصيل (MRU) (اختياري)',
                            fr: 'Frais de livraison (MRU) (opt.)',
                            en: 'Delivery fee (MRU) (optional)',
                          ),
                          hint: _tr(
                              ar: 'مثال: 200', fr: 'Ex: 200', en: 'e.g. 200'),
                          prefixIcon: const Icon(Icons.payments_outlined),
                        ),
                        onChanged: (_) => _syncDeliveryAttrs(),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _deliveryNoteCtl,
                        maxLines: 2,
                        decoration: _decor(
                          label: _tr(
                            ar: 'ملاحظة للتوصيل (اختياري)',
                            fr: 'Note livraison (opt.)',
                            en: 'Delivery note (optional)',
                          ),
                          hint: _tr(
                            ar: 'مثال: داخل نواكشوط فقط',
                            fr: 'Ex: Nouakchott uniquement',
                            en: 'e.g. Nouakchott only',
                          ),
                          prefixIcon: const Icon(Icons.note_outlined),
                        ),
                        onChanged: (_) => _syncDeliveryAttrs(),
                      ),
                    ]
                  ])))
    ]);
    // style: const TextStyle(fontWeight: FontWeight.w800),
  }
}

class _CategoryPickResult {
  const _CategoryPickResult({required this.category, required this.sub});
  final CategoryNode category;
  final SubCategory sub;
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.categories,
    required this.otherSub,
    this.initialCategory,
  });

  final List<CategoryNode> categories;
  final CategoryNode? initialCategory;
  final SubCategory otherSub;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  int _step = 0; // 0 main category, 1 subcategory
  CategoryNode? _cat;

  String _tr({required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'fr') return fr;
    if (code == 'en') return en;
    return ar;
  }

  @override
  void initState() {
    super.initState();
    _cat = widget.initialCategory;
    _step = (_cat == null) ? 0 : 1;
  }

  IconData _iconForCategory(String id) {
    switch (id) {
      case 'electronics':
        return Icons.phone_iphone_rounded;
      case 'fashion':
        return Icons.checkroom_rounded;
      case 'beauty':
        return Icons.spa_rounded;
      case 'home':
        return Icons.chair_rounded;
      case 'vehicles':
        return Icons.directions_car_rounded;
      case 'real_estate':
        return Icons.home_work_rounded;
      case 'services':
        return Icons.handyman_rounded;
      case 'kids':
        return Icons.toys_rounded;
      case 'sports':
        return Icons.sports_soccer_rounded;
      case 'tools':
        return Icons.build_rounded;
      case 'books':
        return Icons.menu_book_rounded;
      case 'agriculture':
        return Icons.agriculture_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Widget _header(ColorScheme cs) {
    final title = _step == 0
        ? _tr(ar: 'اختر الفئة', fr: 'Choisir catégorie', en: 'Choose category')
        : _tr(
            ar: 'اختر الفئة الفرعية',
            fr: 'Choisir sous-catégorie',
            en: 'Choose subcategory',
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          if (_step == 1)
            IconButton(
              tooltip: _tr(ar: 'رجوع', fr: 'Retour', en: 'Back'),
              onPressed: () => setState(() => _step = 0),
              icon: const Icon(Icons.arrow_back_rounded),
            )
          else
            const SizedBox(width: 48),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
          IconButton(
            tooltip: _tr(ar: 'إغلاق', fr: 'Fermer', en: 'Close'),
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, color: cs.onSurface.withAlpha(220)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h = MediaQuery.sizeOf(context).height;
    final sheetH = (h * 0.88).clamp(420.0, 760.0);

    return SizedBox(
      height: sheetH,
      child: Column(
        children: [
          _header(cs),
          const Divider(height: 1),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _step == 0 ? _buildMainGrid(cs) : _buildSubGrid(cs, _cat!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainGrid(ColorScheme cs) {
    return GridView.builder(
      key: const ValueKey('main'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        // Slightly taller tiles to avoid rare RTL font/line-height overflows
        // on some devices (the infamous 2-4px overflow stripe).
        childAspectRatio: 0.92,
      ),
      itemCount: widget.categories.length,
      itemBuilder: (ctx, i) {
        final c = widget.categories[i];
        final selected = (_cat?.id == c.id);
        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => setState(() {
            _cat = c;
            _step = 1;
          }),
          child: Container(
            decoration: BoxDecoration(
              color: selected ? cs.primary.withAlpha(18) : cs.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? cs.primary.withAlpha(140)
                    : cs.outlineVariant.withAlpha(160),
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withAlpha(18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.outlineVariant.withAlpha(130)),
                  ),
                  child: Icon(
                    _iconForCategory(c.id),
                    color: cs.onSurface.withAlpha(220),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  c.name.of(context),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: selected ? cs.primary : cs.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubGrid(ColorScheme cs, CategoryNode c) {
    final subs = <SubCategory>[...c.sub];
    if (subs.every((s) => s.id != widget.otherSub.id)) {
      subs.add(widget.otherSub);
    }

    return GridView.builder(
      key: const ValueKey('sub'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 3.1,
      ),
      itemCount: subs.length,
      itemBuilder: (ctx, i) {
        final s = subs[i];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context)
              .pop(_CategoryPickResult(category: c, sub: s)),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant.withAlpha(160)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.keyboard_arrow_down_rounded,
                    color: cs.onSurfaceVariant.withAlpha(200)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.name.of(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _YearDropdownField extends StatelessWidget {
  const _YearDropdownField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().year;
    const start = 1970;
    final years = <int>[];
    for (var y = now; y >= start; y--) {
      years.add(y);
    }

    final current = int.tryParse(value);

    return DropdownButtonFormField<int>(
      initialValue:
          (current != null && years.contains(current)) ? current : null,
      isExpanded: true,
      menuMaxHeight: 320,
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      items: years
          .map(
            (y) => DropdownMenuItem<int>(
              value: y,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(y.toString()),
              ),
            ),
          )
          .toList(growable: false),
      onChanged: (v) => onChanged(v?.toString()),
    );
  }
}

class _LanguagesMultiField extends StatelessWidget {
  const _LanguagesMultiField({
    required this.label,
    required this.options,
    required this.selectedIds,
    required this.onChanged,
    required this.otherController,
  });

  final String label;
  final List<L10n3> options;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;
  final TextEditingController otherController;

  String _trByLocale(
    BuildContext context, {
    required String ar,
    required String fr,
    required String en,
  }) {
    return L10n3(ar: ar, fr: fr, en: en).of(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final optionIds = options.map((o) => o.en).toList(growable: false);
    final hasOther = optionIds.contains('Other');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in options) ...[
              FilterChip(
                selected: selectedIds.contains(o.en),
                label: Text(o.of(context)),
                onSelected: (v) {
                  final next = Set<String>.from(selectedIds);
                  if (v) {
                    next.add(o.en);
                  } else {
                    next.remove(o.en);
                  }
                  onChanged(next);
                },
              ),
            ],
          ],
        ),
        if (hasOther && selectedIds.contains('Other')) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: otherController,
            decoration: InputDecoration(
              labelText: _trByLocale(
                context,
                ar: 'لغات أخرى',
                fr: 'Autres langues',
                en: 'Other languages',
              ),
              hintText: _trByLocale(
                context,
                ar: 'اختياري',
                fr: 'Optionnel',
                en: 'Optional',
              ),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              prefixIcon: const Icon(Icons.edit_note_rounded),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          _trByLocale(
            context,
            ar: 'اختياري',
            fr: 'Optionnel',
            en: 'Optional',
          ),
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
  }
}

class _SkillsChipsField extends StatelessWidget {
  const _SkillsChipsField({
    required this.label,
    required this.options,
    required this.selectedIds,
    required this.onChanged,
    required this.otherController,
  });

  final String label;
  final List<L10n3> options;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;
  final TextEditingController otherController;

  String _trByLocale(
    BuildContext context, {
    required String ar,
    required String fr,
    required String en,
  }) {
    return L10n3(ar: ar, fr: fr, en: en).of(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final optionIds = options.map((o) => o.en).toList(growable: false);
    final hasOther = optionIds.contains('Other');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in options) ...[
              FilterChip(
                selected: selectedIds.contains(o.en),
                label: Text(o.of(context)),
                onSelected: (v) {
                  final next = Set<String>.from(selectedIds);
                  if (v) {
                    next.add(o.en);
                  } else {
                    next.remove(o.en);
                  }
                  onChanged(next);
                },
              ),
            ],
          ],
        ),
        if (hasOther && selectedIds.contains('Other')) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: otherController,
            decoration: InputDecoration(
              labelText: _trByLocale(
                context,
                ar: 'مهارات أخرى',
                fr: 'Autres compétences',
                en: 'Other skills',
              ),
              hintText: _trByLocale(
                context,
                ar: 'اختياري',
                fr: 'Optionnel',
                en: 'Optional',
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              prefixIcon: const Icon(Icons.edit_note_rounded),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          _trByLocale(
            context,
            ar: 'اختياري',
            fr: 'Optionnel',
            en: 'Optional',
          ),
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.step, required this.totalSteps});
  final int step;
  final int totalSteps;

  String _tr(BuildContext context,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'fr') return fr;
    if (code == 'en') return en;
    return ar;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final allLabels = <String>[
      _tr(context, ar: 'التصنيف', fr: 'Catégorie', en: 'Category'),
      _tr(context, ar: 'الصور', fr: 'Photos', en: 'Photos'),
      _tr(context, ar: 'المعلومات', fr: 'Infos', en: 'Info'),
      _tr(context, ar: 'الموقع', fr: 'Lieu', en: 'Location'),
      _tr(context, ar: 'التواصل', fr: 'Contact', en: 'Contact'),
      _tr(context, ar: 'المعاينة', fr: 'Aperçu', en: 'Preview'),
      _tr(context, ar: 'السياسات', fr: 'Politiques', en: 'Policies'),
    ];

    final total = totalSteps.clamp(0, allLabels.length - 1);
    final labels = allLabels.take(total + 1).toList(growable: false);
    final safeStep = step.clamp(0, labels.length - 1);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Text('${safeStep + 1}/${labels.length}',
                  style: TextStyle(
                      color: cs.onSurface.withAlpha(170),
                      fontWeight: FontWeight.w800)),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    labels[safeStep],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: (safeStep + 1) / labels.length,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: value ? cs.primary.withAlpha(20) : cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withAlpha(160)),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: value ? cs.primary : cs.onSurface.withAlpha(180)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            )),
            Switch.adaptive(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _SmartImage extends StatelessWidget {
  const _SmartImage({
    required this.path,
    this.fit = BoxFit.cover,
  });
  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget fallback() => Container(
          color: cs.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(Icons.image_not_supported_outlined,
              color: cs.onSurface.withAlpha(120)),
        );

    Widget loading() => Container(
          color: cs.surfaceContainerHighest,
          alignment: Alignment.center,
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        );

    if (path.trim().isEmpty) return fallback();
    if (path.startsWith('http')) {
      return Image.network(path,
          fit: fit, errorBuilder: (_, __, ___) => fallback());
    }
    if (path.startsWith('gs://')) {
      return FutureBuilder<String>(
        future: FirebaseStorage.instance.refFromURL(path).getDownloadURL(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return loading();
          final url = (snap.data ?? '').trim();
          if (url.isEmpty) return fallback();
          return Image.network(url,
              fit: fit, errorBuilder: (_, __, ___) => fallback());
        },
      );
    }
    if (!kIsWeb) {
      final f = File(path);
      return Image.file(f, fit: fit, errorBuilder: (_, __, ___) => fallback());
    }
    return fallback();
  }
}

@immutable
class _VipPlan {
  const _VipPlan({
    required this.id,
    required this.tier,
    required this.rank,
    required this.days,
    required this.priceMru,
  });

  final String id;
  final String tier;
  final int rank;
  final int days;
  final int priceMru;
}
