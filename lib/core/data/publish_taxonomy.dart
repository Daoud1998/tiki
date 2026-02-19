import 'package:flutter/material.dart';

import 'ma_catalog.dart';

@immutable
class QuickFieldDef {
  const QuickFieldDef({
    required this.key,
    required this.label,
    this.options = const <L10n3>[],
    this.icon = Icons.tune_rounded,
  });

  final String key;
  final L10n3 label;

  /// Options are localized at runtime via [optionsOf].
  final List<L10n3> options;

  final IconData icon;

  List<String> optionsOf(BuildContext context) =>
      options.map((o) => o.of(context)).toList(growable: false);
}

/// A lightweight intent profile for publish UI.
/// We keep it simple so the app can hide irrelevant fields automatically.
enum PublishKind {
  goods,
  electronics,
  vehicles,
  realEstate,
  services,
  jobs,
  agri,
}

PublishKind publishKindFor({
  required String? categoryId,
  required String? subCategoryId,
}) {
  final cat = (categoryId ?? '').trim();
  if (cat == 'electronics') return PublishKind.electronics;
  if (cat == 'vehicles') return PublishKind.vehicles;
  if (cat == 'real_estate') return PublishKind.realEstate;
  if (cat == 'services') return PublishKind.services;
  if (cat == 'jobs') return PublishKind.jobs;
  if (cat == 'agri_livestock') return PublishKind.agri;
  return PublishKind.goods;
}

/// "Condition" makes sense for physical items, but not for real estate/services/jobs.
bool supportsConditionFor({
  required String? categoryId,
  required String? subCategoryId,
}) {
  final kind =
      publishKindFor(categoryId: categoryId, subCategoryId: subCategoryId);
  if (kind == PublishKind.realEstate) return false;
  if (kind == PublishKind.services) return false;
  if (kind == PublishKind.jobs) return false;
  return true;
}

/// Delivery/shipping is not relevant for jobs/services/real estate, and for most vehicles.
/// We still allow delivery for small items like vehicle parts.
bool supportsDeliveryFor({
  required String? categoryId,
  required String? subCategoryId,
}) {
  final cat = (categoryId ?? '').trim();
  final sub = (subCategoryId ?? '').trim();

  final kind =
      publishKindFor(categoryId: categoryId, subCategoryId: subCategoryId);

  if (kind == PublishKind.realEstate) return false;
  if (kind == PublishKind.services) return false;
  if (kind == PublishKind.jobs) return false;

  // Vehicles: allow only "parts" (everything else is pickup only).
  if (kind == PublishKind.vehicles) {
    if (sub == 'parts') return true;
    return false;
  }

  // Defensive fallback if ids change or a client stores free-form strings.
  final c = cat.toLowerCase();
  final s = sub.toLowerCase();
  if (c.contains('real_estate') || c.contains('immobilier')) return false;
  if (c.contains('service') || s.contains('service')) return false;
  if (c.contains('job') || s.contains('job') || s.startsWith('jobs_'))
    return false;

  return true;
}

/// Warranty (guarantee) is relevant for physical goods, but **not** for
/// jobs/services/real-estate/vehicles (pickup & contracts differ), and not for
/// promo/offer-style listings.
bool supportsWarrantyFor({
  required String? categoryId,
  required String? subCategoryId,
}) {
  final kind =
      publishKindFor(categoryId: categoryId, subCategoryId: subCategoryId);

  // Not eligible categories.
  if (kind == PublishKind.jobs) return false;
  if (kind == PublishKind.services) return false;
  if (kind == PublishKind.realEstate) return false;
  if (kind == PublishKind.vehicles) return false;
  if (kind == PublishKind.agri) return false;

  final cat = (categoryId ?? '').trim().toLowerCase();
  final sub = (subCategoryId ?? '').trim().toLowerCase();

  // Defensive exclusions for legacy/free-form ids.
  if (cat.contains('job') || sub.contains('job')) return false;
  if (cat.contains('service') || sub.contains('service')) return false;
  if (cat.contains('real_estate') || cat.contains('immobilier')) return false;
  if (cat.contains('vehicle') || cat.contains('car') || sub.contains('car')) {
    return false;
  }
  if (cat.contains('promo') || cat.contains('offer') || sub.contains('offer')) {
    return false;
  }

  // Default: physical goods.
  return true;
}

/// Returns a list of "type/variant" options for the selected (category/subcategory).
/// If empty => no dropdown shown.
List<String> variantOptionsFor(
  BuildContext context, {
  required String? categoryId,
  required String? subCategoryId,
}) {
  final id = (subCategoryId ?? categoryId ?? '').trim();
  if (id.isEmpty) return const <String>[];

  final list = _variants[id];
  if (list == null || list.isEmpty) return const <String>[];

  return list.map((o) => o.of(context)).toList(growable: false);
}

/// Returns the raw variant definitions (localized labels) for the selected (category/subcategory).
/// Use this when you need a stable stored value (we recommend storing `option.en` as an id).
List<L10n3> variantDefsFor(
  BuildContext context, {
  required String? categoryId,
  required String? subCategoryId,
}) {
  final id = (subCategoryId ?? categoryId ?? '').trim();
  if (id.isEmpty) return const <L10n3>[];
  return _variants[id] ?? const <L10n3>[];
}

/// Label for the "variant/type" dropdown depending on category context.
/// For example: phones/cars => Brand, real estate => Type, etc.
L10n3 variantFieldLabelBaseFor({
  required String? categoryId,
  required String? subCategoryId,
}) {
  final cat = (categoryId ?? '').trim();
  final sub = (subCategoryId ?? '').trim();

  if (cat == 'electronics' && sub == 'phones') {
    return const L10n3(ar: 'الماركة', fr: 'Marque', en: 'Brand');
  }
  if (cat == 'vehicles' &&
      (sub == 'cars' || sub == 'suv4x4' || sub == 'trucks')) {
    return const L10n3(ar: 'الماركة', fr: 'Marque', en: 'Brand');
  }
  if (cat == 'vehicles' && sub == 'parts') {
    return const L10n3(ar: 'نوع القطعة', fr: 'Type de pièce', en: 'Part type');
  }
  if (cat == 'real_estate') {
    return const L10n3(
        ar: 'نوع العقار', fr: 'Type de bien', en: 'Property type');
  }
  return const L10n3(ar: 'النوع', fr: 'Type', en: 'Type');
}

L10n3 variantFieldHintFor({
  required String? categoryId,
  required String? subCategoryId,
}) {
  final cat = (categoryId ?? '').trim();
  final sub = (subCategoryId ?? '').trim();

  if (cat == 'electronics' && sub == 'phones') {
    return const L10n3(
      ar: 'اختر ماركة الهاتف (اختياري)',
      fr: 'Choisir la marque (optionnel)',
      en: 'Select brand (optional)',
    );
  }
  if (cat == 'vehicles' &&
      (sub == 'cars' || sub == 'suv4x4' || sub == 'trucks')) {
    return const L10n3(
      ar: 'اختر ماركة السيارة (اختياري)',
      fr: 'Choisir la marque (optionnel)',
      en: 'Select brand (optional)',
    );
  }
  if (cat == 'vehicles' && sub == 'parts') {
    return const L10n3(
      ar: 'اختر نوع القطعة (اختياري)',
      fr: 'Choisir le type de pièce (optionnel)',
      en: 'Select part type (optional)',
    );
  }
  if (cat == 'real_estate') {
    return const L10n3(
      ar: 'اختر نوع العقار (اختياري)',
      fr: 'Choisir le type (optionnel)',
      en: 'Select type (optional)',
    );
  }
  return const L10n3(
    ar: 'اختياري: اختر النوع إذا كان مناسباً',
    fr: 'Optionnel: choisissez le type si applicable',
    en: 'Optional: select type if applicable',
  );
}

L10n3 variantOtherFieldLabelFor({
  required String? categoryId,
  required String? subCategoryId,
}) {
  final cat = (categoryId ?? '').trim();
  final sub = (subCategoryId ?? '').trim();

  if (cat == 'electronics' && sub == 'phones') {
    return const L10n3(
        ar: 'اكتب الماركة', fr: 'Écrire la marque', en: 'Type the brand');
  }
  if (cat == 'vehicles' &&
      (sub == 'cars' || sub == 'suv4x4' || sub == 'trucks')) {
    return const L10n3(
        ar: 'اكتب الماركة', fr: 'Écrire la marque', en: 'Type the brand');
  }
  if (cat == 'vehicles' && sub == 'parts') {
    return const L10n3(
        ar: 'اكتب نوع القطعة', fr: 'Écrire le type', en: 'Type the part type');
  }
  return const L10n3(
      ar: 'اكتب النوع', fr: 'Écrire le type', en: 'Type the type');
}

L10n3 variantOtherFieldHintFor({
  required String? categoryId,
  required String? subCategoryId,
}) {
  final cat = (categoryId ?? '').trim();
  final sub = (subCategoryId ?? '').trim();

  if (cat == 'electronics' && sub == 'phones') {
    return const L10n3(
        ar: 'مثال: Nothing', fr: 'Ex: Nothing', en: 'e.g. Nothing');
  }
  if (cat == 'vehicles' &&
      (sub == 'cars' || sub == 'suv4x4' || sub == 'trucks')) {
    return const L10n3(ar: 'مثال: Seat', fr: 'Ex: Seat', en: 'e.g. Seat');
  }
  if (cat == 'vehicles' && sub == 'parts') {
    return const L10n3(
        ar: 'مثال: راديتر', fr: 'Ex: Radiateur', en: 'e.g. Radiator');
  }
  return const L10n3(
      ar: 'مثال: Tecno Spark 10',
      fr: 'Ex: Tecno Spark 10',
      en: 'e.g. Tecno Spark 10');
}

/// When true, the publish UI should show an extra "Model/Series" field (free text).
bool supportsModelFieldFor({
  required String? categoryId,
  required String? subCategoryId,
}) {
  final cat = (categoryId ?? '').trim();
  final sub = (subCategoryId ?? '').trim();
  if (cat == 'electronics' && sub == 'phones') return true;
  if (cat == 'vehicles' &&
      (sub == 'cars' || sub == 'suv4x4' || sub == 'trucks')) return true;
  return false;
}

L10n3 modelFieldLabelFor({
  required String? categoryId,
  required String? subCategoryId,
}) {
  final cat = (categoryId ?? '').trim();
  final sub = (subCategoryId ?? '').trim();
  if (cat == 'electronics' && sub == 'phones') {
    return const L10n3(ar: 'الموديل', fr: 'Modèle', en: 'Model');
  }
  if (cat == 'vehicles') {
    return const L10n3(ar: 'الموديل', fr: 'Modèle', en: 'Model');
  }
  return const L10n3(ar: 'التفاصيل', fr: 'Détails', en: 'Details');
}

L10n3 modelFieldHintFor({
  required String? categoryId,
  required String? subCategoryId,
}) {
  final cat = (categoryId ?? '').trim();
  final sub = (subCategoryId ?? '').trim();
  if (cat == 'electronics' && sub == 'phones') {
    return const L10n3(
      ar: 'مثال: iPhone 13 Pro أو Tecno Spark 10',
      fr: 'Ex: iPhone 13 Pro ou Tecno Spark 10',
      en: 'e.g. iPhone 13 Pro or Tecno Spark 10',
    );
  }
  if (cat == 'vehicles' &&
      (sub == 'cars' || sub == 'suv4x4' || sub == 'trucks')) {
    return const L10n3(
      ar: 'مثال: Hilux 2016 أو Corolla',
      fr: 'Ex: Hilux 2016 ou Corolla',
      en: 'e.g. Hilux 2016 or Corolla',
    );
  }
  return const L10n3(ar: 'اختياري', fr: 'Optionnel', en: 'Optional');
}

/// Returns extra optional fields to help users publish faster.
/// Default: condition (new/used) for physical categories.
List<QuickFieldDef> quickFieldsFor(
  BuildContext context, {
  required String? categoryId,
  required String? subCategoryId,
}) {
  final id = (subCategoryId ?? categoryId ?? '').trim();

  final list = <QuickFieldDef>[];

  if (supportsConditionFor(
      categoryId: categoryId, subCategoryId: subCategoryId)) {
    list.add(
      const QuickFieldDef(
        key: 'condition',
        label: L10n3(ar: 'الحالة', fr: 'État', en: 'Condition'),
        options: <L10n3>[
          L10n3(ar: 'جديد', fr: 'Neuf', en: 'New'),
          L10n3(ar: 'مستعمل', fr: "D'occasion", en: 'Used'),
          L10n3(ar: 'شبه جديد', fr: 'Comme neuf', en: 'Like new'),
          L10n3(ar: 'غير محدد', fr: 'Non précisé', en: 'Not specified'),
        ],
        icon: Icons.verified_outlined,
      ),
    );
  }

  final extra = _quick[id];
  if (extra != null) list.addAll(extra);
  return list;
}

const L10n3 _other = L10n3(ar: 'أخرى', fr: 'Autre', en: 'Other');

const List<L10n3> _colors = <L10n3>[
  L10n3(ar: 'أسود', fr: 'Noir', en: 'Black'),
  L10n3(ar: 'أبيض', fr: 'Blanc', en: 'White'),
  L10n3(ar: 'أزرق', fr: 'Bleu', en: 'Blue'),
  L10n3(ar: 'أحمر', fr: 'Rouge', en: 'Red'),
  L10n3(ar: 'أخضر', fr: 'Vert', en: 'Green'),
  L10n3(ar: 'رمادي', fr: 'Gris', en: 'Gray'),
  L10n3(ar: 'ذهبي', fr: 'Doré', en: 'Gold'),
  L10n3(ar: 'فضي', fr: 'Argent', en: 'Silver'),
  _other,
];

const List<L10n3> _sizes = <L10n3>[
  L10n3(ar: 'XS', fr: 'XS', en: 'XS'),
  L10n3(ar: 'S', fr: 'S', en: 'S'),
  L10n3(ar: 'M', fr: 'M', en: 'M'),
  L10n3(ar: 'L', fr: 'L', en: 'L'),
  L10n3(ar: 'XL', fr: 'XL', en: 'XL'),
  L10n3(ar: 'XXL', fr: 'XXL', en: 'XXL'),
  _other,
];

final Map<String, List<L10n3>> _variants = {
  // Electronics (brands / types)
  'phones': [
    L10n3(ar: 'آيفون', fr: 'Iphone', en: 'Iphone'),
    L10n3(ar: 'سامسونج', fr: 'Samsung', en: 'Samsung'),
    L10n3(ar: 'شاومي', fr: 'Xiaomi', en: 'Xiaomi'),
    L10n3(ar: 'هواوي', fr: 'Huawei', en: 'Huawei'),
    L10n3(ar: 'تكنو', fr: 'Tecno', en: 'Tecno'),
    L10n3(ar: 'إنفينيكس', fr: 'Infinix', en: 'Infinix'),
    L10n3(ar: 'أوبو', fr: 'Oppo', en: 'Oppo'),
    L10n3(ar: 'ريلمي', fr: 'Realme', en: 'Realme'),
    L10n3(ar: 'فيفو', fr: 'Vivo', en: 'Vivo'),
    L10n3(ar: 'آيتل', fr: 'Itel', en: 'Itel'),
    L10n3(ar: 'نوكيا', fr: 'Nokia', en: 'Nokia'),
    L10n3(ar: 'هونر', fr: 'HONOR', en: 'HONOR'),
    L10n3(ar: 'موتورولا', fr: 'Motorola', en: 'Motorola'),
    L10n3(ar: 'ون بلس', fr: 'OnePlus', en: 'OnePlus'),
    L10n3(ar: 'غوغل بيكسل', fr: 'Google Pixel', en: 'Google Pixel'),
    L10n3(ar: 'سوني', fr: 'Sony', en: 'Sony'),
    _other,
  ],
  'tablets': [
    L10n3(ar: 'آيباد', fr: 'iPad', en: 'iPad'),
    L10n3(ar: 'سامسونج تاب', fr: 'Samsung Tab', en: 'Samsung Tab'),
    L10n3(ar: 'هواوي', fr: 'Huawei', en: 'Huawei'),
    L10n3(ar: 'لينوفو', fr: 'Lenovo', en: 'Lenovo'),
    L10n3(ar: 'شاومي', fr: 'Xiaomi', en: 'Xiaomi'),
    _other,
  ],
  'computers': [
    L10n3(ar: 'حاسوب محمول', fr: 'Portable', en: 'Laptop'),
    L10n3(ar: 'حاسوب مكتبي', fr: 'Bureau', en: 'Desktop'),
    L10n3(ar: 'AIO', fr: 'Tout-en-un', en: 'All-in-one'),
    L10n3(ar: 'ألعاب', fr: 'Gaming', en: 'Gaming'),
    _other,
  ],
  'tv_audio': [
    L10n3(ar: 'سامسونج', fr: 'Samsung', en: 'Samsung'),
    L10n3(ar: 'إل جي', fr: 'LG', en: 'LG'),
    L10n3(ar: 'سوني', fr: 'Sony', en: 'Sony'),
    L10n3(ar: 'تي سي إل', fr: 'TCL', en: 'TCL'),
    L10n3(ar: 'هايسنس', fr: 'Hisense', en: 'Hisense'),
    _other,
  ],
  'gaming': [
    L10n3(ar: 'بلايستيشن', fr: 'PlayStation', en: 'PlayStation'),
    L10n3(ar: 'إكس بوكس', fr: 'Xbox', en: 'Xbox'),
    L10n3(ar: 'نينتندو', fr: 'Nintendo', en: 'Nintendo'),
    L10n3(ar: 'ألعاب الكمبيوتر', fr: 'PC', en: 'PC'),
    _other,
  ],
  'cameras': [
    L10n3(ar: 'كانون', fr: 'Canon', en: 'Canon'),
    L10n3(ar: 'نيكون', fr: 'Nikon', en: 'Nikon'),
    L10n3(ar: 'سوني', fr: 'Sony', en: 'Sony'),
    L10n3(ar: 'غو برو', fr: 'GoPro', en: 'GoPro'),
    _other,
  ],
  'wearables': [
    L10n3(ar: 'آبل واتش', fr: 'Apple Watch', en: 'Apple Watch'),
    L10n3(ar: 'سامسونج', fr: 'Samsung', en: 'Samsung'),
    L10n3(ar: 'هواوي', fr: 'Huawei', en: 'Huawei'),
    L10n3(ar: 'شاومي', fr: 'Xiaomi', en: 'Xiaomi'),
    L10n3(ar: 'غارمين', fr: 'Garmin', en: 'Garmin'),
    _other,
  ],
  'smart_home': [
    L10n3(ar: 'كاميرا مراقبة', fr: 'Caméra', en: 'Camera'),
    L10n3(ar: 'مصابيح ذكية', fr: 'Ampoules', en: 'Smart bulbs'),
    L10n3(ar: 'مقبس/قاطع', fr: 'Prise/Interrupteur', en: 'Plug/Switch'),
    L10n3(ar: 'مساعد صوتي', fr: 'Assistant', en: 'Voice assistant'),
    L10n3(ar: 'أجهزة أخرى', fr: 'Autres appareils', en: 'Other devices'),
    _other,
  ],
  'printers': [
    L10n3(ar: 'حبر', fr: 'Jet d’encre', en: 'Inkjet'),
    L10n3(ar: 'ليزر', fr: 'Laser', en: 'Laser'),
    L10n3(ar: 'حرارية', fr: 'Thermique', en: 'Thermal'),
    L10n3(ar: 'سكانر', fr: 'Scanner', en: 'Scanner'),
    _other,
  ],
  'network': [
    L10n3(ar: 'راوتر', fr: 'Routeur', en: 'Router'),
    L10n3(ar: 'مودم', fr: 'Modem', en: 'Modem'),
    L10n3(ar: 'مقوي إشارة', fr: 'Répéteur', en: 'Repeater'),
    L10n3(ar: 'سويتش', fr: 'Switch', en: 'Switch'),
    _other,
  ],
  'components': [
    L10n3(ar: 'معالج CPU', fr: 'CPU', en: 'CPU'),
    L10n3(ar: 'كرت شاشة GPU', fr: 'GPU', en: 'GPU'),
    L10n3(ar: 'RAM', fr: 'RAM', en: 'RAM'),
    L10n3(ar: 'SSD', fr: 'SSD', en: 'SSD'),
    L10n3(ar: 'HDD', fr: 'HDD', en: 'HDD'),
    L10n3(ar: 'لوحة أم', fr: 'Carte mère', en: 'Motherboard'),
    L10n3(ar: 'مزود طاقة', fr: 'Alimentation', en: 'Power supply'),
    L10n3(ar: 'صندوق/تبريد', fr: 'Boîtier/Refroid.', en: 'Case/Cooling'),
    _other,
  ],

  // Vehicles (brands)
  'cars': [
    L10n3(ar: 'تويوتا', fr: 'Toyota', en: 'Toyota'),
    L10n3(ar: 'نيسان', fr: 'Nissan', en: 'Nissan'),
    L10n3(ar: 'هيونداي', fr: 'Hyundai', en: 'Hyundai'),
    L10n3(ar: 'كيا', fr: 'Kia', en: 'Kia'),
    L10n3(ar: 'مرسيدس-بنز', fr: 'Mercedes-Benz', en: 'Mercedes-Benz'),
    L10n3(ar: 'بي إم دبليو', fr: 'BMW', en: 'BMW'),
    L10n3(ar: 'بيجو', fr: 'Peugeot', en: 'Peugeot'),
    L10n3(ar: 'رينو', fr: 'Renault', en: 'Renault'),
    L10n3(ar: 'فولكسفاغن', fr: 'Volkswagen', en: 'Volkswagen'),
    L10n3(ar: 'فورد', fr: 'Ford', en: 'Ford'),
    L10n3(ar: 'شيفروليه', fr: 'Chevrolet', en: 'Chevrolet'),
    L10n3(ar: 'ميتسوبيشي', fr: 'Mitsubishi', en: 'Mitsubishi'),
    L10n3(ar: 'سوزوكي', fr: 'Suzuki', en: 'Suzuki'),
    L10n3(ar: 'هوندا', fr: 'Honda', en: 'Honda'),
    L10n3(ar: 'مازدا', fr: 'Mazda', en: 'Mazda'),
    L10n3(ar: 'أودي', fr: 'Audi', en: 'Audi'),
    L10n3(ar: 'أوبل', fr: 'Opel', en: 'Opel'),
    L10n3(ar: 'فيات', fr: 'Fiat', en: 'Fiat'),
    L10n3(ar: 'داسيا', fr: 'Dacia', en: 'Dacia'),
    L10n3(ar: 'سيتروين', fr: 'Citroën', en: 'Citroën'),
    L10n3(ar: 'سكودا', fr: 'Škoda', en: 'Škoda'),
    L10n3(ar: 'شانجان', fr: 'Changan', en: 'Changan'),
    L10n3(ar: 'جيلي', fr: 'Geely', en: 'Geely'),
    L10n3(ar: 'شيري', fr: 'Chery', en: 'Chery'),
    _other,
  ],
  'suv4x4': [
    L10n3(ar: 'تويوتا', fr: 'Toyota', en: 'Toyota'),
    L10n3(ar: 'نيسان', fr: 'Nissan', en: 'Nissan'),
    L10n3(ar: 'ميتسوبيشي', fr: 'Mitsubishi', en: 'Mitsubishi'),
    L10n3(ar: 'لاند روفر', fr: 'Land Rover', en: 'Land Rover'),
    L10n3(ar: 'هيونداي', fr: 'Hyundai', en: 'Hyundai'),
    L10n3(ar: 'كيا', fr: 'Kia', en: 'Kia'),
    L10n3(ar: 'جيب', fr: 'Jeep', en: 'Jeep'),
    L10n3(ar: 'فورد', fr: 'Ford', en: 'Ford'),
    L10n3(ar: 'مرسيدس-بنز', fr: 'Mercedes-Benz', en: 'Mercedes-Benz'),
    L10n3(ar: 'بي إم دبليو', fr: 'BMW', en: 'BMW'),
    L10n3(ar: 'سوزوكي', fr: 'Suzuki', en: 'Suzuki'),
    L10n3(ar: 'شانجان', fr: 'Changan', en: 'Changan'),
    L10n3(ar: 'جريت وول', fr: 'Great Wall', en: 'Great Wall'),
    _other,
  ],
  'trucks': [
    L10n3(ar: 'إيسوزو', fr: 'Isuzu', en: 'Isuzu'),
    L10n3(ar: 'تويوتا', fr: 'Toyota', en: 'Toyota'),
    L10n3(ar: 'هيونداي', fr: 'Hyundai', en: 'Hyundai'),
    L10n3(ar: 'نيسان', fr: 'Nissan', en: 'Nissan'),
    L10n3(ar: 'ميتسوبيشي فوسو', fr: 'Mitsubishi Fuso', en: 'Mitsubishi Fuso'),
    L10n3(ar: 'هينو', fr: 'Hino', en: 'Hino'),
    L10n3(ar: 'مرسيدس-بنز', fr: 'Mercedes-Benz', en: 'Mercedes-Benz'),
    L10n3(ar: 'إيفيكو', fr: 'Iveco', en: 'Iveco'),
    L10n3(ar: 'مان', fr: 'MAN', en: 'MAN'),
    L10n3(ar: 'فولفو', fr: 'Volvo', en: 'Volvo'),
    L10n3(ar: 'سكانيا', fr: 'Scania', en: 'Scania'),
    _other,
  ],
  'motorcycles': [
    L10n3(ar: 'سكوتر', fr: 'Scooter', en: 'Scooter'),
    L10n3(ar: 'رياضية', fr: 'Sport', en: 'Sport'),
    L10n3(ar: 'عادية', fr: 'Standard', en: 'Standard'),
    L10n3(ar: 'طرق وعرة', fr: 'Tout-terrain', en: 'Off-road'),
    _other,
  ],
  'parts': [
    L10n3(ar: 'إطارات', fr: 'Pneus', en: 'Tires'),
    L10n3(ar: 'بطاريات', fr: 'Batteries', en: 'Batteries'),
    L10n3(ar: 'زيوت وسوائل', fr: 'Huiles & fluides', en: 'Oils & fluids'),
    L10n3(ar: 'فلاتر', fr: 'Filtres', en: 'Filters'),
    L10n3(ar: 'فرامل', fr: 'Freins', en: 'Brakes'),
    L10n3(ar: 'تعليق/مساعدات', fr: 'Suspension', en: 'Suspension'),
    L10n3(ar: 'مصابيح/إنارة', fr: 'Éclairage', en: 'Lights'),
    L10n3(ar: 'هيكل/قطع خارجية', fr: 'Carrosserie', en: 'Body parts'),
    L10n3(ar: 'داخلية', fr: 'Intérieur', en: 'Interior'),
    L10n3(ar: 'إلكترونيات', fr: 'Électronique', en: 'Electronics'),
    L10n3(ar: 'إكسسوارات', fr: 'Accessoires', en: 'Accessories'),
    _other,
  ],

  // Real estate
  'house': [
    L10n3(ar: 'منزل', fr: 'Maison', en: 'House'),
    L10n3(ar: 'فيلا', fr: 'Villa', en: 'Villa'),
    L10n3(ar: 'منزل شعبي', fr: 'Maison traditionnelle', en: 'Traditional'),
    _other,
  ],
  'apartment': [
    L10n3(ar: 'شقة', fr: 'Appartement', en: 'Apartment'),
    L10n3(ar: 'استوديو', fr: 'Studio', en: 'Studio'),
    L10n3(ar: 'دوبلكس', fr: 'Duplex', en: 'Duplex'),
    _other,
  ],
  'land': [
    L10n3(ar: 'أرض سكنية', fr: 'Résidentiel', en: 'Residential'),
    L10n3(ar: 'أرض زراعية', fr: 'Agricole', en: 'Agricultural'),
    L10n3(ar: 'أرض تجارية', fr: 'Commercial', en: 'Commercial'),
    _other,
  ],

  // Jobs (offers & seekers)
  'jobs_offers': [
    L10n3(ar: 'إدارة/مكتب', fr: 'Administration', en: 'Administration'),
    L10n3(ar: 'مبيعات', fr: 'Vente', en: 'Sales'),
    L10n3(ar: 'سائق', fr: 'Chauffeur', en: 'Driver'),
    L10n3(ar: 'بناء', fr: 'Construction', en: 'Construction'),
    L10n3(ar: 'مطاعم/فندقة', fr: 'Restauration', en: 'Food & Hotel'),
    L10n3(ar: 'أمن', fr: 'Sécurité', en: 'Security'),
    L10n3(ar: 'تقنية/برمجة', fr: 'Informatique', en: 'IT/Software'),
    L10n3(ar: 'صحة', fr: 'Santé', en: 'Health'),
    L10n3(ar: 'تعليم', fr: 'Éducation', en: 'Education'),
    _other,
  ],
  'jobs_seek': [
    L10n3(ar: 'إدارة/مكتب', fr: 'Administration', en: 'Administration'),
    L10n3(ar: 'مبيعات', fr: 'Vente', en: 'Sales'),
    L10n3(ar: 'سائق', fr: 'Chauffeur', en: 'Driver'),
    L10n3(ar: 'بناء', fr: 'Construction', en: 'Construction'),
    L10n3(ar: 'مطاعم/فندقة', fr: 'Restauration', en: 'Food & Hotel'),
    L10n3(ar: 'أمن', fr: 'Sécurité', en: 'Security'),
    L10n3(ar: 'تقنية/برمجة', fr: 'Informatique', en: 'IT/Software'),
    L10n3(ar: 'صحة', fr: 'Santé', en: 'Health'),
    L10n3(ar: 'تعليم', fr: 'Éducation', en: 'Education'),
    _other,
  ],
};

List<QuickFieldDef> _vehicleQuickFields() => <QuickFieldDef>[
      QuickFieldDef(
        key: 'year',
        label: L10n3(ar: 'السنة', fr: 'Année', en: 'Year'),
        options: const <L10n3>[],
        icon: Icons.calendar_month_outlined,
      ),
      QuickFieldDef(
        key: 'mileage_km',
        label: L10n3(ar: 'المسافة (كم)', fr: 'Kilométrage', en: 'Mileage (km)'),
        options: const <L10n3>[],
        icon: Icons.speed_outlined,
      ),
      QuickFieldDef(
        key: 'fuel',
        label: L10n3(ar: 'الوقود', fr: 'Carburant', en: 'Fuel'),
        options: <L10n3>[
          L10n3(ar: 'بنزين', fr: 'Essence', en: 'Petrol'),
          L10n3(ar: 'ديزل', fr: 'Diesel', en: 'Diesel'),
          L10n3(ar: 'غاز', fr: 'Gaz', en: 'Gas'),
          L10n3(ar: 'كهرباء', fr: 'Électrique', en: 'Electric'),
          L10n3(ar: 'هجين', fr: 'Hybride', en: 'Hybrid'),
          _other,
        ],
        icon: Icons.local_gas_station_outlined,
      ),
      QuickFieldDef(
        key: 'transmission',
        label: L10n3(ar: 'ناقل الحركة', fr: 'Transmission', en: 'Transmission'),
        options: <L10n3>[
          L10n3(ar: 'عادي', fr: 'Manuelle', en: 'Manual'),
          L10n3(ar: 'أوتوماتيك', fr: 'Automatique', en: 'Automatic'),
          _other,
        ],
        icon: Icons.settings_input_component_outlined,
      ),
      QuickFieldDef(
        key: 'origin',
        label: L10n3(ar: 'المصدر', fr: 'Origine', en: 'Origin'),
        options: <L10n3>[
          L10n3(ar: 'مستوردة', fr: 'Importée', en: 'Imported'),
          L10n3(ar: 'محلية', fr: 'Locale', en: 'Local'),
          _other,
        ],
        icon: Icons.public_outlined,
      ),
    ];

List<QuickFieldDef> _truckQuickFields() => <QuickFieldDef>[
      ..._vehicleQuickFields(),
    ];

final Map<String, List<QuickFieldDef>> _quick = {
  // Phones
  'phones': [
    QuickFieldDef(
      key: 'storage',
      label: L10n3(ar: 'السعة', fr: 'Stockage', en: 'Storage'),
      options: <L10n3>[
        L10n3(ar: '32GB', fr: '32GB', en: '32GB'),
        L10n3(ar: '64GB', fr: '64GB', en: '64GB'),
        L10n3(ar: '128GB', fr: '128GB', en: '128GB'),
        L10n3(ar: '256GB', fr: '256GB', en: '256GB'),
        L10n3(ar: '512GB', fr: '512GB', en: '512GB'),
        L10n3(ar: '1TB', fr: '1TB', en: '1TB'),
      ],
      icon: Icons.sd_storage_outlined,
    ),
    QuickFieldDef(
      key: 'ram',
      label: L10n3(ar: 'الرام', fr: 'RAM', en: 'RAM'),
      options: <L10n3>[
        L10n3(ar: '2GB', fr: '2GB', en: '2GB'),
        L10n3(ar: '3GB', fr: '3GB', en: '3GB'),
        L10n3(ar: '4GB', fr: '4GB', en: '4GB'),
        L10n3(ar: '6GB', fr: '6GB', en: '6GB'),
        L10n3(ar: '8GB', fr: '8GB', en: '8GB'),
        L10n3(ar: '12GB', fr: '12GB', en: '12GB'),
        L10n3(ar: '16GB', fr: '16GB', en: '16GB'),
      ],
      icon: Icons.memory_outlined,
    ),
    const QuickFieldDef(
      key: 'color',
      label: L10n3(ar: 'اللون', fr: 'Couleur', en: 'Color'),
      options: _colors,
      icon: Icons.palette_outlined,
    ),
  ],

  // Smart home
  'smart_home': [
    QuickFieldDef(
      key: 'power',
      label: L10n3(ar: 'الطاقة', fr: 'Alimentation', en: 'Power'),
      options: <L10n3>[
        L10n3(ar: 'بطارية', fr: 'Batterie', en: 'Battery'),
        L10n3(ar: 'USB', fr: 'USB', en: 'USB'),
        L10n3(ar: 'كهرباء', fr: 'Secteur', en: 'Plug-in'),
        _other,
      ],
      icon: Icons.power_outlined,
    ),
  ],

  // Printers
  'printers': [
    QuickFieldDef(
      key: 'paper',
      label: L10n3(ar: 'مقاس الورق', fr: 'Format papier', en: 'Paper size'),
      options: <L10n3>[
        L10n3(ar: 'A4', fr: 'A4', en: 'A4'),
        L10n3(ar: 'A3', fr: 'A3', en: 'A3'),
        L10n3(ar: 'حراري', fr: 'Thermique', en: 'Thermal'),
        _other,
      ],
      icon: Icons.description_outlined,
    ),
  ],

  // Network/Wi‑Fi
  'network': [
    QuickFieldDef(
      key: 'wifi_band',
      label: L10n3(ar: 'النطاق', fr: 'Bande', en: 'Band'),
      options: <L10n3>[
        L10n3(ar: '2.4GHz', fr: '2.4GHz', en: '2.4GHz'),
        L10n3(ar: '5GHz', fr: '5GHz', en: '5GHz'),
        L10n3(ar: 'ثنائي', fr: 'Double bande', en: 'Dual-band'),
        L10n3(ar: 'Wi‑Fi 6', fr: 'Wi‑Fi 6', en: 'Wi‑Fi 6'),
        _other,
      ],
      icon: Icons.wifi_tethering_outlined,
    ),
  ],
  // Cars & vehicles
  'cars': _vehicleQuickFields(),
  'suv4x4': _vehicleQuickFields(),
  'trucks': _truckQuickFields(),

  'motorcycles': [
    QuickFieldDef(
      key: 'year',
      label: L10n3(ar: 'السنة', fr: 'Année', en: 'Year'),
      options: const <L10n3>[],
      icon: Icons.calendar_month_outlined,
    ),
    QuickFieldDef(
      key: 'mileage_km',
      label: L10n3(ar: 'المسافة (كم)', fr: 'Kilométrage', en: 'Mileage (km)'),
      options: const <L10n3>[],
      icon: Icons.speed_outlined,
    ),
  ],

  'parts': [
    QuickFieldDef(
      key: 'compatibility',
      label: L10n3(ar: 'التوافق', fr: 'Compatibilité', en: 'Compatibility'),
      options: <L10n3>[
        L10n3(ar: 'سيارات', fr: 'Voitures', en: 'Cars'),
        L10n3(ar: '4x4', fr: '4x4', en: '4x4'),
        L10n3(ar: 'شاحنات', fr: 'Camions', en: 'Trucks'),
        L10n3(ar: 'دراجات', fr: 'Motos', en: 'Motorcycles'),
        _other,
      ],
      icon: Icons.build_outlined,
    ),
  ],

  // Real estate
  'land': [
    QuickFieldDef(
      key: 'area_m2',
      label: L10n3(ar: 'المساحة (م²)', fr: 'Surface (m²)', en: 'Area (m²)'),
      options: const <L10n3>[],
      icon: Icons.square_foot_outlined,
    ),
    QuickFieldDef(
      key: 'papers',
      label: L10n3(ar: 'الأوراق', fr: 'Papiers', en: 'Documents'),
      options: <L10n3>[
        L10n3(ar: 'متوفر', fr: 'Disponibles', en: 'Available'),
        L10n3(ar: 'غير متوفر', fr: 'Non disponibles', en: 'Not available'),
        _other,
      ],
      icon: Icons.description_outlined,
    ),
  ],
  'house': [
    QuickFieldDef(
      key: 'rooms',
      label: L10n3(ar: 'الغرف', fr: 'Pièces', en: 'Rooms'),
      options: <L10n3>[
        L10n3(ar: '1', fr: '1', en: '1'),
        L10n3(ar: '2', fr: '2', en: '2'),
        L10n3(ar: '3', fr: '3', en: '3'),
        L10n3(ar: '4', fr: '4', en: '4'),
        L10n3(ar: '5+', fr: '5+', en: '5+'),
        _other,
      ],
      icon: Icons.meeting_room_outlined,
    ),
    QuickFieldDef(
      key: 'area_m2',
      label: L10n3(ar: 'المساحة (م²)', fr: 'Surface (m²)', en: 'Area (m²)'),
      options: const <L10n3>[],
      icon: Icons.square_foot_outlined,
    ),
    QuickFieldDef(
      key: 'furnished',
      label: L10n3(ar: 'مفروش', fr: 'Meublé', en: 'Furnished'),
      options: <L10n3>[
        L10n3(ar: 'نعم', fr: 'Oui', en: 'Yes'),
        L10n3(ar: 'لا', fr: 'Non', en: 'No'),
      ],
      icon: Icons.chair_alt_outlined,
    ),
  ],
  'apartment': [
    QuickFieldDef(
      key: 'rooms',
      label: L10n3(ar: 'الغرف', fr: 'Pièces', en: 'Rooms'),
      options: <L10n3>[
        L10n3(ar: '1', fr: '1', en: '1'),
        L10n3(ar: '2', fr: '2', en: '2'),
        L10n3(ar: '3', fr: '3', en: '3'),
        L10n3(ar: '4', fr: '4', en: '4'),
        L10n3(ar: '5+', fr: '5+', en: '5+'),
        _other,
      ],
      icon: Icons.meeting_room_outlined,
    ),
    QuickFieldDef(
      key: 'area_m2',
      label: L10n3(ar: 'المساحة (م²)', fr: 'Surface (m²)', en: 'Area (m²)'),
      options: const <L10n3>[],
      icon: Icons.square_foot_outlined,
    ),
    QuickFieldDef(
      key: 'furnished',
      label: L10n3(ar: 'مفروش', fr: 'Meublé', en: 'Furnished'),
      options: <L10n3>[
        L10n3(ar: 'نعم', fr: 'Oui', en: 'Yes'),
        L10n3(ar: 'لا', fr: 'Non', en: 'No'),
      ],
      icon: Icons.chair_alt_outlined,
    ),
  ],
  'rent': [
    QuickFieldDef(
      key: 'rooms',
      label: L10n3(ar: 'الغرف', fr: 'Pièces', en: 'Rooms'),
      options: <L10n3>[
        L10n3(ar: '1', fr: '1', en: '1'),
        L10n3(ar: '2', fr: '2', en: '2'),
        L10n3(ar: '3', fr: '3', en: '3'),
        L10n3(ar: '4', fr: '4', en: '4'),
        L10n3(ar: '5+', fr: '5+', en: '5+'),
        _other,
      ],
      icon: Icons.meeting_room_outlined,
    ),
    QuickFieldDef(
      key: 'furnished',
      label: L10n3(ar: 'مفروش', fr: 'Meublé', en: 'Furnished'),
      options: <L10n3>[
        L10n3(ar: 'نعم', fr: 'Oui', en: 'Yes'),
        L10n3(ar: 'لا', fr: 'Non', en: 'No'),
      ],
      icon: Icons.chair_alt_outlined,
    ),
  ],
  'shops': [
    QuickFieldDef(
      key: 'area_m2',
      label: L10n3(ar: 'المساحة (م²)', fr: 'Surface (m²)', en: 'Area (m²)'),
      options: const <L10n3>[],
      icon: Icons.square_foot_outlined,
    ),
  ],

  // Fashion
  'ma_traditional': [
    const QuickFieldDef(
      key: 'color',
      label: L10n3(ar: 'اللون', fr: 'Couleur', en: 'Color'),
      options: _colors,
      icon: Icons.palette_outlined,
    ),
    QuickFieldDef(
      key: 'fabric',
      label: L10n3(ar: 'القماش', fr: 'Tissu', en: 'Fabric'),
      options: <L10n3>[
        L10n3(ar: 'قطن', fr: 'Coton', en: 'Cotton'),
        L10n3(ar: 'حرير', fr: 'Soie', en: 'Silk'),
        L10n3(ar: 'شيفون', fr: 'Chiffon', en: 'Chiffon'),
        L10n3(ar: 'صوف', fr: 'Laine', en: 'Wool'),
        _other,
      ],
      icon: Icons.texture_outlined,
    ),
  ],
  'melhafa': [
    const QuickFieldDef(
      key: 'color',
      label: L10n3(ar: 'اللون', fr: 'Couleur', en: 'Color'),
      options: _colors,
      icon: Icons.palette_outlined,
    ),
    QuickFieldDef(
      key: 'fabric',
      label: L10n3(ar: 'القماش', fr: 'Tissu', en: 'Fabric'),
      options: <L10n3>[
        L10n3(ar: 'قطن', fr: 'Coton', en: 'Cotton'),
        L10n3(ar: 'حرير', fr: 'Soie', en: 'Silk'),
        L10n3(ar: 'شيفون', fr: 'Chiffon', en: 'Chiffon'),
        _other,
      ],
      icon: Icons.texture_outlined,
    ),
  ],
  'daraa': [
    const QuickFieldDef(
      key: 'size',
      label: L10n3(ar: 'المقاس', fr: 'Taille', en: 'Size'),
      options: _sizes,
      icon: Icons.straighten_outlined,
    ),
    QuickFieldDef(
      key: 'fabric',
      label: L10n3(ar: 'القماش', fr: 'Tissu', en: 'Fabric'),
      options: <L10n3>[
        L10n3(ar: 'قطن', fr: 'Coton', en: 'Cotton'),
        L10n3(ar: 'صوف', fr: 'Laine', en: 'Wool'),
        L10n3(ar: 'مخمل', fr: 'Velours', en: 'Velvet'),
        _other,
      ],
      icon: Icons.texture_outlined,
    ),
  ],
  'women_clothing': [
    const QuickFieldDef(
      key: 'size',
      label: L10n3(ar: 'المقاس', fr: 'Taille', en: 'Size'),
      options: _sizes,
      icon: Icons.straighten_outlined,
    ),
    const QuickFieldDef(
      key: 'color',
      label: L10n3(ar: 'اللون', fr: 'Couleur', en: 'Color'),
      options: _colors,
      icon: Icons.palette_outlined,
    ),
  ],
  'men_clothing': [
    const QuickFieldDef(
      key: 'size',
      label: L10n3(ar: 'المقاس', fr: 'Taille', en: 'Size'),
      options: _sizes,
      icon: Icons.straighten_outlined,
    ),
    const QuickFieldDef(
      key: 'color',
      label: L10n3(ar: 'اللون', fr: 'Couleur', en: 'Color'),
      options: _colors,
      icon: Icons.palette_outlined,
    ),
  ],
  'kids_clothing': [
    QuickFieldDef(
      key: 'age_range',
      label: L10n3(ar: 'العمر', fr: 'Âge', en: 'Age'),
      options: <L10n3>[
        L10n3(ar: '0-1', fr: '0-1', en: '0-1'),
        L10n3(ar: '2-4', fr: '2-4', en: '2-4'),
        L10n3(ar: '5-7', fr: '5-7', en: '5-7'),
        L10n3(ar: '8-12', fr: '8-12', en: '8-12'),
        L10n3(ar: '13-16', fr: '13-16', en: '13-16'),
        _other,
      ],
      icon: Icons.child_friendly_outlined,
    ),
    const QuickFieldDef(
      key: 'color',
      label: L10n3(ar: 'اللون', fr: 'Couleur', en: 'Color'),
      options: _colors,
      icon: Icons.palette_outlined,
    ),
  ],
  'shoes': [
    QuickFieldDef(
      key: 'size',
      label: L10n3(ar: 'المقاس', fr: 'Pointure', en: 'Size'),
      options: const <L10n3>[],
      icon: Icons.straighten_outlined,
    ),
    const QuickFieldDef(
      key: 'color',
      label: L10n3(ar: 'اللون', fr: 'Couleur', en: 'Color'),
      options: _colors,
      icon: Icons.palette_outlined,
    ),
  ],

  // Jobs
  'jobs_offers': [
    QuickFieldDef(
      key: 'contract',
      label: L10n3(ar: 'نوع العقد', fr: 'Contrat', en: 'Contract'),
      options: <L10n3>[
        L10n3(ar: 'دوام كامل', fr: 'Temps plein', en: 'Full-time'),
        L10n3(ar: 'دوام جزئي', fr: 'Temps partiel', en: 'Part-time'),
        L10n3(ar: 'مؤقت', fr: 'Temporaire', en: 'Temporary'),
        L10n3(ar: 'تدريب', fr: 'Stage', en: 'Internship'),
        _other,
      ],
      icon: Icons.badge_outlined,
    ),
    QuickFieldDef(
      key: 'experience',
      label: L10n3(ar: 'الخبرة', fr: 'Expérience', en: 'Experience'),
      options: <L10n3>[
        L10n3(ar: 'بدون خبرة', fr: 'Sans expérience', en: 'No experience'),
        L10n3(ar: '1-2 سنوات', fr: '1-2 ans', en: '1-2 years'),
        L10n3(ar: '3-5 سنوات', fr: '3-5 ans', en: '3-5 years'),
        L10n3(ar: 'أكثر من 5', fr: 'Plus de 5', en: '5+ years'),
        _other,
      ],
      icon: Icons.workspace_premium_outlined,
    ),
    QuickFieldDef(
      key: 'work_mode',
      label: L10n3(ar: 'نمط العمل', fr: 'Mode', en: 'Work mode'),
      options: <L10n3>[
        L10n3(ar: 'حضوري', fr: 'Présentiel', en: 'On-site'),
        L10n3(ar: 'عن بعد', fr: 'À distance', en: 'Remote'),
        L10n3(ar: 'مختلط', fr: 'Hybride', en: 'Hybrid'),
        _other,
      ],
      icon: Icons.laptop_chromebook_outlined,
    ),
    QuickFieldDef(
      key: 'company',
      label: L10n3(ar: 'اسم الشركة', fr: "Nom de l'entreprise", en: 'Company'),
      options: const <L10n3>[],
      icon: Icons.apartment_outlined,
    ),
  ],
  'jobs_seek': [
    QuickFieldDef(
      key: 'availability',
      label: L10n3(ar: 'متاح', fr: 'Disponible', en: 'Availability'),
      options: <L10n3>[
        L10n3(ar: 'فوراً', fr: 'Immédiatement', en: 'Immediately'),
        L10n3(ar: 'خلال أسبوع', fr: 'Sous une semaine', en: 'Within a week'),
        L10n3(ar: 'خلال شهر', fr: 'Sous un mois', en: 'Within a month'),
        _other,
      ],
      icon: Icons.schedule_outlined,
    ),
    QuickFieldDef(
      key: 'experience',
      label: L10n3(ar: 'الخبرة', fr: 'Expérience', en: 'Experience'),
      options: <L10n3>[
        L10n3(ar: 'بدون خبرة', fr: 'Sans expérience', en: 'No experience'),
        L10n3(ar: '1-2 سنوات', fr: '1-2 ans', en: '1-2 years'),
        L10n3(ar: '3-5 سنوات', fr: '3-5 ans', en: '3-5 years'),
        L10n3(ar: 'أكثر من 5', fr: 'Plus de 5', en: '5+ years'),
        _other,
      ],
      icon: Icons.workspace_premium_outlined,
    ),
    QuickFieldDef(
      key: 'education',
      label: L10n3(ar: 'المستوى الدراسي', fr: 'Études', en: 'Education'),
      options: <L10n3>[
        L10n3(ar: 'ابتدائي', fr: 'Primaire', en: 'Primary'),
        L10n3(ar: 'إعدادي', fr: 'Collège', en: 'Middle school'),
        L10n3(ar: 'ثانوي', fr: 'Lycée', en: 'High school'),
        L10n3(ar: 'جامعة', fr: 'Université', en: 'University'),
        L10n3(ar: 'تكوين مهني', fr: 'Formation', en: 'Vocational'),
        _other,
      ],
      icon: Icons.school_outlined,
    ),
    QuickFieldDef(
      key: 'languages',
      label: L10n3(ar: 'اللغات', fr: 'Langues', en: 'Languages'),
      options: <L10n3>[
        L10n3(ar: 'العربية', fr: 'Arabe', en: 'Arabic'),
        L10n3(ar: 'الفرنسية', fr: 'Français', en: 'French'),
        L10n3(ar: 'الإنجليزية', fr: 'Anglais', en: 'English'),
        L10n3(ar: 'البولارية', fr: 'Pulaar', en: 'Pulaar'),
        L10n3(ar: 'السوننكية', fr: 'Soninké', en: 'Soninke'),
        L10n3(ar: 'الولوفية', fr: 'Wolof', en: 'Wolof'),
        _other,
      ],
      icon: Icons.language_outlined,
    ),
    QuickFieldDef(
      key: 'license',
      label: L10n3(ar: 'رخصة سياقة', fr: 'Permis', en: 'Driving license'),
      options: <L10n3>[
        L10n3(ar: 'نعم', fr: 'Oui', en: 'Yes'),
        L10n3(ar: 'لا', fr: 'Non', en: 'No'),
      ],
      icon: Icons.directions_car_outlined,
    ),
  ],
};

/// All known *quick attribute keys* used by the publish taxonomy.
///
/// This lets the publish wizard keep the user's values in memory (Option A),
/// while **excluding incompatible quick fields when saving**.
final Set<String> kKnownQuickAttrKeys = (() {
  final s = <String>{'condition'};
  for (final list in _quick.values) {
    for (final q in list) {
      s.add(q.key);
    }
  }
  return s;
})();

/// Debug-only sanity check for publish taxonomy.
/// Helps catch accidental mixed-language labels (e.g., Latin brand names shown in Arabic lists).
/// Call this in debug builds only (wrapped in assert).
void debugCheckPublishTaxonomy() {
  assert(() {
    const vehicleKeys = <String>['cars', 'suv4x4', 'trucks'];
    final latin = RegExp(r'[A-Za-z]');
    for (final k in vehicleKeys) {
      final list = _variants[k];
      if (list == null) continue;
      for (final o in list) {
        if (o.en == _other.en) continue;
        if (latin.hasMatch(o.ar)) {
          debugPrint(
            '[publish_taxonomy] Mixed label: $k -> ${o.en} has Arabic="${o.ar}"',
          );
        }
      }
    }
    return true;
  }());
}
