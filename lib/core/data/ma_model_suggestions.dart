import 'ma_catalog.dart';
import 'ma_suggestions.dart';

/// Ready-to-pick model lists for the Publish Wizard.
///
/// The goal is not "perfect global completeness" but a strong local default
/// that speeds up publishing in Mauritania.

bool _isPhoneContext(String? categoryId, String? subCategoryId) {
  final c = (categoryId ?? '').trim();
  final s = (subCategoryId ?? '').trim();
  return c == 'electronics' && s == 'phones';
}

bool _isVehicleContext(String? categoryId, String? subCategoryId) {
  final c = (categoryId ?? '').trim();
  final s = (subCategoryId ?? '').trim();
  return c == 'vehicles' && (s == 'cars' || s == 'suv4x4' || s == 'trucks');
}

/// Normalizes strings for lightweight matching across Arabic/French/English.
///
/// We keep Arabic letters (\u0600-\u06FF) so brands typed in Arabic still match.

List<MaSuggestion> _latestFirst(List<MaSuggestion> list) =>
    list.reversed.toList(growable: false);

List<MaSuggestion> _latestFirstSamsung(List<MaSuggestion> list) {
  final s = <MaSuggestion>[];
  final note = <MaSuggestion>[];
  final a = <MaSuggestion>[];
  final other = <MaSuggestion>[];

  for (final m in list) {
    final id = m.id;
    if (id.startsWith('galaxy_s')) {
      s.add(m);
    } else if (id.startsWith('galaxy_note')) {
      note.add(m);
    } else if (id.startsWith('galaxy_a')) {
      a.add(m);
    } else {
      other.add(m);
    }
  }

  return <MaSuggestion>[
    ...s.reversed,
    ...note.reversed,
    ...a.reversed,
    ...other.reversed,
  ];
}

String _norm(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), '');

bool _typeLooksLike(String? type, List<String> needles) {
  final raw = (type ?? '').trim().toLowerCase();
  if (raw.isEmpty) return false;
  final t = _norm(raw);

  for (final n in needles) {
    final nnRaw = n.trim().toLowerCase();
    if (nnRaw.isNotEmpty && raw.contains(nnRaw)) return true;
    final nn = _norm(nnRaw);
    if (nn.isNotEmpty && t.contains(nn)) return true;
  }
  return false;
}

/// Returns suggestions for the "Model" field.
///
/// - For phones: uses brand/type (Apple/Samsung) when available.
/// - For vehicles: uses brand/type (Toyota, Mercedes, ...) when available.
List<MaSuggestion> modelSuggestionsFor({
  required String? categoryId,
  required String? subCategoryId,
  String? typeIdOrLabel,
}) {
  if (_isPhoneContext(categoryId, subCategoryId)) {
    final t = (typeIdOrLabel ?? '').trim();

    // If no brand was chosen, show a small helpful default.
    if (t.isEmpty)
      return <MaSuggestion>[
        ..._latestFirst(kIPhoneModels),
        ..._latestFirstSamsung(kSamsungModels)
      ];

    if (_typeLooksLike(t, const [
      'apple',
      'iphone',
      'ios',
      'آيفون',
      'ايفون',
      'أيفون',
    ])) {
      return _latestFirst(kIPhoneModels);
    }
    if (_typeLooksLike(t, const [
      'samsung',
      'galaxy',
      'سامسونج',
      'سمسونج',
    ])) {
      return _latestFirstSamsung(kSamsungModels);
    }

    // Brand is known by the user but we don't have a safe list => manual entry.
    return const <MaSuggestion>[];
  }

  if (_isVehicleContext(categoryId, subCategoryId)) {
    final t = (typeIdOrLabel ?? '').trim();

    // If no brand was chosen, show a broad helpful list.
    if (t.isEmpty) {
      return <MaSuggestion>[
        ...kToyotaModels,
        ...kNissanModels,
        ...kHyundaiModels,
        ...kKiaModels,
        ...kMercedesModels,
        ...kMitsubishiModels,
        ...kOtherCommonCarModels,
      ];
    }

    if (_typeLooksLike(t, const ['toyota', 'تويوتا'])) {
      return kToyotaModels;
    }
    if (_typeLooksLike(t, const ['nissan', 'نيسان'])) {
      return kNissanModels;
    }
    if (_typeLooksLike(t, const ['hyundai', 'هيونداي', 'هيونداى'])) {
      return kHyundaiModels;
    }
    if (_typeLooksLike(t, const ['kia', 'كيا'])) {
      return kKiaModels;
    }
    if (_typeLooksLike(t, const ['mercedes', 'benz', 'مرسيدس', 'بنز'])) {
      return kMercedesModels;
    }
    if (_typeLooksLike(t, const ['mitsubishi', 'ميتسوبيشي', 'ميتسوبيشى'])) {
      return kMitsubishiModels;
    }

    // Brand is known by the user but not supported => manual entry (no mixing).
    return const <MaSuggestion>[];
  }

  return const <MaSuggestion>[];
}

// ---------------------------------------------------------------------------
// Phones
// ---------------------------------------------------------------------------

const List<MaSuggestion> kIPhoneModels = <MaSuggestion>[
  MaSuggestion(
      id: 'iphone_4',
      label: L10n3(ar: 'آيفون 4', fr: 'iPhone 4', en: 'iPhone 4')),
  MaSuggestion(
      id: 'iphone_4s',
      label: L10n3(ar: 'آيفون 4 إس', fr: 'iPhone 4s', en: 'iPhone 4s')),
  MaSuggestion(
      id: 'iphone_5',
      label: L10n3(ar: 'آيفون 5', fr: 'iPhone 5', en: 'iPhone 5')),
  MaSuggestion(
      id: 'iphone_5c',
      label: L10n3(ar: 'آيفون 5 سي', fr: 'iPhone 5c', en: 'iPhone 5c')),
  MaSuggestion(
      id: 'iphone_5s',
      label: L10n3(ar: 'آيفون 5 إس', fr: 'iPhone 5s', en: 'iPhone 5s')),
  MaSuggestion(
      id: 'iphone_6',
      label: L10n3(ar: 'آيفون 6', fr: 'iPhone 6', en: 'iPhone 6')),
  MaSuggestion(
      id: 'iphone_6_plus',
      label:
          L10n3(ar: 'آيفون 6 بلس', fr: 'iPhone 6 Plus', en: 'iPhone 6 Plus')),
  MaSuggestion(
      id: 'iphone_6s',
      label: L10n3(ar: 'آيفون 6 إس', fr: 'iPhone 6s', en: 'iPhone 6s')),
  MaSuggestion(
      id: 'iphone_6s_plus',
      label: L10n3(
          ar: 'آيفون 6 إس بلس', fr: 'iPhone 6s Plus', en: 'iPhone 6s Plus')),
  MaSuggestion(
      id: 'iphone_se_2016',
      label: L10n3(
          ar: 'آيفون إس إي (2016)',
          fr: 'iPhone SE (2016)',
          en: 'iPhone SE (2016)')),
  MaSuggestion(
      id: 'iphone_7',
      label: L10n3(ar: 'آيفون 7', fr: 'iPhone 7', en: 'iPhone 7')),
  MaSuggestion(
      id: 'iphone_7_plus',
      label:
          L10n3(ar: 'آيفون 7 بلس', fr: 'iPhone 7 Plus', en: 'iPhone 7 Plus')),
  MaSuggestion(
      id: 'iphone_8',
      label: L10n3(ar: 'آيفون 8', fr: 'iPhone 8', en: 'iPhone 8')),
  MaSuggestion(
      id: 'iphone_8_plus',
      label:
          L10n3(ar: 'آيفون 8 بلس', fr: 'iPhone 8 Plus', en: 'iPhone 8 Plus')),
  MaSuggestion(
      id: 'iphone_x',
      label: L10n3(ar: 'آيفون إكس', fr: 'iPhone X', en: 'iPhone X')),
  MaSuggestion(
      id: 'iphone_xr',
      label: L10n3(ar: 'آيفون إكس آر', fr: 'iPhone XR', en: 'iPhone XR')),
  MaSuggestion(
      id: 'iphone_xs',
      label: L10n3(ar: 'آيفون إكس إس', fr: 'iPhone XS', en: 'iPhone XS')),
  MaSuggestion(
      id: 'iphone_xs_max',
      label: L10n3(
          ar: 'آيفون إكس إس ماكس', fr: 'iPhone XS Max', en: 'iPhone XS Max')),
  MaSuggestion(
      id: 'iphone_11',
      label: L10n3(ar: 'آيفون 11', fr: 'iPhone 11', en: 'iPhone 11')),
  MaSuggestion(
      id: 'iphone_11_pro',
      label:
          L10n3(ar: 'آيفون 11 برو', fr: 'iPhone 11 Pro', en: 'iPhone 11 Pro')),
  MaSuggestion(
      id: 'iphone_11_pro_max',
      label: L10n3(
          ar: 'آيفون 11 برو ماكس',
          fr: 'iPhone 11 Pro Max',
          en: 'iPhone 11 Pro Max')),
  MaSuggestion(
      id: 'iphone_se_2020',
      label: L10n3(
          ar: 'آيفون إس إي (2020)',
          fr: 'iPhone SE (2020)',
          en: 'iPhone SE (2020)')),
  MaSuggestion(
      id: 'iphone_12_mini',
      label: L10n3(
          ar: 'آيفون 12 ميني', fr: 'iPhone 12 mini', en: 'iPhone 12 mini')),
  MaSuggestion(
      id: 'iphone_12',
      label: L10n3(ar: 'آيفون 12', fr: 'iPhone 12', en: 'iPhone 12')),
  MaSuggestion(
      id: 'iphone_12_pro',
      label:
          L10n3(ar: 'آيفون 12 برو', fr: 'iPhone 12 Pro', en: 'iPhone 12 Pro')),
  MaSuggestion(
      id: 'iphone_12_pro_max',
      label: L10n3(
          ar: 'آيفون 12 برو ماكس',
          fr: 'iPhone 12 Pro Max',
          en: 'iPhone 12 Pro Max')),
  MaSuggestion(
      id: 'iphone_13_mini',
      label: L10n3(
          ar: 'آيفون 13 ميني', fr: 'iPhone 13 mini', en: 'iPhone 13 mini')),
  MaSuggestion(
      id: 'iphone_13',
      label: L10n3(ar: 'آيفون 13', fr: 'iPhone 13', en: 'iPhone 13')),
  MaSuggestion(
      id: 'iphone_13_pro',
      label:
          L10n3(ar: 'آيفون 13 برو', fr: 'iPhone 13 Pro', en: 'iPhone 13 Pro')),
  MaSuggestion(
      id: 'iphone_13_pro_max',
      label: L10n3(
          ar: 'آيفون 13 برو ماكس',
          fr: 'iPhone 13 Pro Max',
          en: 'iPhone 13 Pro Max')),
  MaSuggestion(
      id: 'iphone_se_2022',
      label: L10n3(
          ar: 'آيفون إس إي (2022)',
          fr: 'iPhone SE (2022)',
          en: 'iPhone SE (2022)')),
  MaSuggestion(
      id: 'iphone_14',
      label: L10n3(ar: 'آيفون 14', fr: 'iPhone 14', en: 'iPhone 14')),
  MaSuggestion(
      id: 'iphone_14_plus',
      label: L10n3(
          ar: 'آيفون 14 بلس', fr: 'iPhone 14 Plus', en: 'iPhone 14 Plus')),
  MaSuggestion(
      id: 'iphone_14_pro',
      label:
          L10n3(ar: 'آيفون 14 برو', fr: 'iPhone 14 Pro', en: 'iPhone 14 Pro')),
  MaSuggestion(
      id: 'iphone_14_pro_max',
      label: L10n3(
          ar: 'آيفون 14 برو ماكس',
          fr: 'iPhone 14 Pro Max',
          en: 'iPhone 14 Pro Max')),
  MaSuggestion(
      id: 'iphone_15',
      label: L10n3(ar: 'آيفون 15', fr: 'iPhone 15', en: 'iPhone 15')),
  MaSuggestion(
      id: 'iphone_15_plus',
      label: L10n3(
          ar: 'آيفون 15 بلس', fr: 'iPhone 15 Plus', en: 'iPhone 15 Plus')),
  MaSuggestion(
      id: 'iphone_15_pro',
      label:
          L10n3(ar: 'آيفون 15 برو', fr: 'iPhone 15 Pro', en: 'iPhone 15 Pro')),
  MaSuggestion(
      id: 'iphone_15_pro_max',
      label: L10n3(
          ar: 'آيفون 15 برو ماكس',
          fr: 'iPhone 15 Pro Max',
          en: 'iPhone 15 Pro Max')),
  MaSuggestion(
      id: 'iphone_16',
      label: L10n3(ar: 'آيفون 16', fr: 'iPhone 16', en: 'iPhone 16')),
  MaSuggestion(
      id: 'iphone_16_plus',
      label: L10n3(
          ar: 'آيفون 16 بلس', fr: 'iPhone 16 Plus', en: 'iPhone 16 Plus')),
  MaSuggestion(
      id: 'iphone_16_pro',
      label:
          L10n3(ar: 'آيفون 16 برو', fr: 'iPhone 16 Pro', en: 'iPhone 16 Pro')),
  MaSuggestion(
      id: 'iphone_16_pro_max',
      label: L10n3(
          ar: 'آيفون 16 برو ماكس',
          fr: 'iPhone 16 Pro Max',
          en: 'iPhone 16 Pro Max')),
  MaSuggestion(
      id: 'iphone_16e',
      label: L10n3(ar: 'آيفون 16 إي', fr: 'iPhone 16e', en: 'iPhone 16e')),
  MaSuggestion(
      id: 'iphone_17',
      label: L10n3(ar: 'آيفون 17', fr: 'iPhone 17', en: 'iPhone 17')),
  MaSuggestion(
      id: 'iphone_17_plus',
      label: L10n3(
          ar: 'آيفون 17 بلس', fr: 'iPhone 17 Plus', en: 'iPhone 17 Plus')),
  MaSuggestion(
      id: 'iphone_17_pro',
      label:
          L10n3(ar: 'آيفون 17 برو', fr: 'iPhone 17 Pro', en: 'iPhone 17 Pro')),
  MaSuggestion(
      id: 'iphone_17_pro_max',
      label: L10n3(
          ar: 'آيفون 17 برو ماكس',
          fr: 'iPhone 17 Pro Max',
          en: 'iPhone 17 Pro Max')),
];

const List<MaSuggestion> kSamsungModels = <MaSuggestion>[
  MaSuggestion(
      id: 'galaxy_s8',
      label: L10n3(ar: 'جالاكسي إس 8', fr: 'Galaxy S8', en: 'Galaxy S8')),
  MaSuggestion(
      id: 'galaxy_s9',
      label: L10n3(ar: 'جالاكسي إس 9', fr: 'Galaxy S9', en: 'Galaxy S9')),
  MaSuggestion(
      id: 'galaxy_s10',
      label: L10n3(ar: 'جالاكسي إس 10', fr: 'Galaxy S10', en: 'Galaxy S10')),
  MaSuggestion(
      id: 'galaxy_s10_plus',
      label:
          L10n3(ar: 'جالاكسي إس 10 بلس', fr: 'Galaxy S10+', en: 'Galaxy S10+')),
  MaSuggestion(
      id: 'galaxy_s20',
      label: L10n3(ar: 'جالاكسي إس 20', fr: 'Galaxy S20', en: 'Galaxy S20')),
  MaSuggestion(
      id: 'galaxy_s20_plus',
      label:
          L10n3(ar: 'جالاكسي إس 20 بلس', fr: 'Galaxy S20+', en: 'Galaxy S20+')),
  MaSuggestion(
      id: 'galaxy_s20_ultra',
      label: L10n3(
          ar: 'جالاكسي إس 20 ألترا',
          fr: 'Galaxy S20 Ultra',
          en: 'Galaxy S20 Ultra')),
  MaSuggestion(
      id: 'galaxy_s21',
      label: L10n3(ar: 'جالاكسي إس 21', fr: 'Galaxy S21', en: 'Galaxy S21')),
  MaSuggestion(
      id: 'galaxy_s21_plus',
      label:
          L10n3(ar: 'جالاكسي إس 21 بلس', fr: 'Galaxy S21+', en: 'Galaxy S21+')),
  MaSuggestion(
      id: 'galaxy_s21_ultra',
      label: L10n3(
          ar: 'جالاكسي إس 21 ألترا',
          fr: 'Galaxy S21 Ultra',
          en: 'Galaxy S21 Ultra')),
  MaSuggestion(
      id: 'galaxy_s22',
      label: L10n3(ar: 'جالاكسي إس 22', fr: 'Galaxy S22', en: 'Galaxy S22')),
  MaSuggestion(
      id: 'galaxy_s22_plus',
      label:
          L10n3(ar: 'جالاكسي إس 22 بلس', fr: 'Galaxy S22+', en: 'Galaxy S22+')),
  MaSuggestion(
      id: 'galaxy_s22_ultra',
      label: L10n3(
          ar: 'جالاكسي إس 22 ألترا',
          fr: 'Galaxy S22 Ultra',
          en: 'Galaxy S22 Ultra')),
  MaSuggestion(
      id: 'galaxy_s23',
      label: L10n3(ar: 'جالاكسي إس 23', fr: 'Galaxy S23', en: 'Galaxy S23')),
  MaSuggestion(
      id: 'galaxy_s23_plus',
      label:
          L10n3(ar: 'جالاكسي إس 23 بلس', fr: 'Galaxy S23+', en: 'Galaxy S23+')),
  MaSuggestion(
      id: 'galaxy_s23_ultra',
      label: L10n3(
          ar: 'جالاكسي إس 23 ألترا',
          fr: 'Galaxy S23 Ultra',
          en: 'Galaxy S23 Ultra')),
  MaSuggestion(
      id: 'galaxy_s24',
      label: L10n3(ar: 'جالاكسي إس 24', fr: 'Galaxy S24', en: 'Galaxy S24')),
  MaSuggestion(
      id: 'galaxy_s24_plus',
      label:
          L10n3(ar: 'جالاكسي إس 24 بلس', fr: 'Galaxy S24+', en: 'Galaxy S24+')),
  MaSuggestion(
      id: 'galaxy_s24_ultra',
      label: L10n3(
          ar: 'جالاكسي إس 24 ألترا',
          fr: 'Galaxy S24 Ultra',
          en: 'Galaxy S24 Ultra')),
  MaSuggestion(
      id: 'galaxy_s25',
      label: L10n3(ar: 'جالاكسي إس 25', fr: 'Galaxy S25', en: 'Galaxy S25')),
  MaSuggestion(
      id: 'galaxy_s25_plus',
      label:
          L10n3(ar: 'جالاكسي إس 25 بلس', fr: 'Galaxy S25+', en: 'Galaxy S25+')),
  MaSuggestion(
      id: 'galaxy_s25_ultra',
      label: L10n3(
          ar: 'جالاكسي إس 25 ألترا',
          fr: 'Galaxy S25 Ultra',
          en: 'Galaxy S25 Ultra')),
  MaSuggestion(
      id: 'galaxy_s25_fe',
      label: L10n3(
          ar: 'جالاكسي إس 25 إف إي', fr: 'Galaxy S25 FE', en: 'Galaxy S25 FE')),
  MaSuggestion(
      id: 'galaxy_s25_edge',
      label: L10n3(
          ar: 'جالاكسي إس 25 إيدج',
          fr: 'Galaxy S25 Edge',
          en: 'Galaxy S25 Edge')),
  MaSuggestion(
      id: 'galaxy_note8',
      label:
          L10n3(ar: 'جالاكسي نوت 8', fr: 'Galaxy Note 8', en: 'Galaxy Note 8')),
  MaSuggestion(
      id: 'galaxy_note9',
      label:
          L10n3(ar: 'جالاكسي نوت 9', fr: 'Galaxy Note 9', en: 'Galaxy Note 9')),
  MaSuggestion(
      id: 'galaxy_note10',
      label: L10n3(
          ar: 'جالاكسي نوت 10', fr: 'Galaxy Note 10', en: 'Galaxy Note 10')),
  MaSuggestion(
      id: 'galaxy_note10_plus',
      label: L10n3(
          ar: 'جالاكسي نوت 10+', fr: 'Galaxy Note 10+', en: 'Galaxy Note 10+')),
  MaSuggestion(
      id: 'galaxy_note20',
      label: L10n3(
          ar: 'جالاكسي نوت 20', fr: 'Galaxy Note 20', en: 'Galaxy Note 20')),
  MaSuggestion(
      id: 'galaxy_note20_ultra',
      label: L10n3(
          ar: 'جالاكسي نوت 20 ألترا',
          fr: 'Galaxy Note 20 Ultra',
          en: 'Galaxy Note 20 Ultra')),
  MaSuggestion(
      id: 'galaxy_a10',
      label: L10n3(ar: 'جالاكسي إيه 10', fr: 'Galaxy A10', en: 'Galaxy A10')),
  MaSuggestion(
      id: 'galaxy_a10s',
      label:
          L10n3(ar: 'جالاكسي إيه 10 إس', fr: 'Galaxy A10s', en: 'Galaxy A10s')),
  MaSuggestion(
      id: 'galaxy_a12',
      label: L10n3(ar: 'جالاكسي إيه 12', fr: 'Galaxy A12', en: 'Galaxy A12')),
  MaSuggestion(
      id: 'galaxy_a13',
      label: L10n3(ar: 'جالاكسي إيه 13', fr: 'Galaxy A13', en: 'Galaxy A13')),
  MaSuggestion(
      id: 'galaxy_a14',
      label: L10n3(ar: 'جالاكسي إيه 14', fr: 'Galaxy A14', en: 'Galaxy A14')),
  MaSuggestion(
      id: 'galaxy_a15',
      label: L10n3(ar: 'جالاكسي إيه 15', fr: 'Galaxy A15', en: 'Galaxy A15')),
  MaSuggestion(
      id: 'galaxy_a20',
      label: L10n3(ar: 'جالاكسي إيه 20', fr: 'Galaxy A20', en: 'Galaxy A20')),
  MaSuggestion(
      id: 'galaxy_a21s',
      label:
          L10n3(ar: 'جالاكسي إيه 21 إس', fr: 'Galaxy A21s', en: 'Galaxy A21s')),
  MaSuggestion(
      id: 'galaxy_a22',
      label: L10n3(ar: 'جالاكسي إيه 22', fr: 'Galaxy A22', en: 'Galaxy A22')),
  MaSuggestion(
      id: 'galaxy_a23',
      label: L10n3(ar: 'جالاكسي إيه 23', fr: 'Galaxy A23', en: 'Galaxy A23')),
  MaSuggestion(
      id: 'galaxy_a24',
      label: L10n3(ar: 'جالاكسي إيه 24', fr: 'Galaxy A24', en: 'Galaxy A24')),
  MaSuggestion(
      id: 'galaxy_a25',
      label: L10n3(ar: 'جالاكسي إيه 25', fr: 'Galaxy A25', en: 'Galaxy A25')),
  MaSuggestion(
      id: 'galaxy_a30',
      label: L10n3(ar: 'جالاكسي إيه 30', fr: 'Galaxy A30', en: 'Galaxy A30')),
  MaSuggestion(
      id: 'galaxy_a31',
      label: L10n3(ar: 'جالاكسي إيه 31', fr: 'Galaxy A31', en: 'Galaxy A31')),
  MaSuggestion(
      id: 'galaxy_a32',
      label: L10n3(ar: 'جالاكسي إيه 32', fr: 'Galaxy A32', en: 'Galaxy A32')),
  MaSuggestion(
      id: 'galaxy_a33',
      label: L10n3(ar: 'جالاكسي إيه 33', fr: 'Galaxy A33', en: 'Galaxy A33')),
  MaSuggestion(
      id: 'galaxy_a34',
      label: L10n3(ar: 'جالاكسي إيه 34', fr: 'Galaxy A34', en: 'Galaxy A34')),
  MaSuggestion(
      id: 'galaxy_a35',
      label: L10n3(ar: 'جالاكسي إيه 35', fr: 'Galaxy A35', en: 'Galaxy A35')),
  MaSuggestion(
      id: 'galaxy_a50',
      label: L10n3(ar: 'جالاكسي إيه 50', fr: 'Galaxy A50', en: 'Galaxy A50')),
  MaSuggestion(
      id: 'galaxy_a51',
      label: L10n3(ar: 'جالاكسي إيه 51', fr: 'Galaxy A51', en: 'Galaxy A51')),
  MaSuggestion(
      id: 'galaxy_a52',
      label: L10n3(ar: 'جالاكسي إيه 52', fr: 'Galaxy A52', en: 'Galaxy A52')),
  MaSuggestion(
      id: 'galaxy_a53',
      label: L10n3(ar: 'جالاكسي إيه 53', fr: 'Galaxy A53', en: 'Galaxy A53')),
  MaSuggestion(
      id: 'galaxy_a54',
      label: L10n3(ar: 'جالاكسي إيه 54', fr: 'Galaxy A54', en: 'Galaxy A54')),
  MaSuggestion(
      id: 'galaxy_a55',
      label: L10n3(ar: 'جالاكسي إيه 55', fr: 'Galaxy A55', en: 'Galaxy A55')),
];

// ---------------------------------------------------------------------------
// Vehicles
// ---------------------------------------------------------------------------

const List<MaSuggestion> kToyotaModels = <MaSuggestion>[
  MaSuggestion(
      id: 'toyota_land_cruiser',
      label: L10n3(ar: 'لاند كروزر', fr: 'Land Cruiser', en: 'Land Cruiser')),
  MaSuggestion(
      id: 'toyota_prado', label: L10n3(ar: 'برادو', fr: 'Prado', en: 'Prado')),
  MaSuggestion(
      id: 'toyota_hilux',
      label: L10n3(ar: 'هايلوكس', fr: 'Hilux', en: 'Hilux')),
  MaSuggestion(
      id: 'toyota_corolla',
      label: L10n3(ar: 'كورولا', fr: 'Corolla', en: 'Corolla')),
  MaSuggestion(
      id: 'toyota_yaris', label: L10n3(ar: 'يارس', fr: 'Yaris', en: 'Yaris')),
  MaSuggestion(
      id: 'toyota_camry', label: L10n3(ar: 'كامري', fr: 'Camry', en: 'Camry')),
  MaSuggestion(
      id: 'toyota_rav4', label: L10n3(ar: 'راف 4', fr: 'RAV4', en: 'RAV4')),
  MaSuggestion(
      id: 'toyota_hiace', label: L10n3(ar: 'هايس', fr: 'Hiace', en: 'Hiace')),
];

const List<MaSuggestion> kNissanModels = <MaSuggestion>[
  MaSuggestion(
      id: 'nissan_patrol',
      label: L10n3(ar: 'باترول', fr: 'Patrol', en: 'Patrol')),
  MaSuggestion(
      id: 'nissan_navara',
      label: L10n3(ar: 'نافارا', fr: 'Navara', en: 'Navara')),
  MaSuggestion(
      id: 'nissan_xtrail',
      label: L10n3(ar: 'إكس تريل', fr: 'X-Trail', en: 'X-Trail')),
  MaSuggestion(
      id: 'nissan_qashqai',
      label: L10n3(ar: 'قشقاي', fr: 'Qashqai', en: 'Qashqai')),
];

const List<MaSuggestion> kHyundaiModels = <MaSuggestion>[
  MaSuggestion(
      id: 'hyundai_tucson',
      label: L10n3(ar: 'توسان', fr: 'Tucson', en: 'Tucson')),
  MaSuggestion(
      id: 'hyundai_santa_fe',
      label: L10n3(ar: 'سانتا في', fr: 'Santa Fe', en: 'Santa Fe')),
  MaSuggestion(
      id: 'hyundai_accent',
      label: L10n3(ar: 'أكسنت', fr: 'Accent', en: 'Accent')),
  MaSuggestion(
      id: 'hyundai_elantra',
      label: L10n3(ar: 'إلنترا', fr: 'Elantra', en: 'Elantra')),
];

const List<MaSuggestion> kKiaModels = <MaSuggestion>[
  MaSuggestion(
      id: 'kia_sportage',
      label: L10n3(ar: 'سبورتاج', fr: 'Sportage', en: 'Sportage')),
  MaSuggestion(
      id: 'kia_sorento',
      label: L10n3(ar: 'سورينتو', fr: 'Sorento', en: 'Sorento')),
  MaSuggestion(
      id: 'kia_picanto',
      label: L10n3(ar: 'بيكانتو', fr: 'Picanto', en: 'Picanto')),
  MaSuggestion(id: 'kia_rio', label: L10n3(ar: 'ريو', fr: 'Rio', en: 'Rio')),
];

const List<MaSuggestion> kMercedesModels = <MaSuggestion>[
  MaSuggestion(
      id: 'mercedes_c_class',
      label: L10n3(ar: 'مرسيدس الفئة C', fr: 'Classe C', en: 'C-Class')),
  MaSuggestion(
      id: 'mercedes_e_class',
      label: L10n3(ar: 'مرسيدس الفئة E', fr: 'Classe E', en: 'E-Class')),
  MaSuggestion(
      id: 'mercedes_gla', label: L10n3(ar: 'مرسيدس GLA', fr: 'GLA', en: 'GLA')),
  MaSuggestion(
      id: 'mercedes_glc', label: L10n3(ar: 'مرسيدس GLC', fr: 'GLC', en: 'GLC')),
  MaSuggestion(
      id: 'mercedes_gle', label: L10n3(ar: 'مرسيدس GLE', fr: 'GLE', en: 'GLE')),
];

const List<MaSuggestion> kMitsubishiModels = <MaSuggestion>[
  MaSuggestion(
      id: 'mitsubishi_l200',
      label: L10n3(ar: 'ميتسوبيشي إل 200', fr: 'L200', en: 'L200')),
  MaSuggestion(
      id: 'mitsubishi_pajero',
      label: L10n3(ar: 'باجيرو', fr: 'Pajero', en: 'Pajero')),
];

const List<MaSuggestion> kOtherCommonCarModels = <MaSuggestion>[
  MaSuggestion(
      id: 'vw_golf',
      label: L10n3(ar: 'فولكس فاغن غولف', fr: 'Golf', en: 'Golf')),
  MaSuggestion(
      id: 'vw_passat',
      label: L10n3(ar: 'فولكس فاغن باسات', fr: 'Passat', en: 'Passat')),
  MaSuggestion(
      id: 'peugeot_301',
      label: L10n3(ar: 'بيجو 301', fr: 'Peugeot 301', en: 'Peugeot 301')),
  MaSuggestion(
      id: 'peugeot_308',
      label: L10n3(ar: 'بيجو 308', fr: 'Peugeot 308', en: 'Peugeot 308')),
  MaSuggestion(
      id: 'renault_duster',
      label: L10n3(ar: 'رينو داستر', fr: 'Duster', en: 'Duster')),
  MaSuggestion(
      id: 'ford_ranger',
      label: L10n3(ar: 'فورد رينجر', fr: 'Ranger', en: 'Ranger')),
];
