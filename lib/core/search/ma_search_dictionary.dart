import 'package:flutter/material.dart';

/// Mauritania-focused search dictionary:
/// - popular terms & brand names people actually type
/// - simple synonym support (AR/FR/EN + common spellings)
///
/// Use:
///   maQuickSearchChips(locale)
///   maSuggestFromDictionary(query, locale, limit: 8)
///   maNormalizeQuery(text)
class MaSearchEntry {
  const MaSearchEntry({
    required this.ar,
    required this.fr,
    required this.en,
    this.aliases = const <String>[],
    this.tags = const <String>[],
  });

  final String ar;
  final String fr;
  final String en;

  /// Extra spellings (arabizi, brand spellings, common shortcuts)
  final List<String> aliases;

  /// Optional tags you can use later (category hints, etc.)
  final List<String> tags;

  String labelOf(Locale locale) {
    final code = locale.languageCode.toLowerCase();
    if (code == 'ar') return ar;
    if (code == 'fr') return fr;
    return en;
  }

  Iterable<String> allTerms(Locale locale) sync* {
    yield labelOf(locale);
    yield ar;
    yield fr;
    yield en;
    for (final a in aliases) {
      yield a;
    }
  }
}

const List<MaSearchEntry> maSearchDictionary = [
  // Phones
  MaSearchEntry(
    ar: 'آيفون',
    fr: 'iPhone',
    en: 'iPhone',
    aliases: ['iphone', 'ipone', 'ايفون', 'ايفوون'],
    tags: ['phones'],
  ),
  MaSearchEntry(
    ar: 'سامسونج',
    fr: 'Samsung',
    en: 'Samsung',
    aliases: ['samsung', 'sumsung', 'سامسنج'],
    tags: ['phones'],
  ),
  MaSearchEntry(
    ar: 'تيكنو',
    fr: 'Tecno',
    en: 'Tecno',
    aliases: ['tecno', 'تكنو', 'teckno'],
    tags: ['phones'],
  ),
  MaSearchEntry(
    ar: 'إنفينيكس',
    fr: 'Infinix',
    en: 'Infinix',
    aliases: ['infinix', 'انفينيكس', 'infinx'],
    tags: ['phones'],
  ),
  MaSearchEntry(
    ar: 'شاومي',
    fr: 'Xiaomi',
    en: 'Xiaomi',
    aliases: ['xiaomi', 'redmi', 'ريدمي', 'شاومي', 'mi'],
    tags: ['phones'],
  ),


  // iPhone models (popular in Mauritania)
  MaSearchEntry(
    ar: 'آيفون 17',
    fr: 'iPhone 17',
    en: 'iPhone 17',
    aliases: ['iphone17', 'ip 17'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 17 برو',
    fr: 'iPhone 17 Pro',
    en: 'iPhone 17 Pro',
    aliases: ['iphone17 pro', 'ip 17 pro'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 17 برو ماكس',
    fr: 'iPhone 17 Pro Max',
    en: 'iPhone 17 Pro Max',
    aliases: ['iphone17 pro max', 'ip 17 pro max', '17 pro max'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون آير',
    fr: 'iPhone Air',
    en: 'iPhone Air',
    aliases: ['iphone air', 'air iphone'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 16',
    fr: 'iPhone 16',
    en: 'iPhone 16',
    aliases: ['iphone16', 'ip 16'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 16 بلس',
    fr: 'iPhone 16 Plus',
    en: 'iPhone 16 Plus',
    aliases: ['iphone16 plus', 'ip 16 plus', '16 plus'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 16e',
    fr: 'iPhone 16e',
    en: 'iPhone 16e',
    aliases: ['iphone16e', '16e', 'iphone 16e'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 16 برو',
    fr: 'iPhone 16 Pro',
    en: 'iPhone 16 Pro',
    aliases: ['iphone16 pro', 'ip 16 pro'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 16 برو ماكس',
    fr: 'iPhone 16 Pro Max',
    en: 'iPhone 16 Pro Max',
    aliases: ['iphone16 pro max', 'ip 16 pro max', '16 pro max'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 15',
    fr: 'iPhone 15',
    en: 'iPhone 15',
    aliases: ['iphone15', 'ip 15'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 15 بلس',
    fr: 'iPhone 15 Plus',
    en: 'iPhone 15 Plus',
    aliases: ['iphone15 plus', 'ip 15 plus', '15 plus'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 15 برو',
    fr: 'iPhone 15 Pro',
    en: 'iPhone 15 Pro',
    aliases: ['iphone15 pro', 'ip 15 pro'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 15 برو ماكس',
    fr: 'iPhone 15 Pro Max',
    en: 'iPhone 15 Pro Max',
    aliases: ['iphone15 pro max', 'ip 15 pro max', '15 pro max'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 14',
    fr: 'iPhone 14',
    en: 'iPhone 14',
    aliases: ['iphone14', 'ip 14'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 14 بلس',
    fr: 'iPhone 14 Plus',
    en: 'iPhone 14 Plus',
    aliases: ['iphone14 plus', 'ip 14 plus', '14 plus'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 14 برو',
    fr: 'iPhone 14 Pro',
    en: 'iPhone 14 Pro',
    aliases: ['iphone14 pro', 'ip 14 pro'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 14 برو ماكس',
    fr: 'iPhone 14 Pro Max',
    en: 'iPhone 14 Pro Max',
    aliases: ['iphone14 pro max', 'ip 14 pro max', '14 pro max'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 13',
    fr: 'iPhone 13',
    en: 'iPhone 13',
    aliases: ['iphone13', 'ip 13'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 13 ميني',
    fr: 'iPhone 13 mini',
    en: 'iPhone 13 mini',
    aliases: ['iphone13 mini', 'ip 13 mini', '13 mini'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 13 برو',
    fr: 'iPhone 13 Pro',
    en: 'iPhone 13 Pro',
    aliases: ['iphone13 pro', 'ip 13 pro'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 13 برو ماكس',
    fr: 'iPhone 13 Pro Max',
    en: 'iPhone 13 Pro Max',
    aliases: ['iphone13 pro max', 'ip 13 pro max', '13 pro max'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 12',
    fr: 'iPhone 12',
    en: 'iPhone 12',
    aliases: ['iphone12', 'ip 12'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 12 ميني',
    fr: 'iPhone 12 mini',
    en: 'iPhone 12 mini',
    aliases: ['iphone12 mini', 'ip 12 mini', '12 mini'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 12 برو',
    fr: 'iPhone 12 Pro',
    en: 'iPhone 12 Pro',
    aliases: ['iphone12 pro', 'ip 12 pro'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 12 برو ماكس',
    fr: 'iPhone 12 Pro Max',
    en: 'iPhone 12 Pro Max',
    aliases: ['iphone12 pro max', 'ip 12 pro max', '12 pro max'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 11',
    fr: 'iPhone 11',
    en: 'iPhone 11',
    aliases: ['iphone11', 'ip 11'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 11 برو',
    fr: 'iPhone 11 Pro',
    en: 'iPhone 11 Pro',
    aliases: ['iphone11 pro', 'ip 11 pro'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 11 برو ماكس',
    fr: 'iPhone 11 Pro Max',
    en: 'iPhone 11 Pro Max',
    aliases: ['iphone11 pro max', 'ip 11 pro max', '11 pro max'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون إكس',
    fr: 'iPhone X',
    en: 'iPhone X',
    aliases: ['iphone x', 'iphonex', 'ip x', 'x iphone'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون إكس آر',
    fr: 'iPhone XR',
    en: 'iPhone XR',
    aliases: ['iphone xr', 'iphonexr', 'xr iphone'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون إكس إس',
    fr: 'iPhone XS',
    en: 'iPhone XS',
    aliases: ['iphone xs', 'iphonexs', 'xs iphone'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون إكس إس ماكس',
    fr: 'iPhone XS Max',
    en: 'iPhone XS Max',
    aliases: ['iphone xs max', 'iphonexs max', 'xs max'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 8',
    fr: 'iPhone 8',
    en: 'iPhone 8',
    aliases: ['iphone 8', 'iphone8', 'ip 8'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 8 بلس',
    fr: 'iPhone 8 Plus',
    en: 'iPhone 8 Plus',
    aliases: ['iphone 8 plus', 'iphone8 plus', '8 plus'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 7',
    fr: 'iPhone 7',
    en: 'iPhone 7',
    aliases: ['iphone 7', 'iphone7', 'ip 7'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 7 بلس',
    fr: 'iPhone 7 Plus',
    en: 'iPhone 7 Plus',
    aliases: ['iphone 7 plus', 'iphone7 plus', '7 plus'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون 6',
    fr: 'iPhone 6',
    en: 'iPhone 6',
    aliases: ['iphone 6', 'iphone6', 'ip 6'],
    tags: ['phones', 'iphone'],
  ),
  MaSearchEntry(
    ar: 'آيفون إس إي',
    fr: 'iPhone SE',
    en: 'iPhone SE',
    aliases: ['iphone se', 'iphonese', 'se iphone', 'se2', 'se3'],
    tags: ['phones', 'iphone'],
  ),

  // Samsung Galaxy (common series)
  MaSearchEntry(
    ar: 'سامسونج S25 ألترا',
    fr: 'Galaxy S25 Ultra',
    en: 'Galaxy S25 Ultra',
    aliases: ['s25 ultra', 'galaxy s25 ultra'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج S25',
    fr: 'Galaxy S25',
    en: 'Galaxy S25',
    aliases: ['s25', 'galaxy s25'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج S25 بلس',
    fr: 'Galaxy S25+',
    en: 'Galaxy S25+',
    aliases: ['s25+', 'galaxy s25+', 's25 plus'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج S24 ألترا',
    fr: 'Galaxy S24 Ultra',
    en: 'Galaxy S24 Ultra',
    aliases: ['s24 ultra', 'galaxy s24 ultra'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج S24',
    fr: 'Galaxy S24',
    en: 'Galaxy S24',
    aliases: ['s24', 'galaxy s24'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج S23 ألترا',
    fr: 'Galaxy S23 Ultra',
    en: 'Galaxy S23 Ultra',
    aliases: ['s23 ultra', 'galaxy s23 ultra'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج S23',
    fr: 'Galaxy S23',
    en: 'Galaxy S23',
    aliases: ['s23', 'galaxy s23'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج S22',
    fr: 'Galaxy S22',
    en: 'Galaxy S22',
    aliases: ['s22', 'galaxy s22'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج S21',
    fr: 'Galaxy S21',
    en: 'Galaxy S21',
    aliases: ['s21', 'galaxy s21'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج نوت 20 ألترا',
    fr: 'Galaxy Note 20 Ultra',
    en: 'Galaxy Note 20 Ultra',
    aliases: ['note 20 ultra', 'galaxy note 20 ultra'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج نوت 10 بلس',
    fr: 'Galaxy Note 10+',
    en: 'Galaxy Note 10+',
    aliases: ['note 10+', 'note10+', 'galaxy note 10+'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج زد فليب',
    fr: 'Galaxy Z Flip',
    en: 'Galaxy Z Flip',
    aliases: ['z flip', 'galaxy z flip', 'flip'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج زد فولد',
    fr: 'Galaxy Z Fold',
    en: 'Galaxy Z Fold',
    aliases: ['z fold', 'galaxy z fold', 'fold'],
    tags: ['phones', 'samsung'],
  ),

  // Samsung A-series (very common in Mauritania)
  MaSearchEntry(
    ar: 'سامسونج A15',
    fr: 'Galaxy A15',
    en: 'Galaxy A15',
    aliases: ['a15', 'galaxy a15'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج A14',
    fr: 'Galaxy A14',
    en: 'Galaxy A14',
    aliases: ['a14', 'galaxy a14'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج A13',
    fr: 'Galaxy A13',
    en: 'Galaxy A13',
    aliases: ['a13', 'galaxy a13'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج A12',
    fr: 'Galaxy A12',
    en: 'Galaxy A12',
    aliases: ['a12', 'galaxy a12'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج A11',
    fr: 'Galaxy A11',
    en: 'Galaxy A11',
    aliases: ['a11', 'galaxy a11'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج A10',
    fr: 'Galaxy A10',
    en: 'Galaxy A10',
    aliases: ['a10', 'galaxy a10'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج A24',
    fr: 'Galaxy A24',
    en: 'Galaxy A24',
    aliases: ['a24', 'galaxy a24'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج A34',
    fr: 'Galaxy A34',
    en: 'Galaxy A34',
    aliases: ['a34', 'galaxy a34'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج A54',
    fr: 'Galaxy A54',
    en: 'Galaxy A54',
    aliases: ['a54', 'galaxy a54'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج A55',
    fr: 'Galaxy A55',
    en: 'Galaxy A55',
    aliases: ['a55', 'galaxy a55'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج A53',
    fr: 'Galaxy A53',
    en: 'Galaxy A53',
    aliases: ['a53', 'galaxy a53'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج A52',
    fr: 'Galaxy A52',
    en: 'Galaxy A52',
    aliases: ['a52', 'galaxy a52'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج A51',
    fr: 'Galaxy A51',
    en: 'Galaxy A51',
    aliases: ['a51', 'galaxy a51'],
    tags: ['phones', 'samsung'],
  ),
  MaSearchEntry(
    ar: 'سامسونج A50',
    fr: 'Galaxy A50',
    en: 'Galaxy A50',
    aliases: ['a50', 'galaxy a50'],
    tags: ['phones', 'samsung'],
  ),

  // Places (Nouakchott & Nouadhibou municipalities)
  MaSearchEntry(
    ar: 'تفرغ زينه',
    fr: 'Tevragh-Zeina',
    en: 'Tevragh-Zeina',
    aliases: ['tevragh zeina', 'tvragh zeina'],
    tags: ['place'],
  ),
  MaSearchEntry(
    ar: 'لكصر',
    fr: 'Ksar',
    en: 'Ksar',
    aliases: ['ksar'],
    tags: ['place'],
  ),
  MaSearchEntry(
    ar: 'السبخة',
    fr: 'Sebkha',
    en: 'Sebkha',
    aliases: ['sebkha'],
    tags: ['place'],
  ),
  MaSearchEntry(
    ar: 'عرفات',
    fr: 'Arafat',
    en: 'Arafat',
    aliases: ['arafat'],
    tags: ['place'],
  ),
  MaSearchEntry(
    ar: 'الرياض',
    fr: 'Riyad',
    en: 'Riyad',
    aliases: ['riyad', 'riadh'],
    tags: ['place'],
  ),
  MaSearchEntry(
    ar: 'نواذيبو',
    fr: 'Nouadhibou',
    en: 'Nouadhibou',
    aliases: ['nwadhibou', 'nouadhibou'],
    tags: ['place'],
  ),
  MaSearchEntry(
    ar: 'بولنوار',
    fr: 'Boulenouar',
    en: 'Boulenouar',
    aliases: ['boulenouar', 'boulenoir'],
    tags: ['place'],
  ),
  MaSearchEntry(
    ar: 'إنال',
    fr: 'Inal',
    en: 'Inal',
    aliases: ['inal'],
    tags: ['place'],
  ),
  MaSearchEntry(
    ar: 'نوامغار',
    fr: 'Nouamghar',
    en: 'Nouamghar',
    aliases: ['nouamghar', 'nouamghar'],
    tags: ['place'],
  ),
  MaSearchEntry(
    ar: 'اتميمشات',
    fr: 'Tmeimichatt',
    en: 'Tmeimichatt',
    aliases: ['tmeimichatt', 'tmeimichat'],
    tags: ['place'],
  ),

  // Internet / tech
  MaSearchEntry(
    ar: 'ستارلينك',
    fr: 'Starlink',
    en: 'Starlink',
    aliases: ['star link', 'starlink', 'ستار لنك'],
    tags: ['internet'],
  ),
  MaSearchEntry(
    ar: 'واي فاي',
    fr: 'Wi‑Fi',
    en: 'Wi‑Fi',
    aliases: ['wifi', 'wi fi', 'وايفاي', 'ويفي'],
    tags: ['internet'],
  ),
  MaSearchEntry(
    ar: 'راوتر',
    fr: 'Routeur',
    en: 'Router',
    aliases: ['router', 'routeur', 'مودم', 'modem'],
    tags: ['internet'],
  ),
  MaSearchEntry(
    ar: 'لابتوب',
    fr: 'Ordinateur portable',
    en: 'Laptop',
    aliases: ['pc', 'ordinateur', 'laptop', 'لاب توب'],
    tags: ['computers'],
  ),

  // Cars
  MaSearchEntry(
    ar: 'تويوتا',
    fr: 'Toyota',
    en: 'Toyota',
    aliases: ['toyota', 'طيوطا', 'تويوتا'],
    tags: ['cars'],
  ),
  MaSearchEntry(
    ar: 'هايلكس',
    fr: 'Hilux',
    en: 'Hilux',
    aliases: ['hilux', 'hylux', 'هايلوكس'],
    tags: ['cars'],
  ),
  MaSearchEntry(
    ar: 'برادو',
    fr: 'Prado',
    en: 'Prado',
    aliases: ['prado', 'برادو'],
    tags: ['cars'],
  ),
  MaSearchEntry(
    ar: 'مرسيدس',
    fr: 'Mercedes',
    en: 'Mercedes',
    aliases: ['mercedes', 'مرسيدس', 'benz'],
    tags: ['cars'],
  ),

  // Real estate
  MaSearchEntry(
    ar: 'كراء',
    fr: 'Location',
    en: 'Rent',
    aliases: ['إيجار', 'ايجار', 'location', 'rent'],
    tags: ['real_estate'],
  ),
  MaSearchEntry(
    ar: 'بيع',
    fr: 'Vente',
    en: 'Sale',
    aliases: ['vente', 'sell', 'شراء', 'achats'],
    tags: ['real_estate'],
  ),
  MaSearchEntry(
    ar: 'قطعة أرض',
    fr: 'Terrain',
    en: 'Land',
    aliases: ['ارض', 'أرض', 'terrain', 'land', 'plot'],
    tags: ['real_estate'],
  ),
  MaSearchEntry(
    ar: 'شقة',
    fr: 'Appartement',
    en: 'Apartment',
    aliases: ['appartement', 'apartment', 'شقه'],
    tags: ['real_estate'],
  ),

  // Services
  MaSearchEntry(
    ar: 'توصيل',
    fr: 'Livraison',
    en: 'Delivery',
    aliases: ['delivery', 'livraison', 'توصيل طلبات'],
    tags: ['services'],
  ),
  MaSearchEntry(
    ar: 'نقل',
    fr: 'Transport',
    en: 'Transport',
    aliases: ['transport', 'move', 'ترحيل'],
    tags: ['services'],
  ),
  MaSearchEntry(
    ar: 'كهربائي',
    fr: 'Électricien',
    en: 'Electrician',
    aliases: ['electricien', 'electrician', 'كهرباء'],
    tags: ['services'],
  ),
  MaSearchEntry(
    ar: 'سبّاك',
    fr: 'Plombier',
    en: 'Plumber',
    aliases: ['plombier', 'plumber', 'سباك', 'plomberie'],
    tags: ['services'],
  ),
  MaSearchEntry(
    ar: 'تنظيف',
    fr: 'Nettoyage',
    en: 'Cleaning',
    aliases: ['cleaning', 'nettoyage', 'نظافة'],
    tags: ['services'],
  ),

  // Jobs / Wanted
  MaSearchEntry(
    ar: 'وظائف',
    fr: 'Emplois',
    en: 'Jobs',
    aliases: ['job', 'jobs', 'emploi', 'travail', 'عمل'],
    tags: ['jobs'],
  ),
  MaSearchEntry(
    ar: 'مطلوب',
    fr: 'Recherché',
    en: 'Wanted',
    aliases: ['wanted', 'recherche', 'أبحث عن', 'ابحث عن'],
    tags: ['wanted'],
  ),
];

String maNormalizeQuery(String input) {
  var s = input.trim().toLowerCase();
  if (s.isEmpty) return s;

  // Arabic diacritics
  s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '');

  // Arabic letter normalization
  s = s
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه');

  // French / Latin diacritics (keep search forgiving)
  // Note: this is a tiny subset that covers most real-world inputs.
  s = s
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('á', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('å', 'a')
      .replaceAll('ç', 'c')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ì', 'i')
      .replaceAll('î', 'i')
      .replaceAll('ï', 'i')
      .replaceAll('ñ', 'n')
      .replaceAll('ó', 'o')
      .replaceAll('ò', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ù', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ý', 'y')
      .replaceAll('ÿ', 'y')
      .replaceAll('œ', 'oe')
      .replaceAll('æ', 'ae');

  // Remove punctuation-like chars
  s = s.replaceAll(RegExp(r"[’'`´]"), '');
  // Keep ALL letters/numbers (including accents), strip the rest.
  s = s.replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', unicode: true), ' ');

  // Separate letter-number boundaries (e.g. iphone13 -> iphone 13)
  s = s.replaceAllMapped(
    RegExp(r'([\p{L}])([0-9])', unicode: true),
    (m) => '${m[1]} ${m[2]}',
  );
  s = s.replaceAllMapped(
    RegExp(r'([0-9])([\p{L}])', unicode: true),
    (m) => '${m[1]} ${m[2]}',
  );
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

List<String> maSuggestFromDictionary(
  String query,
  Locale locale, {
  int limit = 8,
}) {
  final q = maNormalizeQuery(query);
  if (q.isEmpty) return const [];
  final out = <String>[];
  final seen = <String>{};

  void add(String s) {
    final key = maNormalizeQuery(s);
    if (key.isEmpty || seen.contains(key)) return;
    seen.add(key);
    out.add(s);
  }

  // Prefer startsWith, then contains
  final starts = <String>[];
  final contains = <String>[];

  for (final e in maSearchDictionary) {
    final label = e.labelOf(locale);
    for (final t in e.allTerms(locale)) {
      final n = maNormalizeQuery(t);
      if (n.startsWith(q)) {
        starts.add(label);
        break;
      }
    }
  }

  for (final e in maSearchDictionary) {
    final label = e.labelOf(locale);
    for (final t in e.allTerms(locale)) {
      final n = maNormalizeQuery(t);
      if (n.contains(q)) {
        contains.add(label);
        break;
      }
    }
  }

  for (final s in starts) {
    add(s);
    if (out.length >= limit) return out;
  }
  for (final s in contains) {
    add(s);
    if (out.length >= limit) return out;
  }

  return out;
}

List<String> maQuickSearchChips(Locale locale, {int limit = 12}) {
  // A curated set that feels like Mauritania market "shortcuts".
  final picks = <String>[
    for (final e in maSearchDictionary.take(12)) e.labelOf(locale),
  ];
  return picks.take(limit).toList(growable: false);
}

/// A tappable "hot search" chip (label is localized, query is what we send to /search?q=...)
class MaQuickChip {
  final String label;

  /// Optional free-text query (used when chip is not mapped to a category).
  final String query;

  /// Optional stable category filter ids (recommended for "hot" chips like Cars/Phones).
  final String? categoryId;
  final String? subCategoryId;
  const MaQuickChip(
    this.label,
    this.query, {
    this.categoryId,
    this.subCategoryId,
  });
}

/// Hot / high-demand chips for the Mauritanian market.
/// These are curated defaults (no backend needed yet).
/// Later we can replace this by Firestore "top searches" per wilaya / time window.
List<MaQuickChip> maHotSearchChips(Locale locale, {int limit = 10}) {
  final code = locale.languageCode.toLowerCase();

  const ar = <MaQuickChip>[
    MaQuickChip('ملحفة', 'ملحفة',
        categoryId: 'fashion', subCategoryId: 'melhafa'),
    MaQuickChip('دراعة', 'دراعة',
        categoryId: 'fashion', subCategoryId: 'daraa'),
    MaQuickChip('هواتف', 'هواتف',
        categoryId: 'electronics', subCategoryId: 'phones'),
    MaQuickChip('سيارات للبيع', 'سيارات للبيع',
        categoryId: 'vehicles', subCategoryId: 'cars'),
    MaQuickChip('كراء شقة', 'كراء شقة',
        categoryId: 'real_estate', subCategoryId: 'rent'),
    MaQuickChip('عطور', 'عطور',
        categoryId: 'fashion', subCategoryId: 'perfume'),
    MaQuickChip('قطع غيار', 'قطع غيار',
        categoryId: 'vehicles', subCategoryId: 'parts'),
    MaQuickChip('أراضي', 'أراضي',
        categoryId: 'real_estate', subCategoryId: 'land'),
    MaQuickChip('أثاث', 'أثاث', categoryId: 'home', subCategoryId: 'furniture'),
    MaQuickChip('خدمات', 'خدمات', categoryId: 'services'),
  ];

  const fr = <MaQuickChip>[
    MaQuickChip('Mlehfa', 'mlehfa',
        categoryId: 'fashion', subCategoryId: 'melhafa'),
    MaQuickChip('Daraa', 'daraa',
        categoryId: 'fashion', subCategoryId: 'daraa'),
    MaQuickChip('Téléphones', 'telephone',
        categoryId: 'electronics', subCategoryId: 'phones'),
    MaQuickChip('Voitures', 'voiture',
        categoryId: 'vehicles', subCategoryId: 'cars'),
    MaQuickChip('Location appart', 'location appartement',
        categoryId: 'real_estate', subCategoryId: 'rent'),
    MaQuickChip('Parfums', 'parfum',
        categoryId: 'fashion', subCategoryId: 'perfume'),
    MaQuickChip('Pièces auto', 'pieces auto',
        categoryId: 'vehicles', subCategoryId: 'parts'),
    MaQuickChip('Terrains', 'terrain',
        categoryId: 'real_estate', subCategoryId: 'land'),
    MaQuickChip('Meubles', 'meubles',
        categoryId: 'home', subCategoryId: 'furniture'),
    MaQuickChip('Services', 'services', categoryId: 'services'),
  ];

  const en = <MaQuickChip>[
    MaQuickChip('Mlehfa', 'mlehfa',
        categoryId: 'fashion', subCategoryId: 'melhafa'),
    MaQuickChip('Daraa', 'daraa',
        categoryId: 'fashion', subCategoryId: 'daraa'),
    MaQuickChip('Phones', 'phones',
        categoryId: 'electronics', subCategoryId: 'phones'),
    MaQuickChip('Cars', 'cars', categoryId: 'vehicles', subCategoryId: 'cars'),
    MaQuickChip('Apartment rent', 'apartment rent',
        categoryId: 'real_estate', subCategoryId: 'rent'),
    MaQuickChip('Perfume', 'perfume',
        categoryId: 'fashion', subCategoryId: 'perfume'),
    MaQuickChip('Car parts', 'car parts',
        categoryId: 'vehicles', subCategoryId: 'parts'),
    MaQuickChip('Land', 'land',
        categoryId: 'real_estate', subCategoryId: 'land'),
    MaQuickChip('Furniture', 'furniture',
        categoryId: 'home', subCategoryId: 'furniture'),
    MaQuickChip('Services', 'services', categoryId: 'services'),
  ];

  final list = (code == 'ar')
      ? ar
      : (code == 'fr')
          ? fr
          : en;

  return list.take(limit).toList(growable: false);
}
