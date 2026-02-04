import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tiki/features/widgets/similar_products_section.dart';
import 'package:tiki/features/product/data/products_repository.dart';
import 'package:tiki/features/product/domain/app_product.dart';
import 'package:tiki/features/product/state/products_providers.dart';
import '../../../core/mocks/promo_moderation.dart';
import '../../../core/storage/local_store.dart';
import '../../../core/state/likes_controller.dart';
import 'package:tiki/core/state/auth_state.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/i18n/tikki_tr.dart';
import '../../../core/data/ma_locations.dart';
import '../../../core/data/ma_catalog.dart';
import '../../../core/data/publish_taxonomy.dart';
import '../../../core/constants/support_contacts.dart';

/// Product details screen (keeps bottom navigation because it's inside ShellRoute).
///
class ProductDetailsScreen extends ConsumerStatefulWidget {
  const ProductDetailsScreen({super.key, required this.productId});
  final String productId;

  @override
  ConsumerState<ProductDetailsScreen> createState() =>
      _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends ConsumerState<ProductDetailsScreen> {
  bool _recorded = false;
  int _views = 0;

  Future<void> _openExternal(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        _toast(tikkiTr(context,
            ar: 'تعذر فتح الرابط',
            fr: 'Impossible d’ouvrir le lien',
            en: 'Could not open link'));
      }
    } catch (_) {
      if (!mounted) return;
      _toast(tikkiTr(context,
          ar: 'تعذر فتح الرابط',
          fr: 'Impossible d’ouvrir le lien',
          en: 'Could not open link'));
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 950)),
    );
  }

  void _smartBack() {
    final r = GoRouter.of(context);
    if (r.canPop()) {
      r.pop();
    } else {
      context.go('/home');
    }
  }

  String _digitsOnly(String input) {
    final d = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 8) return '222$d'; // common in MR
    return d;
  }

  Uri _waMe(String phone, String message) {
    final p = _digitsOnly(phone);
    final text = Uri.encodeComponent(message);
    return Uri.parse('https://wa.me/$p?text=$text');
  }

  bool _truthy(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    return v == '1' || v == 'true' || v == 'yes' || v == 'y';
  }

  ({bool enabled, int? feeMru, String note}) _deliveryInfo(AppProduct p) {
    final a = p.attrs;
    final enabled = _truthy(a['delivery_enabled'] ?? a['deliveryEnabled']);

    int? fee;
    final feeRaw =
        (a['delivery_fee_mru'] ?? a['deliveryFeeMru'] ?? '').toString();
    if (feeRaw.trim().isNotEmpty) {
      final digits = feeRaw.replaceAll(RegExp(r'[^0-9]'), '');
      fee = int.tryParse(digits);
    }

    final note =
        (a['delivery_note'] ?? a['deliveryNote'] ?? '').toString().trim();
    return (enabled: enabled, feeMru: fee, note: note);
  }

  String _fixTimeAgo(String s) {
    // Safety: some builds/theme can end up spacing French letters like: "i l y a".
    // Normalize it back to "il y a" without affecting other locales.
    return s.replaceAll(
      RegExp(r'\bi\s+l\s+y\s+a\b', caseSensitive: false),
      'il y a',
    );
  }

  /// Seller note (optional) captured in Publish Wizard.
  /// We try a few places to be compatible with older mock data:
  /// - `details` (most common in this project)
  /// - attrs keys: note / sellerNote / seller_note / extra
  String _sellerNote(AppProduct p) {
    final d1 = (p.details ?? '').trim();
    if (d1.isNotEmpty) return d1;

    final a = p.attrs;
    final candidates = <String>[
      (a['note'] ?? '').toString(),
      (a['sellerNote'] ?? '').toString(),
      (a['seller_note'] ?? '').toString(),
      (a['extra'] ?? '').toString(),
      (a['extraNote'] ?? '').toString(),
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    return candidates.isEmpty ? '' : candidates.first;
  }

  bool _isInternalAttrKey(String key) {
    final k = key.trim().toLowerCase();
    if (k.isEmpty) return false;

    // Reserved/internal keys should never be shown publicly.
    if (k.startsWith('__')) return true;
    if (k.endsWith('__')) return true;

    // Generic ids are usually internal (category ids, location ids, etc.).
    if (k == 'id' || k.endsWith('_id')) return true;

    // Promo / reviews / VIP internals.
    if (k.startsWith('promo_') || k.startsWith('review_')) return true;
    if (k.contains('promo_') || k.contains('vip_')) return true;
    if (k.contains('promo') || k.contains('vip')) return true;

    // Location / routing fields (should not be shown in specs).
    if (k == 'wilaya' || k == 'moughataa') return true;
    if (k.contains('wilaya') || k.contains('moughataa')) return true;

    // Publish wizard internal flags
    if (k == 'outside_ma' || k == 'outside_ma_country') return true;
    if (k == 'country' || k == 'country_code' || k == 'countrycode')
      return true;

    // Delivery internals (shown elsewhere as chips)
    if (k.startsWith('delivery_') ||
        k.contains('deliveryfee') ||
        k.contains('delivery_fee')) {
      return true;
    }

    return false;
  }

  String _composeDetails(AppProduct p) {
    final parts = <String>[];

    // Main description (keep it above the bullet specs).
    final desc = (p.description ?? '').trim();
    final alt = (p.subtitle ?? '').trim();
    if (desc.isNotEmpty) {
      parts.add(desc);
    } else if (alt.isNotEmpty) {
      parts.add(alt);
    }

    String _keyNorm(String raw) =>
        raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

    final variantDefs = variantDefsFor(
      context,
      categoryId: p.category,
      subCategoryId: p.subCategory,
    );

    final quickDefs = quickFieldsFor(
      context,
      categoryId: p.category,
      subCategoryId: p.subCategory,
    );

    String _beautifyKey(String raw) {
      final s = raw.trim();
      if (s.isEmpty) return raw;
      return s.replaceAll('_', ' ');
    }

    // Strong bidi isolation for *any* mixed-script segment.
    // This prevents RTL/LTR reordering like "Automatic :transmission".
    String _iso(String s) => '\u2068$s\u2069'; // FSI ... PDI

    String _label(String keyRaw) {
      final k = _keyNorm(keyRaw);

      switch (k) {
        case 'type':
          return variantFieldLabelBaseFor(
            categoryId: p.category,
            subCategoryId: p.subCategory,
          ).of(context);
        case 'brand':
          return tikkiTr(context, ar: 'الماركة', fr: 'Marque', en: 'Brand');
        case 'model':
          return tikkiTr(context, ar: 'الموديل', fr: 'Modèle', en: 'Model');
        case 'languages':
          return tikkiTr(context, ar: 'اللغات', fr: 'Langues', en: 'Languages');
        case 'skills':
          return tikkiTr(context,
              ar: 'المهارات', fr: 'Compétences', en: 'Skills');
        case 'storage':
          return tikkiTr(context, ar: 'السعة', fr: 'Stockage', en: 'Storage');
        case 'color':
          return tikkiTr(context, ar: 'اللون', fr: 'Couleur', en: 'Color');
        case 'condition':
          return tikkiTr(context, ar: 'الحالة', fr: 'État', en: 'Condition');
        case 'year':
          return tikkiTr(context, ar: 'السنة', fr: 'Année', en: 'Year');

        // Mileage: accept common key variants.
        case 'mileage':
        case 'mileage_km':
        case 'mileagekm':
          return tikkiTr(
            context,
            ar: 'المسافة (كم)',
            fr: 'Kilométrage (km)',
            en: 'Mileage (km)',
          );

        // Cars
        case 'transmission':
        case 'gearbox':
          return tikkiTr(
            context,
            ar: 'ناقل الحركة',
            fr: 'Transmission',
            en: 'Transmission',
          );
        case 'fuel':
          return tikkiTr(context, ar: 'الوقود', fr: 'Carburant', en: 'Fuel');
        case 'origin':
          return tikkiTr(context, ar: 'المنشأ', fr: 'Origine', en: 'Origin');

        // Real estate
        case 'area_m2':
        case 'aream2':
          return tikkiTr(context,
              ar: 'المساحة (م²)', fr: 'Surface (m²)', en: 'Area (m²)');
        case 'rooms':
          return tikkiTr(context, ar: 'الغرف', fr: 'Pièces', en: 'Rooms');

        // Location note
        case 'location_note':
        case 'locationnote':
          return tikkiTr(
            context,
            ar: 'ملاحظة الموقع',
            fr: 'Note de localisation',
            en: 'Location note',
          );

        case 'ram':
          return tikkiTr(context, ar: 'الرام', fr: 'RAM', en: 'RAM');
        case 'power':
          return tikkiTr(context,
              ar: 'الطاقة', fr: 'Alimentation', en: 'Power');
        case 'paper':
          return tikkiTr(context,
              ar: 'مقاس الورق', fr: 'Format papier', en: 'Paper size');
        case 'wifi_band':
          return tikkiTr(context, ar: 'النطاق', fr: 'Bande', en: 'Band');
        case 'papers':
          return tikkiTr(context,
              ar: 'الأوراق', fr: 'Papiers', en: 'Documents');
        case 'compatibility':
          return tikkiTr(context,
              ar: 'التوافق', fr: 'Compatibilité', en: 'Compatibility');
        case 'furnished':
          return tikkiTr(context, ar: 'مفروش', fr: 'Meublé', en: 'Furnished');
        case 'contract':
          return tikkiTr(context,
              ar: 'نوع العقد', fr: 'Contrat', en: 'Contract');
        case 'work_mode':
          return tikkiTr(context, ar: 'نمط العمل', fr: 'Mode', en: 'Work mode');
        case 'education':
          return tikkiTr(context,
              ar: 'المستوى الدراسي', fr: 'Études', en: 'Education');
        case 'experience':
          return tikkiTr(context,
              ar: 'الخبرة', fr: 'Expérience', en: 'Experience');
        case 'license':
          return tikkiTr(context,
              ar: 'رخصة سياقة', fr: 'Permis', en: 'Driving license');
        case 'availability':
          return tikkiTr(context,
              ar: 'متاح', fr: 'Disponible', en: 'Availability');
        case 'age_range':
          return tikkiTr(context, ar: 'العمر', fr: 'Âge', en: 'Age');
        case 'fabric':
          return tikkiTr(context, ar: 'القماش', fr: 'Tissu', en: 'Fabric');
        case 'company':
          return tikkiTr(context,
              ar: 'اسم الشركة', fr: "Nom de l'entreprise", en: 'Company');
        case 'size':
          return tikkiTr(context, ar: 'المقاس', fr: 'Pointure', en: 'Size');

        default:
          return _beautifyKey(keyRaw);
      }
    }

    String _unitizeNum(String raw,
        {required String arUnit,
        required String frUnit,
        required String enUnit}) {
      final v = raw.trim();
      if (v.isEmpty) return v;

      // If the user already typed a unit, keep it.
      final hasLetters = RegExp(r'[A-Za-z\u0600-\u06FF]').hasMatch(v);
      if (hasLetters) return v;

      final n = num.tryParse(v.replaceAll(',', '.'));
      if (n == null) return v;

      final unit = tikkiTr(context, ar: arUnit, fr: frUnit, en: enUnit);
      // Keep integers clean.
      final numStr = (n % 1 == 0) ? n.toInt().toString() : n.toString();
      return '$numStr $unit';
    }

    String _localizeTypeValue(String raw) {
      // Localize common phone/car brands when UI language is Arabic.
      // We keep FR/EN values as-is to avoid changing user data semantics.
      final lang = Localizations.localeOf(context).languageCode;
      if (lang != 'ar') return raw;

      final s = raw.trim();
      if (s.isEmpty) return s;

      // If already Arabic, keep it.
      if (RegExp(r'[\u0600-\u06FF]').hasMatch(s)) return s;

      String norm(String x) => x
          .toLowerCase()
          .replaceAll('&', 'and')
          .replaceAll(RegExp(r'[^a-z0-9]+'), '');

      final n = norm(s);

      const ar = <String, String>{
        // Phones
        'iphone': 'آيفون',
        'apple': 'آبل',
        'samsung': 'سامسونج',
        'xiaomi': 'شاومي',
        'huawei': 'هواوي',
        'oppo': 'أوبو',
        'tecno': 'تكنو',
        'infinix': 'إنفينيكس',
        'realme': 'ريلمي',
        'vivo': 'فيفو',
        'nokia': 'نوكيا',
        'sony': 'سوني',
        'googlepixel': 'غوغل بيكسل',
        'pixel': 'بيكسل',

        // Cars (common in Mauritania)
        'toyota': 'تويوتا',
        'nissan': 'نيسان',
        'hyundai': 'هيونداي',
        'kia': 'كيا',
        'honda': 'هوندا',
        'mazda': 'مازدا',
        'mitsubishi': 'ميتسوبيشي',
        'suzuki': 'سوزوكي',
        'mercedes': 'مرسيدس',
        'mercedesbenz': 'مرسيدس',
        'bmw': 'بي إم دبليو',
        'audi': 'أودي',
        'volkswagen': 'فولكسفاغن',
        'vw': 'فولكسفاغن',
        'ford': 'فورد',
        'chevrolet': 'شيفروليه',
        'dacia': 'داسيا',
        'renault': 'رينو',
        'peugeot': 'بيجو',
        'citroen': 'سيتروين',
        'fiat': 'فيات',
        'opel': 'أوبل',
        'skoda': 'سكودا',
        'volvo': 'فولفو',
        'jeep': 'جيب',
        'landrover': 'لاند روفر',
        'rangerover': 'رانج روفر',
        'tesla': 'تسلا',
        'subaru': 'سوبارو',
        'isuzu': 'إيسوزو',
        'iveco': 'إيفيكو',
        'daf': 'داف',
        'man': 'مان',
        'scania': 'سكانيا',
      };

      // Extra aliases
      final alias = <String, String>{
        'mercedes-benz': 'mercedesbenz',
        'mercedesbenz': 'mercedesbenz',
        'land rover': 'landrover',
        'land-rover': 'landrover',
        'rangerover': 'rangerover',
        'google pixel': 'googlepixel',
        'googlepixel': 'googlepixel',
      };

      final key = alias[n] ?? n;
      return ar[key] ?? s;
    }

    String? _fromOpts(String raw, List<L10n3> opts) {
      String normId(String x) => x
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), '');
      final a = normId(raw);
      if (a.isEmpty) return null;
      for (final o in opts) {
        if (a == normId(o.en) || a == normId(o.fr) || a == normId(o.ar)) {
          return o.of(context);
        }
      }
      return null;
    }

    String _joinPretty(List<String> items) {
      final cleaned =
          items.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      return cleaned.join(', ');
    }

    String _localizeLanguageToken(String tok) {
      final t = tok.trim();
      if (t.isEmpty) return '';
      final low = t.toLowerCase();
      // Accept both stable ids and localized strings from older drafts.
      if (low == 'arabic' || t == 'العربية' || t == 'عربية') {
        return tikkiTr(context, ar: 'العربية', fr: 'Arabe', en: 'Arabic');
      }
      if (low == 'french' || t == 'الفرنسية' || t == 'فرنسية') {
        return tikkiTr(context, ar: 'الفرنسية', fr: 'Français', en: 'French');
      }
      if (low == 'english' ||
          t == 'الإنجليزية' ||
          t == 'الانجليزية' ||
          t == 'إنجليزية') {
        return tikkiTr(context, ar: 'الإنجليزية', fr: 'Anglais', en: 'English');
      }
      if (low == 'pulaar' || t == 'البولارية') {
        return tikkiTr(context, ar: 'البولارية', fr: 'Pulaar', en: 'Pulaar');
      }
      if (low == 'soninke' || low == 'soninké' || t == 'السوننكية') {
        return tikkiTr(context, ar: 'السوننكية', fr: 'Soninké', en: 'Soninke');
      }
      if (low == 'wolof' || t == 'الولوفية') {
        return tikkiTr(context, ar: 'الولوفية', fr: 'Wolof', en: 'Wolof');
      }
      if (low == 'other' || t == 'أخرى' || t == 'Autre') {
        return tikkiTr(context, ar: 'أخرى', fr: 'Autre', en: 'Other');
      }
      return t;
    }

    String _localizeSkillToken(String tok) {
      final t = tok.trim();
      if (t.isEmpty) return '';
      final low = t.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      // Stable ids are stored in EN in drafts; accept AR/FR too.
      if (low == 'customer service' ||
          t == 'خدمة العملاء' ||
          t == 'Service client') {
        return tikkiTr(context,
            ar: 'خدمة العملاء', fr: 'Service client', en: 'Customer service');
      }
      if (low == 'sales' || t == 'مبيعات' || t == 'Vente') {
        return tikkiTr(context, ar: 'مبيعات', fr: 'Vente', en: 'Sales');
      }
      if (low == 'accounting' || t == 'محاسبة' || t == 'Comptabilité') {
        return tikkiTr(context,
            ar: 'محاسبة', fr: 'Comptabilité', en: 'Accounting');
      }
      if (low == 'word' || t == 'Word') {
        return tikkiTr(context, ar: 'Word', fr: 'Word', en: 'Word');
      }
      if (low == 'excel' || t == 'Excel') {
        return tikkiTr(context, ar: 'Excel', fr: 'Excel', en: 'Excel');
      }
      if (low == 'design' || t == 'تصميم' || t == 'Design') {
        return tikkiTr(context, ar: 'تصميم', fr: 'Design', en: 'Design');
      }
      if (low == 'driving' || t == 'سياقة' || t == 'Conduite') {
        return tikkiTr(context, ar: 'سياقة', fr: 'Conduite', en: 'Driving');
      }
      if (low == 'cooking' || t == 'طبخ' || t == 'Cuisine') {
        return tikkiTr(context, ar: 'طبخ', fr: 'Cuisine', en: 'Cooking');
      }
      if (low == 'security' ||
          t == 'حراسة' ||
          t == 'Sécurité' ||
          t == 'Securite') {
        return tikkiTr(context, ar: 'حراسة', fr: 'Sécurité', en: 'Security');
      }
      if (low == 'teaching' || t == 'تدريس' || t == 'Enseignement') {
        return tikkiTr(context,
            ar: 'تدريس', fr: 'Enseignement', en: 'Teaching');
      }
      if (low == 'maintenance' || t == 'صيانة' || t == 'Maintenance') {
        return tikkiTr(context,
            ar: 'صيانة', fr: 'Maintenance', en: 'Maintenance');
      }
      if (low == 'programming' || t == 'برمجة' || t == 'Programmation') {
        return tikkiTr(context,
            ar: 'برمجة', fr: 'Programmation', en: 'Programming');
      }
      if (low == 'other' || t == 'أخرى' || t == 'Autre') {
        return tikkiTr(context, ar: 'أخرى', fr: 'Autre', en: 'Other');
      }
      return t;
    }

    String _formatLanguages(String raw) {
      final parts = raw
          .split('|')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.isEmpty) return '';
      final out = <String>[];
      for (final t in parts) {
        if (t.toLowerCase() == 'other') {
          final other = (p.attrs['languages_other'] ?? '').toString().trim();
          final label = _localizeLanguageToken(t);
          if (other.isNotEmpty) {
            out.add('$label: $other');
          } else {
            out.add(label);
          }
        } else {
          out.add(_localizeLanguageToken(t));
        }
      }
      return _joinPretty(out);
    }

    String _formatSkills(String raw) {
      final parts = raw
          .split('|')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.isEmpty) return '';
      final out = <String>[];
      for (final t in parts) {
        if (t.toLowerCase() == 'other') {
          final other = (p.attrs['skills_other'] ?? '').toString().trim();
          final label = tikkiTr(context, ar: 'أخرى', fr: 'Autre', en: 'Other');
          if (other.isNotEmpty) {
            out.add('$label: $other');
          } else {
            out.add(label);
          }
        } else {
          // Keep as-is (already human text), but clean spacing.
          out.add(_localizeSkillToken(t));
        }
      }
      return _joinPretty(out);
    }

    String _val(String keyRaw, dynamic value) {
      final raw = (value ?? '').toString().trim();
      if (raw.isEmpty) return '';

      final k = _keyNorm(keyRaw);
      final low = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

      if (k == 'languages') {
        // Stored as pipe-separated ids: Arabic|French|Other
        return _formatLanguages(raw);
      }

      if (k == 'skills') {
        return _formatSkills(raw);
      }

      // Variant/type: first try to localize using the same taxonomy as Publish Wizard.
      if (k == 'type' || k == 'brand') {
        final viaTax = _fromOpts(raw, variantDefs);
        if (viaTax != null) return viaTax;
        // Fallback (Arabic only): common brand dictionary.
        return _localizeTypeValue(raw);
      }

      // Quick-fields dropdown values: localize by matching stored ids (usually option.en).
      for (final d in quickDefs) {
        if (d.key == k && d.options.isNotEmpty) {
          final viaTax = _fromOpts(raw, d.options);
          if (viaTax != null) return viaTax;
          break;
        }
      }

      Map<String, String> tri(String ar, String fr, String en) =>
          {'ar': ar, 'fr': fr, 'en': en};

      String pick(Map<String, String> t) => tikkiTr(
            context,
            ar: t['ar']!,
            fr: t['fr']!,
            en: t['en']!,
          );

      // --- Condition mapping (handles stored AR/FR too) ---
      if (k == 'condition') {
        final dict = <String, Map<String, String>>{
          'new': tri('جديد', 'Neuf', 'New'),
          'used': tri('مستعمل', 'Occasion', 'Used'),
          'like_new': tri('شبه جديد', 'Comme neuf', 'Like new'),
          'refurbished': tri('مجدّد', 'Reconditionné', 'Refurbished'),
          'open_box': tri('مفتوح', 'Boîte ouverte', 'Open box'),
        };

        final syn = <String, String>{
          // new
          'new': 'new',
          'brand new': 'new',
          'neuf': 'new',
          'nouveau': 'new',
          'جديد': 'new',
          'جديدة': 'new',

          // used
          'used': 'used',
          'secondhand': 'used',
          'second-hand': 'used',
          'second hand': 'used',
          'preowned': 'used',
          'pre-owned': 'used',
          'occasion': 'used',
          'd\'occasion': 'used',
          'مستعمل': 'used',
          'مستعملة': 'used',

          // like new
          'like new': 'like_new',
          'like-new': 'like_new',
          'likenew': 'like_new',
          'comme neuf': 'like_new',
          'شبه جديد': 'like_new',
          'مثل الجديد': 'like_new',

          // refurbished
          'refurbished': 'refurbished',
          'reconditionne': 'refurbished',
          'reconditionné': 'refurbished',
          'مجدّد': 'refurbished',
          'مجدد': 'refurbished',

          // open box
          'open box': 'open_box',
          'boite ouverte': 'open_box',
          'boîte ouverte': 'open_box',
          'مفتوح': 'open_box',
        };

        final id = syn[low];
        if (id != null && dict.containsKey(id)) return pick(dict[id]!);
      }

      // --- Color mapping (handles stored AR/FR too) ---
      if (k == 'color') {
        final dict = <String, Map<String, String>>{
          'white': tri('أبيض', 'Blanc', 'White'),
          'black': tri('أسود', 'Noir', 'Black'),
          'red': tri('أحمر', 'Rouge', 'Red'),
          'blue': tri('أزرق', 'Bleu', 'Blue'),
          'green': tri('أخضر', 'Vert', 'Green'),
          'gray': tri('رمادي', 'Gris', 'Gray'),
          'silver': tri('فضي', 'Argent', 'Silver'),
          'gold': tri('ذهبي', 'Doré', 'Gold'),
          'yellow': tri('أصفر', 'Jaune', 'Yellow'),
          'orange': tri('برتقالي', 'Orange', 'Orange'),
          'purple': tri('بنفسجي', 'Violet', 'Purple'),
          'pink': tri('وردي', 'Rose', 'Pink'),
          'brown': tri('بني', 'Marron', 'Brown'),
        };

        final syn = <String, String>{
          'white': 'white',
          'blanc': 'white',
          'أبيض': 'white',
          'بيضاء': 'white',
          'black': 'black',
          'noir': 'black',
          'أسود': 'black',
          'سوداء': 'black',
          'red': 'red',
          'rouge': 'red',
          'أحمر': 'red',
          'حمراء': 'red',
          'blue': 'blue',
          'bleu': 'blue',
          'أزرق': 'blue',
          'زرقاء': 'blue',
          'green': 'green',
          'vert': 'green',
          'أخضر': 'green',
          'خضراء': 'green',
          'gray': 'gray',
          'grey': 'gray',
          'gris': 'gray',
          'رمادي': 'gray',
          'رمادية': 'gray',
          'silver': 'silver',
          'argent': 'silver',
          'فضي': 'silver',
          'فضية': 'silver',
          'gold': 'gold',
          'doré': 'gold',
          'dore': 'gold',
          'or': 'gold',
          'ذهبي': 'gold',
          'ذهبية': 'gold',
          'yellow': 'yellow',
          'jaune': 'yellow',
          'أصفر': 'yellow',
          'صفراء': 'yellow',
          'orange': 'orange',
          'برتقالي': 'orange',
          'purple': 'purple',
          'violet': 'purple',
          'بنفسجي': 'purple',
          'pink': 'pink',
          'rose': 'pink',
          'وردي': 'pink',
          'brown': 'brown',
          'marron': 'brown',
          'بني': 'brown',
        };

        final id = syn[low];
        if (id != null && dict.containsKey(id)) return pick(dict[id]!);
      }

      // --- Transmission mapping ---
      if (k == 'transmission' || k == 'gearbox') {
        final syn = <String, String>{
          'automatic': 'automatic',
          'auto': 'automatic',
          'أوتوماتيك': 'automatic',
          'اوتوماتيك': 'automatic',
          'automatique': 'automatic',
          'manuelle': 'manual',
          'manual': 'manual',
          'manuel': 'manual',
          'يدوي': 'manual',
        };
        final id = syn[low];
        if (id == 'automatic') {
          return tikkiTr(context,
              ar: 'أوتوماتيك', fr: 'Automatique', en: 'Automatic');
        }
        if (id == 'manual') {
          return tikkiTr(context, ar: 'يدوي', fr: 'Manuelle', en: 'Manual');
        }
      }

      // --- Origin mapping ---
      if (k == 'origin') {
        final syn = <String, String>{
          'imported': 'imported',
          'import': 'imported',
          'importé': 'imported',
          'importe': 'imported',
          'مستورَد': 'imported',
          'مستورد': 'imported',
          'local': 'local',
          'محلي': 'local',
        };
        final id = syn[low];
        if (id == 'imported') {
          return tikkiTr(context, ar: 'مستورَد', fr: 'Importé', en: 'Imported');
        }
        if (id == 'local') {
          return tikkiTr(context, ar: 'محلي', fr: 'Local', en: 'Local');
        }
      }

      // --- Fuel mapping ---
      if (k == 'fuel') {
        final syn = <String, String>{
          'hybrid': 'hybrid',
          'هجين': 'hybrid',
          'essence': 'petrol',
          'petrol': 'petrol',
          'gasoline': 'petrol',
          'gas': 'petrol',
          'gaz': 'petrol',
          'بنزين': 'petrol',
          'diesel': 'diesel',
          'gasoil': 'diesel',
          'ديزل': 'diesel',
          'electric': 'electric',
          'électrique': 'electric',
          'electrique': 'electric',
          'كهربائي': 'electric',
        };
        final id = syn[low];
        if (id == 'hybrid') {
          return tikkiTr(context, ar: 'هجين', fr: 'Hybride', en: 'Hybrid');
        }
        if (id == 'petrol') {
          return tikkiTr(context, ar: 'بنزين', fr: 'Essence', en: 'Petrol');
        }
        if (id == 'diesel') {
          return tikkiTr(context, ar: 'ديزل', fr: 'Diesel', en: 'Diesel');
        }
        if (id == 'electric') {
          return tikkiTr(context,
              ar: 'كهربائي', fr: 'Électrique', en: 'Electric');
        }
      }

      // --- Units for numeric fields ---
      if (k == 'mileage' || k == 'mileage_km' || k == 'mileagekm') {
        return _unitizeNum(raw, arUnit: 'كم', frUnit: 'km', enUnit: 'km');
      }
      if (k == 'area_m2' || k == 'aream2') {
        return _unitizeNum(raw, arUnit: 'م²', frUnit: 'm²', enUnit: 'm²');
      }

      // Normalize common booleans
      if (raw == 'true' || raw == 'false') {
        return (raw == 'true')
            ? tikkiTr(context, ar: 'نعم', fr: 'Oui', en: 'Yes')
            : tikkiTr(context, ar: 'لا', fr: 'Non', en: 'No');
      }

      return raw;
    }

    if (p.attrs.isNotEmpty) {
      // Avoid duplicating the seller note if stored in attrs.
      const skipKeys = <String>{
        'note',
        'sellerNote',
        'seller_note',
        'extra',
        'extraNote',
        'languages_other',
        'skills_other',
      };

      final lines = p.attrs.entries
          .where((e) => !skipKeys.contains(e.key))
          .where((e) => !PromoKeys.isReserved(e.key))
          .where((e) => !_isInternalAttrKey(e.key))
          .map((e) {
            final label = _label(e.key);
            final value = _val(e.key, e.value);
            if (value.trim().isEmpty) return '';
            return '• ${_iso(label)}: ${_iso(value)}';
          })
          .where((s) => s.trim().length > 3)
          .toList();

      if (lines.isNotEmpty) {
        if (parts.isNotEmpty) parts.add('');
        parts.addAll(lines);
      }
    }

    return parts.join('\n');
  }

  void _openWarrantyPolicy(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tikkiTr(ctx,
                      ar: 'سياسة الضمان',
                      fr: 'Politique de garantie',
                      en: 'Warranty policy'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 10),
                Text(
                  tikkiTr(
                    ctx,
                    ar: 'الضمان معلومة يحددها البائع. التطبيق لا يضمن صحة الضمان.قبل الدفع، اتفق مع البائع على شروط الضمان واحتفظ بما يثبت ذلك.',
                    fr: 'La garantie est déclarée par le vendeur. L’application ne vérifie pas.Avant de payer, confirmez les conditions et gardez une preuve.',
                    en: 'Warranty is seller-declared. The app does not verify it.Before paying, confirm terms and keep proof.',
                  ),
                  style: TextStyle(
                      color: cs.onSurface.withAlpha(199),
                      height: 1.35,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _blockSellerOnly(AppProduct p) async {
    final phone = (p.phone ?? '').trim();
    if (phone.isEmpty) {
      _toast(tikkiTr(context,
          ar: 'لا يوجد رقم للبائع لحظره.',
          fr: "Aucun numéro vendeur à bloquer.",
          en: "No seller phone to block."));
      return;
    }
    try {
      final store = ref.read(localStoreProvider);
      await store.blockSeller(phone);
      if (!mounted) return;
      _toast(tikkiTr(context,
          ar: 'تم حظر البائع. لن ترى منتجاته بعد الآن.',
          fr: "Vendeur bloqué. Vous ne verrez plus ses annonces.",
          en: "Seller blocked. You won't see their products."));
      context.pop();
    } catch (_) {
      _toast(tikkiTr(context,
          ar: 'تعذر الحظر حالياً.',
          fr: "Impossible de bloquer maintenant.",
          en: "Couldn't block right now."));
    }
  }

  Future<void> _reportAndBlock(AppProduct p) async {
    final result = await _showReportDialog();
    if (result == null) return;

    final phone = (p.phone ?? '').trim();

    try {
      final store = ref.read(localStoreProvider);
      await store.addProductReport(
        productId: p.id,
        sellerPhone: phone,
        reasonId: result['reasonId'] ?? 'other',
        note: (result['note'] ?? '').trim().isEmpty ? null : result['note'],
      );

      // Auto-block after reporting (as requested).
      if (phone.isNotEmpty) {
        await store.blockSeller(phone);
      }

      if (!mounted) return;
      _toast(tikkiTr(context,
          ar: phone.isNotEmpty
              ? 'تم إرسال الإبلاغ وحظر البائع.'
              : 'تم إرسال الإبلاغ.',
          fr: phone.isNotEmpty
              ? "Signalement envoyé + vendeur bloqué."
              : "Signalement envoyé.",
          en: phone.isNotEmpty ? "Reported + seller blocked." : "Reported."));
      context.pop();
    } catch (_) {
      _toast(tikkiTr(context,
          ar: 'تعذر إرسال الإبلاغ حالياً.',
          fr: "Impossible d'envoyer le signalement.",
          en: "Couldn't send report."));
    }
  }

  Future<Map<String, String>?> _showReportDialog() async {
    // reasons: id -> localized label
    final reasons = <Map<String, String>>[
      {'id': 'spam', 'ar': 'إعلان مزعج/سبام', 'fr': 'Spam', 'en': 'Spam'},
      {'id': 'fraud', 'ar': 'احتيال', 'fr': 'Arnaque', 'en': 'Fraud'},
      {
        'id': 'prohibited',
        'ar': 'محتوى ممنوع',
        'fr': 'Contenu interdit',
        'en': 'Prohibited content'
      },
      {
        'id': 'wrong',
        'ar': 'معلومات خاطئة',
        'fr': 'Infos incorrectes',
        'en': 'Incorrect information'
      },
      {'id': 'other', 'ar': 'سبب آخر', 'fr': 'Autre', 'en': 'Other'},
    ];

    return showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        String selected = reasons.first['id']!;
        final noteCtrl = TextEditingController();

        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            final isOther = selected == 'other';

            Widget reasonTile(Map<String, String> r) {
              final id = r['id']!;
              final isSel = id == selected;
              return ListTile(
                onTap: () => setStateDialog(() => selected = id),
                leading: Icon(
                  isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                ),
                title: Text(
                    tikkiTr(context, ar: r['ar']!, fr: r['fr']!, en: r['en']!)),
              );
            }

            return AlertDialog(
              title: Text(tikkiTr(context,
                  ar: 'إبلاغ عن المنتج', fr: 'Signaler', en: 'Report')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final r in reasons) reasonTile(r),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: tikkiTr(context,
                            ar: 'تفاصيل (اختياري)',
                            fr: 'Détails (optionnel)',
                            en: 'Details (optional)'),
                        hintText: isOther
                            ? tikkiTr(context,
                                ar: 'اكتب السبب هنا (إلزامي في "سبب آخر")',
                                fr: 'Écrivez la raison ici (obligatoire pour "Autre")',
                                en: 'Write the reason here (required for "Other")')
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(tikkiTr(context,
                      ar: 'إلغاء', fr: 'Annuler', en: 'Cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    final note = noteCtrl.text.trim();
                    if (isOther && note.isEmpty) {
                      _toast(tikkiTr(context,
                          ar: 'اكتب سبب الإبلاغ.',
                          fr: 'Veuillez écrire la raison.',
                          en: 'Please write a reason.'));
                      return;
                    }
                    Navigator.of(ctx).pop({
                      'reasonId': selected,
                      'note': note,
                    });
                  },
                  child: Text(tikkiTr(context,
                      ar: 'إرسال', fr: 'Envoyer', en: 'Submit')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pid = widget.productId.trim();
    // Load from Firestore
    final asyncP = ref.watch(productByIdProvider(pid));
    return asyncP.when(
      loading: () => _loadingScaffold(context),
      error: (e, _) => _errorScaffold(context, e),
      data: (ap) {
        if (ap == null) return _notFoundScaffold(context);

        if (!_recorded) {
          _recorded = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Record recently viewed locally (for UX), and increment views remotely.
            Future<void>(() async {
              try {
                final store = ref.read(localStoreProvider);
                final prev = store.getRecentlyViewedIds();
                final next = <String>[pid, ...prev.where((e) => e != pid)];
                await store.setRecentlyViewedIds(
                    next.take(30).toList(growable: false));
              } catch (_) {}

              try {
                final store = ref.read(localStoreProvider);
                final auth = ref.read(authControllerProvider);
                final uid = (auth.userId ?? '').trim();
                final viewerKey = uid.isNotEmpty
                    ? uid
                    : await store.getOrCreateDeviceId();

                // Unique per day (viewerKey = uid or device id)
                final shouldCount =
                    await store.markProductViewedToday(pid, viewerKey: viewerKey);

                if (shouldCount) {
                  await ref.read(productsRepositoryProvider).incrementUniqueViewPerDay(
                        pid,
                        viewerKey: viewerKey,
                      );
                }
              } catch (_) {}
            });
          });
        }

        return _buildForProduct(context, ap);
      },
    );
  }

  Widget _buildForProduct(BuildContext context, AppProduct product) {
    final prod = product;
    final cs = Theme.of(context).colorScheme;
    final liked = ref.watch(likesProvider.select((s) => s.contains(prod.id)));
    final auth = ref.watch(authControllerProvider);
    final isOwner = auth.isSignedIn && (auth.userId ?? '') == (prod.sellerId);

    final warrantyLabel = _warrantyLabel(context, prod);
    final delivery = _deliveryInfo(prod);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              surfaceTintColor: Theme.of(context).scaffoldBackgroundColor,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: _smartBack,
              ),
              actions: [
                IconButton(
                  tooltip: tikkiTr(context,
                      ar: 'مشاركة', fr: 'Partager', en: 'Share'),
                  onPressed: () {
                    const link = 'https://tiki.app';
                    SharePlus.instance
                        .share(ShareParams(text: link, subject: 'TIKI'));
                  },
                  icon: const Icon(Icons.share_outlined),
                ),
                PopupMenuButton<String>(
                  tooltip:
                      tikkiTr(context, ar: 'المزيد', fr: 'Plus', en: 'More'),
                  onSelected: (v) async {
                    final p = prod;
                    if (v == 'report') {
                      await _reportAndBlock(p);
                    } else if (v == 'block') {
                      await _blockSellerOnly(p);
                    }
                  },
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'report',
                      child: Text(tikkiTr(context,
                          ar: 'إبلاغ + حظر البائع',
                          fr: "Signaler + Bloquer",
                          en: 'Report + Block')),
                    ),
                    PopupMenuItem<String>(
                      value: 'block',
                      child: Text(tikkiTr(context,
                          ar: 'حظر البائع فقط',
                          fr: 'Bloquer vendeur',
                          en: 'Block seller')),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert),
                ),
                IconButton(
                  tooltip: liked
                      ? tikkiTr(context,
                          ar: 'إزالة من الإعجابات', fr: 'Retirer', en: 'Unlike')
                      : tikkiTr(context, ar: 'إعجاب', fr: 'Aimer', en: 'Like'),
                  onPressed: () async {
                    await ref.read(likesProvider.notifier).toggle(prod.id);
                  },
                  color: liked ? const Color(0xFFFF4D6D) : cs.onSurfaceVariant,
                  icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
                ),
              ],
            ),

            // Image
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    // Slightly shorter than 1:1 to keep the header compact.
                    aspectRatio: 1.12,
                    child: _MediaGallery(
                      images: prod.images,
                      heroTag: 'prod_${prod.id}',
                    ),
                  ),
                ),
              ),
            ),

            // Title + price + meta
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prod.title,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          height: 1.25),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        final sid = (prod.sellerId).trim();
                        if (sid.isEmpty) return;
                        final name = (prod.sellerName).trim();
                        final qp = name.isNotEmpty
                            ? '?name=${Uri.encodeComponent(name)}'
                            : '';
                        context.push('/seller/$sid$qp');
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${tikkiTr(context, ar: 'البائع', fr: 'Vendeur', en: 'Seller')}: ${prod.sellerName}',
                              style: TextStyle(
                                color: cs.primary.withAlpha(235),
                                fontWeight: FontWeight.w900,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        // Price (0 means negotiable -> show nothing)
                        if (prod.price > 0)
                          Text(
                            Formatters.priceMRU(prod.price),
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: cs.primary),
                          ),
                        if (prod.price > 0 &&
                            prod.oldPrice != null &&
                            prod.oldPrice! > prod.price)
                          Text(
                            Formatters.priceMRU(prod.oldPrice!),
                            style: TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        _Pill(
                            text: formatMaLocationSmart(
                              context,
                              wilayaRaw: prod.wilaya,
                              moughataaRaw: prod.moughataa,
                              attrs: prod.attrs,
                            ),
                            icon: Icons.location_on_outlined),
                        _Pill(
                            text: _fixTimeAgo(
                                Formatters.timeAgo(context, prod.publishedAt)),
                            icon: Icons.schedule),
                        if (delivery.enabled)
                          _Pill(
                            text: delivery.feeMru != null &&
                                    (delivery.feeMru ?? 0) > 0
                                ? tikkiTr(
                                    context,
                                    ar: 'توصيل: ${Formatters.priceMRU(delivery.feeMru!)}',
                                    fr: 'Livraison: ${Formatters.priceMRU(delivery.feeMru!)}',
                                    en: 'Delivery: ${Formatters.priceMRU(delivery.feeMru!)}',
                                  )
                                : tikkiTr(
                                    context,
                                    ar: 'توصيل متاح',
                                    fr: 'Livraison disponible',
                                    en: 'Delivery available',
                                  ),
                            icon: Icons.local_shipping_outlined,
                          ),
                        // Views count is shown on the seller side (My Listings),
                        // but hidden on the public product details page.
                        if (warrantyLabel != null)
                          _Pill(
                              text: warrantyLabel,
                              icon: Icons.verified_outlined),
                        if (prod.isSold)
                          _Pill(
                            text: tikkiTr(context,
                                ar: 'مباع', fr: 'Vendu', en: 'Sold'),
                            icon: Icons.check_circle_outline,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Product details (expandable)
                    Builder(
                      builder: (ctx) {
                        final text = _composeDetails(prod).trim();
                        if (text.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tikkiTr(ctx,
                                  ar: 'تفاصيل المنتج',
                                  fr: 'Détails du produit',
                                  en: 'Product details'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                            const SizedBox(height: 6),
                            _ExpandableText(
                              text: text,
                              maxLines: 4,
                              style: TextStyle(
                                height: 1.35,
                                color: cs.onSurface.withAlpha(210),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        );
                      },
                    ),

                    // Seller note (optional) shown only when non-empty.
                    Builder(
                      builder: (ctx) {
                        String _norm(String s) =>
                            s.trim().replaceAll(RegExp(r'\s+'), ' ');

                        final note = _norm(_sellerNote(prod));
                        if (note.isEmpty) return const SizedBox.shrink();

                        // Avoid showing the seller note when it duplicates the main description.
                        final mainDesc = _norm(
                            ((prod.description ?? '').trim().isNotEmpty)
                                ? (prod.description ?? '')
                                : (prod.subtitle ?? ''));
                        if (mainDesc.isNotEmpty && note == mainDesc) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tikkiTr(ctx,
                                  ar: 'ملاحظة البائع',
                                  fr: 'Note du vendeur',
                                  en: 'Seller note'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                            const SizedBox(height: 6),
                            _ExpandableText(
                              text: note,
                              maxLines: 3,
                              style: TextStyle(
                                height: 1.35,
                                color: cs.onSurface.withAlpha(210),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        );
                      },
                    ),

                    if (warrantyLabel != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              tikkiTr(context,
                                  ar: 'هذا المنتج عليه ضمان',
                                  fr: 'Ce produit a une garantie',
                                  en: 'This product has a warranty'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _openWarrantyPolicy(context),
                            child: Text(tikkiTr(context,
                                ar: 'السياسة', fr: 'Politique', en: 'Policy')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Promo / VIP details (only the owner can see).
                    Builder(
                      builder: (ctx) {
                        if (!isOwner) return const SizedBox.shrink();

                        final status = PromoModeration.promoStatus(prod);
                        if (status == PromoStatus.none) {
                          return const SizedBox.shrink();
                        }

                        String statusLabel() {
                          switch (status) {
                            case PromoStatus.pending:
                              return tikkiTr(ctx,
                                  ar: 'قيد المراجعة',
                                  fr: 'En attente',
                                  en: 'Pending');
                            case PromoStatus.approved:
                              return tikkiTr(ctx,
                                  ar: 'مفعّل', fr: 'Actif', en: 'Active');
                            case PromoStatus.rejected:
                              return tikkiTr(ctx,
                                  ar: 'مرفوض', fr: 'Refusé', en: 'Rejected');
                            case PromoStatus.none:
                            default:
                              return tikkiTr(ctx,
                                  ar: 'غير مفعل',
                                  fr: 'Inactif',
                                  en: 'Inactive');
                          }
                        }

                        DateTime? _dt(String? ms) {
                          final v = (ms ?? '').trim();
                          if (v.isEmpty) return null;
                          final i = int.tryParse(v);
                          if (i == null) return null;
                          return DateTime.fromMillisecondsSinceEpoch(i);
                        }

                        String formatDt(DateTime? d) {
                          if (d == null) return '—';
                          final l = MaterialLocalizations.of(ctx);
                          final date = l.formatFullDate(d);
                          final tod = TimeOfDay.fromDateTime(d);
                          return '$date • ${l.formatTimeOfDay(tod)}';
                        }

                        final pkg = PromoModeration.packageById(
                            prod.attrs[PromoKeys.promoPkgId]);
                        final promoDays = PromoModeration.promoDays(prod);
                        final promoPrice = PromoModeration.promoPriceMru(prod);
                        final tx =
                            (prod.attrs[PromoKeys.promoTxId] ?? '').trim();
                        final reqAt =
                            _dt(prod.attrs[PromoKeys.promoRequestedAtMs]);
                        final until = PromoModeration.promoUntil(prod);
                        final rejectReason =
                            (prod.attrs[PromoKeys.promoRejectReason] ?? '')
                                .trim();

                        return Container(
                          margin: const EdgeInsets.only(top: 8, bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: cs.outlineVariant),
                            color: cs.surface,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.star_rounded, color: cs.primary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tikkiTr(ctx,
                                          ar: 'معلومات الترويج (VIP)',
                                          fr: 'Infos promotion (VIP)',
                                          en: 'Promotion info (VIP)'),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      color: cs.primary.withAlpha(20),
                                    ),
                                    child: Text(
                                      statusLabel(),
                                      style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: cs.primary),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                tikkiTr(ctx,
                                    ar: 'هذا القسم يظهر لك فقط (صاحب الإعلان).',
                                    fr: 'Cette section est visible uniquement par vous (vendeur).',
                                    en: 'This section is visible only to you (the seller).'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface.withAlpha(170),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _InfoRow(
                                  label: tikkiTr(ctx,
                                      ar: 'الباقة',
                                      fr: 'Forfait',
                                      en: 'Package'),
                                  value: (() {
                                    if (pkg != null) return pkg!.titleOf(ctx);
                                    if (promoDays != null) {
                                      final label = tikkiTr(ctx,
                                          ar: 'VIP • $promoDays يوم',
                                          fr: 'VIP • $promoDays jours',
                                          en: 'VIP • $promoDays days');
                                      if (promoPrice != null &&
                                          promoPrice! > 0) {
                                        return '$label • ${promoPrice} MRU';
                                      }
                                      return label;
                                    }
                                    return '—';
                                  })()),
                              _InfoRow(
                                  label: tikkiTr(ctx,
                                      ar: 'رقم العملية',
                                      fr: 'Transaction',
                                      en: 'Transaction'),
                                  value: tx.isEmpty ? '—' : tx),
                              _InfoRow(
                                  label: tikkiTr(ctx,
                                      ar: 'تاريخ الطلب',
                                      fr: 'Demandé',
                                      en: 'Requested'),
                                  value: formatDt(reqAt)),
                              _InfoRow(
                                  label: tikkiTr(ctx,
                                      ar: 'ينتهي', fr: 'Expire', en: 'Expires'),
                                  value: formatDt(until)),
                              if (status == PromoStatus.rejected &&
                                  rejectReason.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  tikkiTr(ctx,
                                      ar: 'سبب الرفض: $rejectReason',
                                      fr: 'Raison: $rejectReason',
                                      en: 'Reason: $rejectReason'),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: cs.error),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    if (delivery.enabled) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withAlpha(150),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: cs.outlineVariant.withAlpha(120)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.local_shipping_outlined,
                                color: cs.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tikkiTr(context,
                                        ar: 'التوصيل',
                                        fr: 'Livraison',
                                        en: 'Delivery'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    delivery.feeMru != null &&
                                            (delivery.feeMru ?? 0) > 0
                                        ? tikkiTr(
                                            context,
                                            ar: 'رسوم تقديرية: ${Formatters.priceMRU(delivery.feeMru!)}',
                                            fr: 'Frais estimés: ${Formatters.priceMRU(delivery.feeMru!)}',
                                            en: 'Estimated fee: ${Formatters.priceMRU(delivery.feeMru!)}',
                                          )
                                        : tikkiTr(
                                            context,
                                            ar: 'متاح (حسب الاتفاق)',
                                            fr: 'Disponible (selon accord)',
                                            en: 'Available (by agreement)',
                                          ),
                                    style: TextStyle(
                                      color: cs.onSurface.withAlpha(210),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (delivery.note.trim().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      delivery.note,
                                      style: TextStyle(
                                        color: cs.onSurface.withAlpha(200),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.tonal(
                              onPressed: () {
                                final loc = formatMaLocationSmart(
                                  context,
                                  wilayaRaw: prod.wilaya,
                                  moughataaRaw: prod.moughataa,
                                  attrs: prod.attrs,
                                );
                                final msg = tikkiTr(
                                  context,
                                  ar: 'مرحبا، أريد طلب توصيل لهذا المنتج عبر Tikki:\n${prod.title}\nالموقع: $loc\nرقم البائع: ${prod.phone}\nID: ${prod.id}',
                                  fr: 'Bonjour, je veux demander une livraison via Tikki:\n${prod.title}\nLieu: $loc\nTéléphone vendeur: ${prod.phone}\nID: ${prod.id}',
                                  en: 'Hello, I want to request delivery via Tikki:\n${prod.title}\nLocation: $loc\nSeller phone: ${prod.phone}\nID: ${prod.id}',
                                );
                                _openExternal(_waMe(kSupportWhatsApp, msg));
                              },
                              child: Text(tikkiTr(context,
                                  ar: 'اطلب', fr: 'Demander', en: 'Request')),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Contact buttons
                    _ContactBar(
                      phone: prod.phone,
                      allowWhatsApp: prod.allowWhatsApp,
                      allowCall: prod.allowCall,
                      onOpenWhatsApp: (p) => _openExternal(
                        _waMe(
                          p,
                          tikkiTr(
                            context,
                            ar: 'مرحبا، أريد هذا المنتج: ${prod.title}',
                            fr: 'Bonjour, je veux ce produit: ${prod.title}',
                            en: 'Hello, I want this item: ${prod.title}',
                          ),
                        ),
                      ),
                      onOpenCall: (p) =>
                          _openExternal(Uri.parse('tel:${_digitsOnly(p)}')),
                      onMissingPhone: () => _toast(tikkiTr(
                        context,
                        ar: 'رقم الهاتف غير متوفر حاليا',
                        fr: 'Numéro indisponible',
                        en: 'Phone not available',
                      )),
                    ),
                  ],
                ),
              ),
            ),

            // Similar products
            SliverToBoxAdapter(
              child: SimilarProductsSection(current: prod),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: _smartBack,
        ),
        title: const Text(''),
      ),
      body: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _errorScaffold(BuildContext context, Object error) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: _smartBack,
        ),
        title: const Text(''),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            tikkiTr(
              context,
              ar: 'تعذر تحميل المنتج. حاول مرة أخرى.\n$error',
              fr: 'Impossible de charger le produit. Réessayez.\n$error',
              en: 'Could not load product. Please try again.\n$error',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _notFoundScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: _smartBack,
        ),
        title: const Text(''),
      ),
      body: Center(
        child: Text(
          tikkiTr(context,
              ar: 'هذا المنتج غير موجود',
              fr: 'Produit introuvable',
              en: 'Product not found'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  static String? _warrantyLabel(BuildContext context, AppProduct p) {
    if (!p.hasWarranty) return null;
    final v = p.warrantyValue;
    final unit = p.warrantyUnit;
    if (v == null || unit == null || v <= 0) return null;

    String unitLabel(String u) {
      switch (u) {
        case 'days':
          return tikkiTr(context, ar: 'يوم', fr: 'jour', en: 'day');
        case 'weeks':
          return tikkiTr(context, ar: 'أسبوع', fr: 'semaine', en: 'week');
        case 'years':
          return tikkiTr(context, ar: 'سنة', fr: 'an', en: 'year');
        default:
          return tikkiTr(context, ar: 'شهر', fr: 'mois', en: 'month');
      }
    }

    final u = unitLabel(unit);
    final plural = (v == 1) ? u : _pluralize(context, u);
    return tikkiTr(context,
        ar: 'ضمان $v $plural',
        fr: 'Garantie $v $plural',
        en: '$v $plural warranty');
  }

  static String _pluralize(BuildContext context, String word) {
    // Simple pluralization for FR/EN; AR is already handled by short label.
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    if (code == 'en') return word.endsWith('s') ? word : '${word}s';
    if (code == 'fr') return word.endsWith('s') ? word : '${word}s';
    return word; // AR
  }
}

class _ContactBar extends StatelessWidget {
  const _ContactBar({
    required this.phone,
    required this.allowWhatsApp,
    required this.allowCall,
    required this.onOpenWhatsApp,
    required this.onOpenCall,
    required this.onMissingPhone,
  });

  final String? phone;
  final bool allowWhatsApp;
  final bool allowCall;
  final void Function(String phone) onOpenWhatsApp;
  final void Function(String phone) onOpenCall;
  final VoidCallback onMissingPhone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = phone?.trim();
    final hasPhone = p != null && p.isNotEmpty;

    final baseStyle = FilledButton.styleFrom(
      minimumSize: const Size(0, 42),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      textStyle: const TextStyle(fontWeight: FontWeight.w900),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: (!hasPhone || !allowCall)
                ? onMissingPhone
                : () => onOpenCall(p!),
            icon: const Icon(Icons.call_outlined),
            label: Text(_tt(context, ar: 'اتصال', fr: 'Appel', en: 'Call')),
            style: baseStyle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: (!hasPhone || !allowWhatsApp)
                ? onMissingPhone
                : () => onOpenWhatsApp(p!),
            icon: const Icon(Icons.chat_bubble_outline),
            label: Text(
                _tt(context, ar: 'واتساب', fr: 'WhatsApp', en: 'WhatsApp')),
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary.withAlpha(31),
              foregroundColor: cs.primary,
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }

  static String _tt(BuildContext c,
      {required String ar, required String fr, required String en}) {
    final code = Localizations.localeOf(c).languageCode.toLowerCase();
    if (code == 'fr') return fr;
    if (code == 'en') return en;
    return ar;
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: cs.onSurface.withAlpha(170),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(166),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outline.withAlpha(128)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _SafeImage extends StatelessWidget {
  const _SafeImage({required this.url, this.fit = BoxFit.cover});
  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget fallback() => Container(
          color: cs.surfaceContainerHighest.withAlpha(140),
          alignment: Alignment.center,
          child: Icon(Icons.image_outlined, color: cs.onSurface.withAlpha(89)),
        );

    final u = url.trim();
    if (u.startsWith('http')) {
      return Image.network(
        u,
        fit: fit,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        loadingBuilder: (c, child, progress) {
          if (progress == null) return child;
          return fallback();
        },
        errorBuilder: (_, __, ___) => fallback(),
      );
    }
    if (u.isEmpty) return fallback();

    // Local file path (picked from gallery/camera)
    if (!kIsWeb &&
        (u.startsWith('/') || u.startsWith('file:') || u.contains('\\'))) {
      final path = u.startsWith('file:') ? Uri.parse(u).toFilePath() : u;
      return Image.file(
        File(path),
        fit: fit,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) => fallback(),
      );
    }

    return Image.asset(
      u,
      fit: fit,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, __, ___) => fallback(),
    );
  }
}

class _MediaGallery extends StatefulWidget {
  const _MediaGallery({required this.images, required this.heroTag});
  final List<String> images;
  final String heroTag;

  @override
  State<_MediaGallery> createState() => _MediaGalleryState();
}

class _MediaGalleryState extends State<_MediaGallery> {
  late final PageController _ctl;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    _ctl = PageController();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _openViewer(int initial) {
    final imgs = widget.images.where((e) => e.trim().isNotEmpty).toList();
    if (imgs.isEmpty) return;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) {
        return _ImageViewerDialog(
          images: imgs,
          initialIndex: initial.clamp(0, imgs.length - 1),
          heroTag: widget.heroTag,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final imgs = widget.images.where((e) => e.trim().isNotEmpty).toList();

    if (imgs.isEmpty) {
      return const _SafeImage(url: '');
    }

    return Stack(
      children: [
        PageView.builder(
          controller: _ctl,
          itemCount: imgs.length,
          onPageChanged: (v) => setState(() => _i = v),
          itemBuilder: (ctx, index) {
            return InkWell(
              onTap: () => _openViewer(index),
              child: Hero(
                tag: '${widget.heroTag}_$index',
                child: _SafeImage(url: imgs[index]),
              ),
            );
          },
        ),
        if (imgs.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(115),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: cs.outline.withAlpha(80)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(imgs.length, (idx) {
                    final sel = idx == _i;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: sel ? 14 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: sel
                            ? Colors.white.withAlpha(240)
                            : Colors.white.withAlpha(120),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ImageViewerDialog extends StatefulWidget {
  const _ImageViewerDialog({
    required this.images,
    required this.initialIndex,
    required this.heroTag,
  });
  final List<String> images;
  final int initialIndex;
  final String heroTag;

  @override
  State<_ImageViewerDialog> createState() => _ImageViewerDialogState();
}

class _ImageViewerDialogState extends State<_ImageViewerDialog> {
  late final PageController _ctl;
  late int _i;

  @override
  void initState() {
    super.initState();
    _i = widget.initialIndex;
    _ctl = PageController(initialPage: _i);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _ctl,
              itemCount: widget.images.length,
              onPageChanged: (v) => setState(() => _i = v),
              itemBuilder: (ctx, index) {
                return Center(
                  child: Hero(
                    tag: '${widget.heroTag}_$index',
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: _SafeImage(
                        url: widget.images[index],
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              left: 8,
              top: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                color: Colors.white,
              ),
            ),
            Positioned(
              right: 12,
              top: 14,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(140),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: cs.outline.withAlpha(70)),
                ),
                child: Text(
                  '${_i + 1}/${widget.images.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({
    required this.text,
    this.maxLines = 3,
    this.style,
  });

  final String text;
  final int maxLines;
  final TextStyle? style;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    final dir = Directionality.of(context);

    return LayoutBuilder(
      builder: (ctx, c) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textDirection: dir,
          maxLines: widget.maxLines,
          ellipsis: '…',
        )..layout(maxWidth: c.maxWidth);
        final overflow = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: style,
              maxLines: _expanded ? null : widget.maxLines,
              overflow:
                  _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (overflow)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                  ),
                  child: Text(
                    _expanded
                        ? tikkiTr(context,
                            ar: 'إخفاء', fr: 'Réduire', en: 'Less')
                        : tikkiTr(context,
                            ar: 'المزيد', fr: 'Plus', en: 'More'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
