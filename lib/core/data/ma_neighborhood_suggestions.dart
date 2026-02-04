import 'ma_catalog.dart';
import 'ma_suggestions.dart';

/// Neighborhood suggestions (أحياء) for the busiest local markets:
/// - Nouakchott (all 9 moughataas)
/// - Nouadhibou + Chami
///
/// Notes:
/// - This is a "helper" list, not an official gazette.
/// - Users can always choose manual entry.

List<MaSuggestion> neighborhoodSuggestionsFor({
  required String? wilayaId,
  required String? moughataaId,
}) {
  final mid = (moughataaId ?? '').trim();
  if (mid.isNotEmpty) {
    final list = _byMoughataa[mid];
    if (list != null && list.isNotEmpty) return list;
  }

  // If only the wilaya is known (and it's one of the busy ones), we can offer
  // a combined list.
  final wid = (wilayaId ?? '').trim();
  if (wid.startsWith('nouakchott_')) {
    return _nouakchottAll;
  }
  if (wid == 'dakhlet_nouadhibou') {
    return _nouadhibouAll;
  }
  return const <MaSuggestion>[];
}

final Map<String, List<MaSuggestion>> _byMoughataa =
    <String, List<MaSuggestion>>{
  // Nouakchott Ouest
  'tevragh_zeina': const <MaSuggestion>[
    MaSuggestion(
        id: 'tz_tevragh',
        label:
            L10n3(ar: 'تفرغ زينة', fr: 'Tevragh Zeina', en: 'Tevragh Zeina')),
    MaSuggestion(
        id: 'tz_diplomatic',
        label: L10n3(
            ar: 'الحي الدبلوماسي',
            fr: 'Quartier diplomatique',
            en: 'Diplomatic quarter')),
    MaSuggestion(
        id: 'tz_ilot_k',
        label: L10n3(ar: 'الحي K', fr: 'Ilot K', en: 'Ilot K')),
    MaSuggestion(
        id: 'tz_ilot_l',
        label: L10n3(ar: 'الحي L', fr: 'Ilot L', en: 'Ilot L')),
    MaSuggestion(
        id: 'tz_ilot_m',
        label: L10n3(ar: 'الحي M', fr: 'Ilot M', en: 'Ilot M')),
    MaSuggestion(
        id: 'tz_ilot_n',
        label: L10n3(ar: 'الحي N', fr: 'Ilot N', en: 'Ilot N')),
    MaSuggestion(
        id: 'tz_ilot_o',
        label: L10n3(ar: 'الحي O', fr: 'Ilot O', en: 'Ilot O')),
    MaSuggestion(
        id: 'tz_ilot_p',
        label: L10n3(ar: 'الحي P', fr: 'Ilot P', en: 'Ilot P')),
    MaSuggestion(
        id: 'tz_ilot_q',
        label: L10n3(ar: 'الحي Q', fr: 'Ilot Q', en: 'Ilot Q')),
    MaSuggestion(
        id: 'tz_ilot_r',
        label: L10n3(ar: 'الحي R', fr: 'Ilot R', en: 'Ilot R')),
    MaSuggestion(
        id: 'tz_ilot_s',
        label: L10n3(ar: 'الحي S', fr: 'Ilot S', en: 'Ilot S')),
    MaSuggestion(
        id: 'tz_ilot_t',
        label: L10n3(ar: 'الحي T', fr: 'Ilot T', en: 'Ilot T')),
  ],
  'ksar': const <MaSuggestion>[
    MaSuggestion(
        id: 'ksar_ksar', label: L10n3(ar: 'لكصر', fr: 'Ksar', en: 'Ksar')),
    MaSuggestion(
        id: 'ksar_old',
        label: L10n3(ar: 'لكصر القديم', fr: 'Vieux Ksar', en: 'Old Ksar')),
    MaSuggestion(
        id: 'ksar_center',
        label: L10n3(ar: 'وسط لكصر', fr: 'Centre Ksar', en: 'Ksar Center')),
    MaSuggestion(
        id: 'ksar_souk',
        label: L10n3(ar: 'قرب السوق', fr: 'Près du marché', en: 'Near market')),
    MaSuggestion(
        id: 'ksar_univ',
        label: L10n3(
            ar: 'قرب الجامعة',
            fr: 'Près de l’université',
            en: 'Near university')),
  ],
  'sebkha': const <MaSuggestion>[
    MaSuggestion(
        id: 'sebkha_sebkha',
        label: L10n3(ar: 'السبخة', fr: 'Sebkha', en: 'Sebkha')),
    MaSuggestion(
        id: 'sebkha_souk',
        label: L10n3(
            ar: 'سوق السبخة', fr: 'Marché de Sebkha', en: 'Sebkha market')),
    MaSuggestion(
        id: 'sebkha_oumoul',
        label: L10n3(
            ar: 'حي العمال',
            fr: 'Quartier des ouvriers',
            en: 'Workers quarter')),
    MaSuggestion(
        id: 'sebkha_beach',
        label:
            L10n3(ar: 'قرب البحر', fr: 'Près de la mer', en: 'Near the sea')),
  ],

  // Nouakchott Nord
  'teyarett': const <MaSuggestion>[
    MaSuggestion(
        id: 'teyarett_teyarett',
        label: L10n3(ar: 'تيارت', fr: 'Teyarett', en: 'Teyarett')),
    MaSuggestion(
        id: 'teyarett_souk',
        label: L10n3(
            ar: 'سوق تيارت', fr: 'Marché de Teyarett', en: 'Teyarett market')),
    MaSuggestion(
        id: 'teyarett_road',
        label: L10n3(ar: 'شارع 50 متر', fr: 'Route 50m', en: '50m road')),
    MaSuggestion(
        id: 'teyarett_school',
        label: L10n3(
            ar: 'قرب المدارس', fr: 'Près des écoles', en: 'Near schools')),
  ],
  'dar_naim': const <MaSuggestion>[
    MaSuggestion(
        id: 'dar_naim_darnaim',
        label: L10n3(ar: 'دار النعيم', fr: 'Dar Naim', en: 'Dar Naim')),
    MaSuggestion(
        id: 'dar_naim_souk',
        label: L10n3(
            ar: 'سوق دار النعيم',
            fr: 'Marché Dar Naim',
            en: 'Dar Naim market')),
    MaSuggestion(
        id: 'dar_naim_terhil',
        label: L10n3(ar: 'حي الترحيل', fr: 'Relogement', en: 'Resettlement')),
    MaSuggestion(
        id: 'dar_naim_extension',
        label: L10n3(ar: 'الامتداد', fr: 'Extension', en: 'Extension')),
  ],
  'toujounine': const <MaSuggestion>[
    MaSuggestion(
        id: 'toujounine_main',
        label: L10n3(ar: 'توجونين', fr: 'Toujounine', en: 'Toujounine')),
    MaSuggestion(
        id: 'toujounine_saada',
        label: L10n3(ar: 'حي السعادة', fr: 'Hay Saada', en: 'Hay Saada')),
    MaSuggestion(
        id: 'toujounine_dubai',
        label: L10n3(ar: 'حي دبي', fr: 'Hay Dubai', en: 'Hay Dubai')),
    MaSuggestion(
        id: 'toujounine_souk',
        label: L10n3(
            ar: 'سوق توجونين',
            fr: 'Marché Toujounine',
            en: 'Toujounine market')),
    MaSuggestion(
        id: 'toujounine_terhil',
        label: L10n3(ar: 'حي الترحيل', fr: 'Relogement', en: 'Resettlement')),
  ],

  // Nouakchott Sud
  'arafat': const <MaSuggestion>[
    MaSuggestion(
        id: 'arafat_arafat',
        label: L10n3(ar: 'عرفات', fr: 'Arafat', en: 'Arafat')),
    MaSuggestion(
        id: 'arafat_tensweilm',
        label: L10n3(ar: 'تنسويلم', fr: 'Tensweilm', en: 'Tensweilm')),
    MaSuggestion(
        id: 'arafat_terhil',
        label: L10n3(ar: 'حي الترحيل', fr: 'Relogement', en: 'Resettlement')),
    MaSuggestion(
        id: 'arafat_sector1',
        label: L10n3(ar: 'القطاع 1', fr: 'Secteur 1', en: 'Sector 1')),
    MaSuggestion(
        id: 'arafat_sector2',
        label: L10n3(ar: 'القطاع 2', fr: 'Secteur 2', en: 'Sector 2')),
  ],
  'el_mina': const <MaSuggestion>[
    MaSuggestion(
        id: 'el_mina_mina',
        label: L10n3(ar: 'الميناء', fr: 'El Mina', en: 'El Mina')),
    MaSuggestion(
        id: 'el_mina_souk',
        label: L10n3(
            ar: 'سوق الميناء', fr: 'Marché El Mina', en: 'El Mina market')),
    MaSuggestion(
        id: 'el_mina_baghdad',
        label: L10n3(ar: 'حي بغداد', fr: 'Hay Baghdad', en: 'Hay Baghdad')),
    MaSuggestion(
        id: 'el_mina_terhil',
        label: L10n3(ar: 'حي الترحيل', fr: 'Relogement', en: 'Resettlement')),
  ],
  'riyad': const <MaSuggestion>[
    MaSuggestion(
        id: 'riyad_riyad',
        label: L10n3(ar: 'الرياض', fr: 'Riyad', en: 'Riyad')),
    MaSuggestion(
        id: 'riyad_sector1',
        label: L10n3(ar: 'القطاع 1', fr: 'Secteur 1', en: 'Sector 1')),
    MaSuggestion(
        id: 'riyad_sector2',
        label: L10n3(ar: 'القطاع 2', fr: 'Secteur 2', en: 'Sector 2')),
    MaSuggestion(
        id: 'riyad_sector3',
        label: L10n3(ar: 'القطاع 3', fr: 'Secteur 3', en: 'Sector 3')),
    MaSuggestion(
        id: 'riyad_terhil',
        label: L10n3(ar: 'حي الترحيل', fr: 'Relogement', en: 'Resettlement')),
  ],

  // Nouadhibou
  'nouadhibou': const <MaSuggestion>[
    MaSuggestion(
        id: 'ndb_nouadhibou',
        label: L10n3(ar: 'نواذيبو', fr: 'Nouadhibou', en: 'Nouadhibou')),
    MaSuggestion(
        id: 'ndb_cansado',
        label: L10n3(ar: 'كانصادو', fr: 'Cansado', en: 'Cansado')),
    MaSuggestion(
        id: 'ndb_terhil',
        label: L10n3(ar: 'حي الترحيل', fr: 'Relogement', en: 'Resettlement')),
    MaSuggestion(
        id: 'ndb_airport',
        label: L10n3(
            ar: 'حي المطار', fr: 'Quartier aéroport', en: 'Airport area')),
    MaSuggestion(
        id: 'ndb_industrial',
        label: L10n3(
            ar: 'الحي الصناعي',
            fr: 'Zone industrielle',
            en: 'Industrial zone')),
    MaSuggestion(
        id: 'ndb_boulevard',
        label: L10n3(ar: 'البوليفار', fr: 'Boulevard', en: 'Boulevard')),
    MaSuggestion(
        id: 'ndb_old',
        label:
            L10n3(ar: 'المدينة القديمة', fr: 'Vieille ville', en: 'Old town')),
    MaSuggestion(
        id: 'ndb_hanfia4',
        label: L10n3(ar: 'الحنفية الرابعة', fr: 'Hanfia 4', en: 'Hanfia 4')),
    MaSuggestion(
        id: 'ndb_hanfia5',
        label: L10n3(ar: 'الحنفية الخامسة', fr: 'Hanfia 5', en: 'Hanfia 5')),
  ],
  'chami': const <MaSuggestion>[
    MaSuggestion(
        id: 'chami_chami',
        label: L10n3(ar: 'الشامي', fr: 'Chami', en: 'Chami')),
    MaSuggestion(
        id: 'chami_center',
        label: L10n3(ar: 'وسط الشامي', fr: 'Centre Chami', en: 'Chami center')),
    MaSuggestion(
        id: 'chami_terhil',
        label: L10n3(ar: 'حي الترحيل', fr: 'Relogement', en: 'Resettlement')),
  ],
};

final List<MaSuggestion> _nouakchottAll = <MaSuggestion>[
  for (final mid in const <String>[
    'tevragh_zeina',
    'ksar',
    'sebkha',
    'teyarett',
    'dar_naim',
    'toujounine',
    'arafat',
    'el_mina',
    'riyad',
  ])
    ...(_byMoughataa[mid] ?? const <MaSuggestion>[]),
];

final List<MaSuggestion> _nouadhibouAll = <MaSuggestion>[
  ...(_byMoughataa['nouadhibou'] ?? const <MaSuggestion>[]),
  ...(_byMoughataa['chami'] ?? const <MaSuggestion>[]),
];
