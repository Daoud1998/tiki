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
String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), '');

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
    if (t.isEmpty) return <MaSuggestion>[...kIPhoneModels, ...kSamsungModels];

    if (_typeLooksLike(t, const [
      'apple',
      'iphone',
      'ios',
      'آيفون',
      'ايفون',
      'أيفون',
    ])) {
      return kIPhoneModels;
    }
    if (_typeLooksLike(t, const [
      'samsung',
      'galaxy',
      'سامسونج',
      'سمسونج',
    ])) {
      return kSamsungModels;
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
      label: L10n3(ar: 'iPhone 4', fr: 'iPhone 4', en: 'iPhone 4')),
  MaSuggestion(
      id: 'iphone_4s',
      label: L10n3(ar: 'iPhone 4s', fr: 'iPhone 4s', en: 'iPhone 4s')),
  MaSuggestion(
      id: 'iphone_5',
      label: L10n3(ar: 'iPhone 5', fr: 'iPhone 5', en: 'iPhone 5')),
  MaSuggestion(
      id: 'iphone_5c',
      label: L10n3(ar: 'iPhone 5c', fr: 'iPhone 5c', en: 'iPhone 5c')),
  MaSuggestion(
      id: 'iphone_5s',
      label: L10n3(ar: 'iPhone 5s', fr: 'iPhone 5s', en: 'iPhone 5s')),
  MaSuggestion(
      id: 'iphone_6',
      label: L10n3(ar: 'iPhone 6', fr: 'iPhone 6', en: 'iPhone 6')),
  MaSuggestion(
      id: 'iphone_6_plus',
      label:
          L10n3(ar: 'iPhone 6 Plus', fr: 'iPhone 6 Plus', en: 'iPhone 6 Plus')),
  MaSuggestion(
      id: 'iphone_6s',
      label: L10n3(ar: 'iPhone 6s', fr: 'iPhone 6s', en: 'iPhone 6s')),
  MaSuggestion(
      id: 'iphone_6s_plus',
      label: L10n3(
          ar: 'iPhone 6s Plus', fr: 'iPhone 6s Plus', en: 'iPhone 6s Plus')),
  MaSuggestion(
      id: 'iphone_se_2016',
      label: L10n3(
          ar: 'iPhone SE (2016)',
          fr: 'iPhone SE (2016)',
          en: 'iPhone SE (2016)')),
  MaSuggestion(
      id: 'iphone_7',
      label: L10n3(ar: 'iPhone 7', fr: 'iPhone 7', en: 'iPhone 7')),
  MaSuggestion(
      id: 'iphone_7_plus',
      label:
          L10n3(ar: 'iPhone 7 Plus', fr: 'iPhone 7 Plus', en: 'iPhone 7 Plus')),
  MaSuggestion(
      id: 'iphone_8',
      label: L10n3(ar: 'iPhone 8', fr: 'iPhone 8', en: 'iPhone 8')),
  MaSuggestion(
      id: 'iphone_8_plus',
      label:
          L10n3(ar: 'iPhone 8 Plus', fr: 'iPhone 8 Plus', en: 'iPhone 8 Plus')),
  MaSuggestion(
      id: 'iphone_x',
      label: L10n3(ar: 'iPhone X', fr: 'iPhone X', en: 'iPhone X')),
  MaSuggestion(
      id: 'iphone_xr',
      label: L10n3(ar: 'iPhone XR', fr: 'iPhone XR', en: 'iPhone XR')),
  MaSuggestion(
      id: 'iphone_xs',
      label: L10n3(ar: 'iPhone XS', fr: 'iPhone XS', en: 'iPhone XS')),
  MaSuggestion(
      id: 'iphone_xs_max',
      label:
          L10n3(ar: 'iPhone XS Max', fr: 'iPhone XS Max', en: 'iPhone XS Max')),
  MaSuggestion(
      id: 'iphone_11',
      label: L10n3(ar: 'iPhone 11', fr: 'iPhone 11', en: 'iPhone 11')),
  MaSuggestion(
      id: 'iphone_11_pro',
      label:
          L10n3(ar: 'iPhone 11 Pro', fr: 'iPhone 11 Pro', en: 'iPhone 11 Pro')),
  MaSuggestion(
      id: 'iphone_11_pro_max',
      label: L10n3(
          ar: 'iPhone 11 Pro Max',
          fr: 'iPhone 11 Pro Max',
          en: 'iPhone 11 Pro Max')),
  MaSuggestion(
      id: 'iphone_se_2020',
      label: L10n3(
          ar: 'iPhone SE (2020)',
          fr: 'iPhone SE (2020)',
          en: 'iPhone SE (2020)')),
  MaSuggestion(
      id: 'iphone_12_mini',
      label: L10n3(
          ar: 'iPhone 12 mini', fr: 'iPhone 12 mini', en: 'iPhone 12 mini')),
  MaSuggestion(
      id: 'iphone_12',
      label: L10n3(ar: 'iPhone 12', fr: 'iPhone 12', en: 'iPhone 12')),
  MaSuggestion(
      id: 'iphone_12_pro',
      label:
          L10n3(ar: 'iPhone 12 Pro', fr: 'iPhone 12 Pro', en: 'iPhone 12 Pro')),
  MaSuggestion(
      id: 'iphone_12_pro_max',
      label: L10n3(
          ar: 'iPhone 12 Pro Max',
          fr: 'iPhone 12 Pro Max',
          en: 'iPhone 12 Pro Max')),
  MaSuggestion(
      id: 'iphone_13_mini',
      label: L10n3(
          ar: 'iPhone 13 mini', fr: 'iPhone 13 mini', en: 'iPhone 13 mini')),
  MaSuggestion(
      id: 'iphone_13',
      label: L10n3(ar: 'iPhone 13', fr: 'iPhone 13', en: 'iPhone 13')),
  MaSuggestion(
      id: 'iphone_13_pro',
      label:
          L10n3(ar: 'iPhone 13 Pro', fr: 'iPhone 13 Pro', en: 'iPhone 13 Pro')),
  MaSuggestion(
      id: 'iphone_13_pro_max',
      label: L10n3(
          ar: 'iPhone 13 Pro Max',
          fr: 'iPhone 13 Pro Max',
          en: 'iPhone 13 Pro Max')),
  MaSuggestion(
      id: 'iphone_se_2022',
      label: L10n3(
          ar: 'iPhone SE (2022)',
          fr: 'iPhone SE (2022)',
          en: 'iPhone SE (2022)')),
  MaSuggestion(
      id: 'iphone_14',
      label: L10n3(ar: 'iPhone 14', fr: 'iPhone 14', en: 'iPhone 14')),
  MaSuggestion(
      id: 'iphone_14_plus',
      label: L10n3(
          ar: 'iPhone 14 Plus', fr: 'iPhone 14 Plus', en: 'iPhone 14 Plus')),
  MaSuggestion(
      id: 'iphone_14_pro',
      label:
          L10n3(ar: 'iPhone 14 Pro', fr: 'iPhone 14 Pro', en: 'iPhone 14 Pro')),
  MaSuggestion(
      id: 'iphone_14_pro_max',
      label: L10n3(
          ar: 'iPhone 14 Pro Max',
          fr: 'iPhone 14 Pro Max',
          en: 'iPhone 14 Pro Max')),
  MaSuggestion(
      id: 'iphone_15',
      label: L10n3(ar: 'iPhone 15', fr: 'iPhone 15', en: 'iPhone 15')),
  MaSuggestion(
      id: 'iphone_15_plus',
      label: L10n3(
          ar: 'iPhone 15 Plus', fr: 'iPhone 15 Plus', en: 'iPhone 15 Plus')),
  MaSuggestion(
      id: 'iphone_15_pro',
      label:
          L10n3(ar: 'iPhone 15 Pro', fr: 'iPhone 15 Pro', en: 'iPhone 15 Pro')),
  MaSuggestion(
      id: 'iphone_15_pro_max',
      label: L10n3(
          ar: 'iPhone 15 Pro Max',
          fr: 'iPhone 15 Pro Max',
          en: 'iPhone 15 Pro Max')),
  MaSuggestion(
      id: 'iphone_16',
      label: L10n3(ar: 'iPhone 16', fr: 'iPhone 16', en: 'iPhone 16')),
  MaSuggestion(
      id: 'iphone_16_plus',
      label: L10n3(
          ar: 'iPhone 16 Plus', fr: 'iPhone 16 Plus', en: 'iPhone 16 Plus')),
  MaSuggestion(
      id: 'iphone_16_pro',
      label:
          L10n3(ar: 'iPhone 16 Pro', fr: 'iPhone 16 Pro', en: 'iPhone 16 Pro')),
  MaSuggestion(
      id: 'iphone_16_pro_max',
      label: L10n3(
          ar: 'iPhone 16 Pro Max',
          fr: 'iPhone 16 Pro Max',
          en: 'iPhone 16 Pro Max')),
  MaSuggestion(
      id: 'iphone_16e',
      label: L10n3(ar: 'iPhone 16e', fr: 'iPhone 16e', en: 'iPhone 16e')),
];

const List<MaSuggestion> kSamsungModels = <MaSuggestion>[
  MaSuggestion(
      id: 'galaxy_s8',
      label: L10n3(ar: 'Galaxy S8', fr: 'Galaxy S8', en: 'Galaxy S8')),
  MaSuggestion(
      id: 'galaxy_s9',
      label: L10n3(ar: 'Galaxy S9', fr: 'Galaxy S9', en: 'Galaxy S9')),
  MaSuggestion(
      id: 'galaxy_s10',
      label: L10n3(ar: 'Galaxy S10', fr: 'Galaxy S10', en: 'Galaxy S10')),
  MaSuggestion(
      id: 'galaxy_s10_plus',
      label: L10n3(ar: 'Galaxy S10+', fr: 'Galaxy S10+', en: 'Galaxy S10+')),
  MaSuggestion(
      id: 'galaxy_s20',
      label: L10n3(ar: 'Galaxy S20', fr: 'Galaxy S20', en: 'Galaxy S20')),
  MaSuggestion(
      id: 'galaxy_s20_plus',
      label: L10n3(ar: 'Galaxy S20+', fr: 'Galaxy S20+', en: 'Galaxy S20+')),
  MaSuggestion(
      id: 'galaxy_s20_ultra',
      label: L10n3(
          ar: 'Galaxy S20 Ultra',
          fr: 'Galaxy S20 Ultra',
          en: 'Galaxy S20 Ultra')),
  MaSuggestion(
      id: 'galaxy_s21',
      label: L10n3(ar: 'Galaxy S21', fr: 'Galaxy S21', en: 'Galaxy S21')),
  MaSuggestion(
      id: 'galaxy_s21_plus',
      label: L10n3(ar: 'Galaxy S21+', fr: 'Galaxy S21+', en: 'Galaxy S21+')),
  MaSuggestion(
      id: 'galaxy_s21_ultra',
      label: L10n3(
          ar: 'Galaxy S21 Ultra',
          fr: 'Galaxy S21 Ultra',
          en: 'Galaxy S21 Ultra')),
  MaSuggestion(
      id: 'galaxy_s22',
      label: L10n3(ar: 'Galaxy S22', fr: 'Galaxy S22', en: 'Galaxy S22')),
  MaSuggestion(
      id: 'galaxy_s22_plus',
      label: L10n3(ar: 'Galaxy S22+', fr: 'Galaxy S22+', en: 'Galaxy S22+')),
  MaSuggestion(
      id: 'galaxy_s22_ultra',
      label: L10n3(
          ar: 'Galaxy S22 Ultra',
          fr: 'Galaxy S22 Ultra',
          en: 'Galaxy S22 Ultra')),
  MaSuggestion(
      id: 'galaxy_s23',
      label: L10n3(ar: 'Galaxy S23', fr: 'Galaxy S23', en: 'Galaxy S23')),
  MaSuggestion(
      id: 'galaxy_s23_plus',
      label: L10n3(ar: 'Galaxy S23+', fr: 'Galaxy S23+', en: 'Galaxy S23+')),
  MaSuggestion(
      id: 'galaxy_s23_ultra',
      label: L10n3(
          ar: 'Galaxy S23 Ultra',
          fr: 'Galaxy S23 Ultra',
          en: 'Galaxy S23 Ultra')),
  MaSuggestion(
      id: 'galaxy_s24',
      label: L10n3(ar: 'Galaxy S24', fr: 'Galaxy S24', en: 'Galaxy S24')),
  MaSuggestion(
      id: 'galaxy_s24_plus',
      label: L10n3(ar: 'Galaxy S24+', fr: 'Galaxy S24+', en: 'Galaxy S24+')),
  MaSuggestion(
      id: 'galaxy_s24_ultra',
      label: L10n3(
          ar: 'Galaxy S24 Ultra',
          fr: 'Galaxy S24 Ultra',
          en: 'Galaxy S24 Ultra')),
  MaSuggestion(
      id: 'galaxy_s25',
      label: L10n3(ar: 'Galaxy S25', fr: 'Galaxy S25', en: 'Galaxy S25')),
  MaSuggestion(
      id: 'galaxy_s25_plus',
      label: L10n3(ar: 'Galaxy S25+', fr: 'Galaxy S25+', en: 'Galaxy S25+')),
  MaSuggestion(
      id: 'galaxy_s25_ultra',
      label: L10n3(
          ar: 'Galaxy S25 Ultra',
          fr: 'Galaxy S25 Ultra',
          en: 'Galaxy S25 Ultra')),
  MaSuggestion(
      id: 'galaxy_s25_fe',
      label:
          L10n3(ar: 'Galaxy S25 FE', fr: 'Galaxy S25 FE', en: 'Galaxy S25 FE')),
  MaSuggestion(
      id: 'galaxy_s25_edge',
      label: L10n3(
          ar: 'Galaxy S25 Edge', fr: 'Galaxy S25 Edge', en: 'Galaxy S25 Edge')),
  MaSuggestion(
      id: 'galaxy_note8',
      label:
          L10n3(ar: 'Galaxy Note 8', fr: 'Galaxy Note 8', en: 'Galaxy Note 8')),
  MaSuggestion(
      id: 'galaxy_note9',
      label:
          L10n3(ar: 'Galaxy Note 9', fr: 'Galaxy Note 9', en: 'Galaxy Note 9')),
  MaSuggestion(
      id: 'galaxy_note10',
      label: L10n3(
          ar: 'Galaxy Note 10', fr: 'Galaxy Note 10', en: 'Galaxy Note 10')),
  MaSuggestion(
      id: 'galaxy_note10_plus',
      label: L10n3(
          ar: 'Galaxy Note 10+', fr: 'Galaxy Note 10+', en: 'Galaxy Note 10+')),
  MaSuggestion(
      id: 'galaxy_note20',
      label: L10n3(
          ar: 'Galaxy Note 20', fr: 'Galaxy Note 20', en: 'Galaxy Note 20')),
  MaSuggestion(
      id: 'galaxy_note20_ultra',
      label: L10n3(
          ar: 'Galaxy Note 20 Ultra',
          fr: 'Galaxy Note 20 Ultra',
          en: 'Galaxy Note 20 Ultra')),
  MaSuggestion(
      id: 'galaxy_a10',
      label: L10n3(ar: 'Galaxy A10', fr: 'Galaxy A10', en: 'Galaxy A10')),
  MaSuggestion(
      id: 'galaxy_a10s',
      label: L10n3(ar: 'Galaxy A10s', fr: 'Galaxy A10s', en: 'Galaxy A10s')),
  MaSuggestion(
      id: 'galaxy_a12',
      label: L10n3(ar: 'Galaxy A12', fr: 'Galaxy A12', en: 'Galaxy A12')),
  MaSuggestion(
      id: 'galaxy_a13',
      label: L10n3(ar: 'Galaxy A13', fr: 'Galaxy A13', en: 'Galaxy A13')),
  MaSuggestion(
      id: 'galaxy_a14',
      label: L10n3(ar: 'Galaxy A14', fr: 'Galaxy A14', en: 'Galaxy A14')),
  MaSuggestion(
      id: 'galaxy_a15',
      label: L10n3(ar: 'Galaxy A15', fr: 'Galaxy A15', en: 'Galaxy A15')),
  MaSuggestion(
      id: 'galaxy_a20',
      label: L10n3(ar: 'Galaxy A20', fr: 'Galaxy A20', en: 'Galaxy A20')),
  MaSuggestion(
      id: 'galaxy_a21s',
      label: L10n3(ar: 'Galaxy A21s', fr: 'Galaxy A21s', en: 'Galaxy A21s')),
  MaSuggestion(
      id: 'galaxy_a22',
      label: L10n3(ar: 'Galaxy A22', fr: 'Galaxy A22', en: 'Galaxy A22')),
  MaSuggestion(
      id: 'galaxy_a23',
      label: L10n3(ar: 'Galaxy A23', fr: 'Galaxy A23', en: 'Galaxy A23')),
  MaSuggestion(
      id: 'galaxy_a24',
      label: L10n3(ar: 'Galaxy A24', fr: 'Galaxy A24', en: 'Galaxy A24')),
  MaSuggestion(
      id: 'galaxy_a25',
      label: L10n3(ar: 'Galaxy A25', fr: 'Galaxy A25', en: 'Galaxy A25')),
  MaSuggestion(
      id: 'galaxy_a30',
      label: L10n3(ar: 'Galaxy A30', fr: 'Galaxy A30', en: 'Galaxy A30')),
  MaSuggestion(
      id: 'galaxy_a31',
      label: L10n3(ar: 'Galaxy A31', fr: 'Galaxy A31', en: 'Galaxy A31')),
  MaSuggestion(
      id: 'galaxy_a32',
      label: L10n3(ar: 'Galaxy A32', fr: 'Galaxy A32', en: 'Galaxy A32')),
  MaSuggestion(
      id: 'galaxy_a33',
      label: L10n3(ar: 'Galaxy A33', fr: 'Galaxy A33', en: 'Galaxy A33')),
  MaSuggestion(
      id: 'galaxy_a34',
      label: L10n3(ar: 'Galaxy A34', fr: 'Galaxy A34', en: 'Galaxy A34')),
  MaSuggestion(
      id: 'galaxy_a35',
      label: L10n3(ar: 'Galaxy A35', fr: 'Galaxy A35', en: 'Galaxy A35')),
  MaSuggestion(
      id: 'galaxy_a50',
      label: L10n3(ar: 'Galaxy A50', fr: 'Galaxy A50', en: 'Galaxy A50')),
  MaSuggestion(
      id: 'galaxy_a51',
      label: L10n3(ar: 'Galaxy A51', fr: 'Galaxy A51', en: 'Galaxy A51')),
  MaSuggestion(
      id: 'galaxy_a52',
      label: L10n3(ar: 'Galaxy A52', fr: 'Galaxy A52', en: 'Galaxy A52')),
  MaSuggestion(
      id: 'galaxy_a53',
      label: L10n3(ar: 'Galaxy A53', fr: 'Galaxy A53', en: 'Galaxy A53')),
  MaSuggestion(
      id: 'galaxy_a54',
      label: L10n3(ar: 'Galaxy A54', fr: 'Galaxy A54', en: 'Galaxy A54')),
  MaSuggestion(
      id: 'galaxy_a55',
      label: L10n3(ar: 'Galaxy A55', fr: 'Galaxy A55', en: 'Galaxy A55')),
];

// ---------------------------------------------------------------------------
// Vehicles
// ---------------------------------------------------------------------------

const List<MaSuggestion> kToyotaModels = <MaSuggestion>[
  MaSuggestion(
      id: 'toyota_land_cruiser',
      label: L10n3(ar: 'Land Cruiser', fr: 'Land Cruiser', en: 'Land Cruiser')),
  MaSuggestion(
      id: 'toyota_prado', label: L10n3(ar: 'Prado', fr: 'Prado', en: 'Prado')),
  MaSuggestion(
      id: 'toyota_hilux', label: L10n3(ar: 'Hilux', fr: 'Hilux', en: 'Hilux')),
  MaSuggestion(
      id: 'toyota_corolla',
      label: L10n3(ar: 'Corolla', fr: 'Corolla', en: 'Corolla')),
  MaSuggestion(
      id: 'toyota_yaris', label: L10n3(ar: 'Yaris', fr: 'Yaris', en: 'Yaris')),
  MaSuggestion(
      id: 'toyota_camry', label: L10n3(ar: 'Camry', fr: 'Camry', en: 'Camry')),
  MaSuggestion(
      id: 'toyota_rav4', label: L10n3(ar: 'RAV4', fr: 'RAV4', en: 'RAV4')),
  MaSuggestion(
      id: 'toyota_hiace', label: L10n3(ar: 'Hiace', fr: 'Hiace', en: 'Hiace')),
];

const List<MaSuggestion> kNissanModels = <MaSuggestion>[
  MaSuggestion(
      id: 'nissan_patrol',
      label: L10n3(ar: 'Patrol', fr: 'Patrol', en: 'Patrol')),
  MaSuggestion(
      id: 'nissan_navara',
      label: L10n3(ar: 'Navara', fr: 'Navara', en: 'Navara')),
  MaSuggestion(
      id: 'nissan_xtrail',
      label: L10n3(ar: 'X-Trail', fr: 'X-Trail', en: 'X-Trail')),
  MaSuggestion(
      id: 'nissan_qashqai',
      label: L10n3(ar: 'Qashqai', fr: 'Qashqai', en: 'Qashqai')),
];

const List<MaSuggestion> kHyundaiModels = <MaSuggestion>[
  MaSuggestion(
      id: 'hyundai_tucson',
      label: L10n3(ar: 'Tucson', fr: 'Tucson', en: 'Tucson')),
  MaSuggestion(
      id: 'hyundai_santa_fe',
      label: L10n3(ar: 'Santa Fe', fr: 'Santa Fe', en: 'Santa Fe')),
  MaSuggestion(
      id: 'hyundai_accent',
      label: L10n3(ar: 'Accent', fr: 'Accent', en: 'Accent')),
  MaSuggestion(
      id: 'hyundai_elantra',
      label: L10n3(ar: 'Elantra', fr: 'Elantra', en: 'Elantra')),
];

const List<MaSuggestion> kKiaModels = <MaSuggestion>[
  MaSuggestion(
      id: 'kia_sportage',
      label: L10n3(ar: 'Sportage', fr: 'Sportage', en: 'Sportage')),
  MaSuggestion(
      id: 'kia_sorento',
      label: L10n3(ar: 'Sorento', fr: 'Sorento', en: 'Sorento')),
  MaSuggestion(
      id: 'kia_picanto',
      label: L10n3(ar: 'Picanto', fr: 'Picanto', en: 'Picanto')),
  MaSuggestion(id: 'kia_rio', label: L10n3(ar: 'Rio', fr: 'Rio', en: 'Rio')),
];

const List<MaSuggestion> kMercedesModels = <MaSuggestion>[
  MaSuggestion(
      id: 'mercedes_c_class',
      label: L10n3(ar: 'C-Class', fr: 'Classe C', en: 'C-Class')),
  MaSuggestion(
      id: 'mercedes_e_class',
      label: L10n3(ar: 'E-Class', fr: 'Classe E', en: 'E-Class')),
  MaSuggestion(
      id: 'mercedes_gla', label: L10n3(ar: 'GLA', fr: 'GLA', en: 'GLA')),
  MaSuggestion(
      id: 'mercedes_glc', label: L10n3(ar: 'GLC', fr: 'GLC', en: 'GLC')),
  MaSuggestion(
      id: 'mercedes_gle', label: L10n3(ar: 'GLE', fr: 'GLE', en: 'GLE')),
];

const List<MaSuggestion> kMitsubishiModels = <MaSuggestion>[
  MaSuggestion(
      id: 'mitsubishi_l200', label: L10n3(ar: 'L200', fr: 'L200', en: 'L200')),
  MaSuggestion(
      id: 'mitsubishi_pajero',
      label: L10n3(ar: 'Pajero', fr: 'Pajero', en: 'Pajero')),
];

const List<MaSuggestion> kOtherCommonCarModels = <MaSuggestion>[
  MaSuggestion(id: 'vw_golf', label: L10n3(ar: 'Golf', fr: 'Golf', en: 'Golf')),
  MaSuggestion(
      id: 'vw_passat', label: L10n3(ar: 'Passat', fr: 'Passat', en: 'Passat')),
  MaSuggestion(
      id: 'peugeot_301',
      label: L10n3(ar: 'Peugeot 301', fr: 'Peugeot 301', en: 'Peugeot 301')),
  MaSuggestion(
      id: 'peugeot_308',
      label: L10n3(ar: 'Peugeot 308', fr: 'Peugeot 308', en: 'Peugeot 308')),
  MaSuggestion(
      id: 'renault_duster',
      label: L10n3(ar: 'Duster', fr: 'Duster', en: 'Duster')),
  MaSuggestion(
      id: 'ford_ranger',
      label: L10n3(ar: 'Ranger', fr: 'Ranger', en: 'Ranger')),
];
