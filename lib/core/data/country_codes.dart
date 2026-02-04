import 'package:flutter/material.dart';

@immutable
class CountryCode {
  final String iso2; // e.g. 'MR'
  final String dialCode; // e.g. '+222'
  final String nameAr;
  final String nameFr;
  final String nameEn;

  const CountryCode({
    required this.iso2,
    required this.dialCode,
    required this.nameAr,
    required this.nameFr,
    required this.nameEn,
  });

  String nameFor(Locale locale) {
    final code = locale.languageCode.toLowerCase();
    if (code == 'fr') return nameFr;
    if (code == 'en') return nameEn;
    return nameAr;
  }

  String get flagEmoji {
    final code = iso2.toUpperCase();
    if (code.length != 2) return '🏳️';
    final first = code.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = code.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCodes([first, second]);
  }
}

/// Europe + some popular countries (Temu-like picker).
///
/// You can add more later if you wish.
const List<CountryCode> kCountryCodes = [
  // Most-used / Target
  CountryCode(
      iso2: 'MR',
      dialCode: '+222',
      nameAr: 'موريتانيا',
      nameFr: 'Mauritanie',
      nameEn: 'Mauritania'),

  // Europe (mostly sovereign states)
  CountryCode(
      iso2: 'FR',
      dialCode: '+33',
      nameAr: 'فرنسا',
      nameFr: 'France',
      nameEn: 'France'),
  CountryCode(
      iso2: 'ES',
      dialCode: '+34',
      nameAr: 'إسبانيا',
      nameFr: 'Espagne',
      nameEn: 'Spain'),
  CountryCode(
      iso2: 'DE',
      dialCode: '+49',
      nameAr: 'ألمانيا',
      nameFr: 'Allemagne',
      nameEn: 'Germany'),
  CountryCode(
      iso2: 'NL',
      dialCode: '+31',
      nameAr: 'هولندا',
      nameFr: 'Pays-Bas',
      nameEn: 'Netherlands'),
  CountryCode(
      iso2: 'BE',
      dialCode: '+32',
      nameAr: 'بلجيكا',
      nameFr: 'Belgique',
      nameEn: 'Belgium'),
  CountryCode(
      iso2: 'IT',
      dialCode: '+39',
      nameAr: 'إيطاليا',
      nameFr: 'Italie',
      nameEn: 'Italy'),
  CountryCode(
      iso2: 'GB',
      dialCode: '+44',
      nameAr: 'المملكة المتحدة',
      nameFr: 'Royaume-Uni',
      nameEn: 'United Kingdom'),
  CountryCode(
      iso2: 'PT',
      dialCode: '+351',
      nameAr: 'البرتغال',
      nameFr: 'Portugal',
      nameEn: 'Portugal'),
  CountryCode(
      iso2: 'IE',
      dialCode: '+353',
      nameAr: 'أيرلندا',
      nameFr: 'Irlande',
      nameEn: 'Ireland'),
  CountryCode(
      iso2: 'CH',
      dialCode: '+41',
      nameAr: 'سويسرا',
      nameFr: 'Suisse',
      nameEn: 'Switzerland'),
  CountryCode(
      iso2: 'AT',
      dialCode: '+43',
      nameAr: 'النمسا',
      nameFr: 'Autriche',
      nameEn: 'Austria'),
  CountryCode(
      iso2: 'DK',
      dialCode: '+45',
      nameAr: 'الدنمارك',
      nameFr: 'Danemark',
      nameEn: 'Denmark'),
  CountryCode(
      iso2: 'SE',
      dialCode: '+46',
      nameAr: 'السويد',
      nameFr: 'Suède',
      nameEn: 'Sweden'),
  CountryCode(
      iso2: 'NO',
      dialCode: '+47',
      nameAr: 'النرويج',
      nameFr: 'Norvège',
      nameEn: 'Norway'),
  CountryCode(
      iso2: 'PL',
      dialCode: '+48',
      nameAr: 'بولندا',
      nameFr: 'Pologne',
      nameEn: 'Poland'),
  CountryCode(
      iso2: 'FI',
      dialCode: '+358',
      nameAr: 'فنلندا',
      nameFr: 'Finlande',
      nameEn: 'Finland'),
  CountryCode(
      iso2: 'IS',
      dialCode: '+354',
      nameAr: 'آيسلندا',
      nameFr: 'Islande',
      nameEn: 'Iceland'),
  CountryCode(
      iso2: 'LU',
      dialCode: '+352',
      nameAr: 'لوكسمبورغ',
      nameFr: 'Luxembourg',
      nameEn: 'Luxembourg'),
  CountryCode(
      iso2: 'LI',
      dialCode: '+423',
      nameAr: 'ليختنشتاين',
      nameFr: 'Liechtenstein',
      nameEn: 'Liechtenstein'),
  CountryCode(
      iso2: 'MC',
      dialCode: '+377',
      nameAr: 'موناكو',
      nameFr: 'Monaco',
      nameEn: 'Monaco'),
  CountryCode(
      iso2: 'AD',
      dialCode: '+376',
      nameAr: 'أندورا',
      nameFr: 'Andorre',
      nameEn: 'Andorra'),
  CountryCode(
      iso2: 'SM',
      dialCode: '+378',
      nameAr: 'سان مارينو',
      nameFr: 'Saint-Marin',
      nameEn: 'San Marino'),
  CountryCode(
      iso2: 'VA',
      dialCode: '+39',
      nameAr: 'الفاتيكان',
      nameFr: 'Vatican',
      nameEn: 'Vatican City'),
  CountryCode(
      iso2: 'MT',
      dialCode: '+356',
      nameAr: 'مالطا',
      nameFr: 'Malte',
      nameEn: 'Malta'),
  CountryCode(
      iso2: 'CY',
      dialCode: '+357',
      nameAr: 'قبرص',
      nameFr: 'Chypre',
      nameEn: 'Cyprus'),
  CountryCode(
      iso2: 'EE',
      dialCode: '+372',
      nameAr: 'إستونيا',
      nameFr: 'Estonie',
      nameEn: 'Estonia'),
  CountryCode(
      iso2: 'LV',
      dialCode: '+371',
      nameAr: 'لاتفيا',
      nameFr: 'Lettonie',
      nameEn: 'Latvia'),
  CountryCode(
      iso2: 'LT',
      dialCode: '+370',
      nameAr: 'ليتوانيا',
      nameFr: 'Lituanie',
      nameEn: 'Lithuania'),
  CountryCode(
      iso2: 'CZ',
      dialCode: '+420',
      nameAr: 'التشيك',
      nameFr: 'Tchéquie',
      nameEn: 'Czechia'),
  CountryCode(
      iso2: 'SK',
      dialCode: '+421',
      nameAr: 'سلوفاكيا',
      nameFr: 'Slovaquie',
      nameEn: 'Slovakia'),
  CountryCode(
      iso2: 'HU',
      dialCode: '+36',
      nameAr: 'المجر',
      nameFr: 'Hongrie',
      nameEn: 'Hungary'),
  CountryCode(
      iso2: 'RO',
      dialCode: '+40',
      nameAr: 'رومانيا',
      nameFr: 'Roumanie',
      nameEn: 'Romania'),
  CountryCode(
      iso2: 'BG',
      dialCode: '+359',
      nameAr: 'بلغاريا',
      nameFr: 'Bulgarie',
      nameEn: 'Bulgaria'),
  CountryCode(
      iso2: 'GR',
      dialCode: '+30',
      nameAr: 'اليونان',
      nameFr: 'Grèce',
      nameEn: 'Greece'),
  CountryCode(
      iso2: 'SI',
      dialCode: '+386',
      nameAr: 'سلوفينيا',
      nameFr: 'Slovénie',
      nameEn: 'Slovenia'),
  CountryCode(
      iso2: 'HR',
      dialCode: '+385',
      nameAr: 'كرواتيا',
      nameFr: 'Croatie',
      nameEn: 'Croatia'),
  CountryCode(
      iso2: 'BA',
      dialCode: '+387',
      nameAr: 'البوسنة والهرسك',
      nameFr: 'Bosnie-Herzégovine',
      nameEn: 'Bosnia & Herzegovina'),
  CountryCode(
      iso2: 'RS',
      dialCode: '+381',
      nameAr: 'صربيا',
      nameFr: 'Serbie',
      nameEn: 'Serbia'),
  CountryCode(
      iso2: 'ME',
      dialCode: '+382',
      nameAr: 'الجبل الأسود',
      nameFr: 'Monténégro',
      nameEn: 'Montenegro'),
  CountryCode(
      iso2: 'MK',
      dialCode: '+389',
      nameAr: 'مقدونيا الشمالية',
      nameFr: 'Macédoine du Nord',
      nameEn: 'North Macedonia'),
  CountryCode(
      iso2: 'AL',
      dialCode: '+355',
      nameAr: 'ألبانيا',
      nameFr: 'Albanie',
      nameEn: 'Albania'),
  CountryCode(
      iso2: 'XK',
      dialCode: '+383',
      nameAr: 'كوسوفو',
      nameFr: 'Kosovo',
      nameEn: 'Kosovo'),
  CountryCode(
      iso2: 'MD',
      dialCode: '+373',
      nameAr: 'مولدوفا',
      nameFr: 'Moldavie',
      nameEn: 'Moldova'),
  CountryCode(
      iso2: 'UA',
      dialCode: '+380',
      nameAr: 'أوكرانيا',
      nameFr: 'Ukraine',
      nameEn: 'Ukraine'),
  CountryCode(
      iso2: 'BY',
      dialCode: '+375',
      nameAr: 'بيلاروس',
      nameFr: 'Biélorussie',
      nameEn: 'Belarus'),
  CountryCode(
      iso2: 'RU',
      dialCode: '+7',
      nameAr: 'روسيا',
      nameFr: 'Russie',
      nameEn: 'Russia'),
  CountryCode(
      iso2: 'TR',
      dialCode: '+90',
      nameAr: 'تركيا',
      nameFr: 'Turquie',
      nameEn: 'Turkey'),
  CountryCode(
      iso2: 'AM',
      dialCode: '+374',
      nameAr: 'أرمينيا',
      nameFr: 'Arménie',
      nameEn: 'Armenia'),
  CountryCode(
      iso2: 'AZ',
      dialCode: '+994',
      nameAr: 'أذربيجان',
      nameFr: 'Azerbaïdjan',
      nameEn: 'Azerbaijan'),
  CountryCode(
      iso2: 'GE',
      dialCode: '+995',
      nameAr: 'جورجيا',
      nameFr: 'Géorgie',
      nameEn: 'Georgia'),

  // Nearby / Famous
  CountryCode(
      iso2: 'MA',
      dialCode: '+212',
      nameAr: 'المغرب',
      nameFr: 'Maroc',
      nameEn: 'Morocco'),
  CountryCode(
      iso2: 'DZ',
      dialCode: '+213',
      nameAr: 'الجزائر',
      nameFr: 'Algérie',
      nameEn: 'Algeria'),
  CountryCode(
      iso2: 'TN',
      dialCode: '+216',
      nameAr: 'تونس',
      nameFr: 'Tunisie',
      nameEn: 'Tunisia'),
  CountryCode(
      iso2: 'SN',
      dialCode: '+221',
      nameAr: 'السنغال',
      nameFr: 'Sénégal',
      nameEn: 'Senegal'),
  CountryCode(
      iso2: 'ML',
      dialCode: '+223',
      nameAr: 'مالي',
      nameFr: 'Mali',
      nameEn: 'Mali'),
  CountryCode(
      iso2: 'CI',
      dialCode: '+225',
      nameAr: 'ساحل العاج',
      nameFr: "Côte d’Ivoire",
      nameEn: "Côte d’Ivoire"),
  CountryCode(
      iso2: 'EG',
      dialCode: '+20',
      nameAr: 'مصر',
      nameFr: 'Égypte',
      nameEn: 'Egypt'),

  CountryCode(
      iso2: 'US',
      dialCode: '+1',
      nameAr: 'الولايات المتحدة',
      nameFr: 'États-Unis',
      nameEn: 'United States'),
  CountryCode(
      iso2: 'CA',
      dialCode: '+1',
      nameAr: 'كندا',
      nameFr: 'Canada',
      nameEn: 'Canada'),
  CountryCode(
      iso2: 'AE',
      dialCode: '+971',
      nameAr: 'الإمارات',
      nameFr: 'Émirats arabes unis',
      nameEn: 'United Arab Emirates'),
  CountryCode(
      iso2: 'SA',
      dialCode: '+966',
      nameAr: 'السعودية',
      nameFr: 'Arabie saoudite',
      nameEn: 'Saudi Arabia'),
  CountryCode(
      iso2: 'QA',
      dialCode: '+974',
      nameAr: 'قطر',
      nameFr: 'Qatar',
      nameEn: 'Qatar'),
  CountryCode(
      iso2: 'KW',
      dialCode: '+965',
      nameAr: 'الكويت',
      nameFr: 'Koweït',
      nameEn: 'Kuwait'),
  CountryCode(
      iso2: 'OM',
      dialCode: '+968',
      nameAr: 'عُمان',
      nameFr: 'Oman',
      nameEn: 'Oman'),

  CountryCode(
      iso2: 'IN',
      dialCode: '+91',
      nameAr: 'الهند',
      nameFr: 'Inde',
      nameEn: 'India'),
  CountryCode(
      iso2: 'PK',
      dialCode: '+92',
      nameAr: 'باكستان',
      nameFr: 'Pakistan',
      nameEn: 'Pakistan'),
  CountryCode(
      iso2: 'CN',
      dialCode: '+86',
      nameAr: 'الصين',
      nameFr: 'Chine',
      nameEn: 'China'),
  CountryCode(
      iso2: 'BR',
      dialCode: '+55',
      nameAr: 'البرازيل',
      nameFr: 'Brésil',
      nameEn: 'Brazil'),
  CountryCode(
      iso2: 'AU',
      dialCode: '+61',
      nameAr: 'أستراليا',
      nameFr: 'Australie',
      nameEn: 'Australia'),
];
