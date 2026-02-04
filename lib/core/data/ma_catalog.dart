import 'package:flutter/widgets.dart';

@immutable
class L10n3 {
  const L10n3({required this.ar, required this.fr, required this.en});
  final String ar;
  final String fr;
  final String en;

  String ofLocale(Locale locale) {
    final code = locale.languageCode.toLowerCase();
    if (code == 'ar') return ar;
    if (code == 'fr') return fr;
    if (code == 'en') return en;
    // App supports AR/FR/EN only; fallback to Arabic.
    return ar;
  }

  String of(BuildContext context) => ofLocale(Localizations.localeOf(context));
}

@immutable
class Moughataa {
  const Moughataa({required this.id, required this.name});
  final String id;
  final L10n3 name;
}

@immutable
class Wilaya {
  const Wilaya(
      {required this.id, required this.name, required this.moughataas});
  final String id;
  final L10n3 name;
  final List<Moughataa> moughataas;

  /// Pads to exactly 4 items for fixed UI layouts.
  List<Moughataa> get moughataas4 {
    if (moughataas.length >= 4)
      return moughataas.take(4).toList(growable: false);
    final out = [...moughataas];
    while (out.length < 4) {
      out.add(const Moughataa(
          id: '__na__', name: L10n3(ar: '—', fr: '—', en: '—')));
    }
    return out;
  }
}

@immutable
class SubCategory {
  const SubCategory({required this.id, required this.name});
  final String id;
  final L10n3 name;
}

// ---------------------------------------------------------------------------
// "Other" (uncategorized) subcategory
// ---------------------------------------------------------------------------

/// Stable id used for the uncategorized subcategory.
const String kOtherSubcategoryId = 'other';

/// Display label for uncategorized subcategory (AR/FR/EN).
const SubCategory kOtherSubcategory = SubCategory(
  id: kOtherSubcategoryId,
  name: L10n3(ar: 'أخرى', fr: 'Autre', en: 'Other'),
);

/// Adds the "Other" subcategory at the end (if not already present).
List<SubCategory> withOtherSubcategory(List<SubCategory> subs) {
  if (subs.isEmpty) return const <SubCategory>[kOtherSubcategory];
  if (subs.any((s) => s.id == kOtherSubcategoryId)) return subs;
  return <SubCategory>[...subs, kOtherSubcategory];
}

/// Backward-compatible alias (older patches used this name).
List<SubCategory> maWithOtherSubCategory(List<SubCategory> subs) =>
    withOtherSubcategory(subs);

/// Robust resolver: maps stored values (id OR localized label) to a stable id.
String? resolveCategoryIdAny(String? any) {
  final v = (any ?? '').trim();
  if (v.isEmpty) return null;
  final vl = v.toLowerCase();
  for (final c in maCategories) {
    if (c.id.toLowerCase() == vl) return c.id;
    if (c.name.ar.toLowerCase() == vl ||
        c.name.fr.toLowerCase() == vl ||
        c.name.en.toLowerCase() == vl) return c.id;
  }
  return v;
}

String? resolveSubCategoryIdAny(String? any) {
  final v = (any ?? '').trim();
  if (v.isEmpty) return null;
  final vl = v.toLowerCase();
  if (vl == kOtherSubcategoryId) return kOtherSubcategoryId;
  for (final c in maCategories) {
    for (final s in withOtherSubcategory(c.sub)) {
      if (s.id.toLowerCase() == vl) return s.id;
      if (s.name.ar.toLowerCase() == vl ||
          s.name.fr.toLowerCase() == vl ||
          s.name.en.toLowerCase() == vl) return s.id;
    }
  }
  return v;
}

/// True when the value is empty/unknown OR explicitly "other".
bool isOtherSubcategoryValue(String? any) {
  final id = resolveSubCategoryIdAny(any);
  return id == null || id.trim().isEmpty || id == kOtherSubcategoryId;
}

@immutable
class CategoryNode {
  const CategoryNode(
      {required this.id, required this.name, this.sub = const <SubCategory>[]});
  final String id;
  final L10n3 name;
  final List<SubCategory> sub;

  /// Backwards-compatible alias used by some screens.
  ///
  /// Older code referenced `subCategories` instead of `sub`.
  List<SubCategory> get subCategories => sub;
}

@immutable
class ServiceTag {
  const ServiceTag({required this.id, required this.name});
  final String id;
  final L10n3 name;
}

// ---------------------------------------------------------------------------
// Categories (Market + Services)
// ---------------------------------------------------------------------------

const maCategories = <CategoryNode>[
  CategoryNode(
    id: 'vehicles',
    name: L10n3(ar: 'المركبات', fr: 'Véhicules', en: 'Vehicles'),
    sub: [
      SubCategory(
          id: 'cars', name: L10n3(ar: 'سيارات', fr: 'Voitures', en: 'Cars')),
      SubCategory(id: 'suv4x4', name: L10n3(ar: '4x4', fr: '4x4', en: '4x4')),
      SubCategory(
        id: 'trucks',
        name: L10n3(ar: 'شاحنات/حافلات', fr: 'Camions/Bus', en: 'Trucks/Bus'),
      ),
      SubCategory(
          id: 'motorcycles',
          name: L10n3(ar: 'دراجات نارية', fr: 'Motos', en: 'Motorcycles')),
      SubCategory(
          id: 'bicycles',
          name: L10n3(ar: 'دراجات', fr: 'Vélos', en: 'Bicycles')),
      SubCategory(
          id: 'parts', name: L10n3(ar: 'قطع غيار', fr: 'Pièces', en: 'Parts')),
    ],
  ),
  CategoryNode(
    id: 'real_estate',
    name: L10n3(ar: 'العقارات', fr: 'Immobilier', en: 'Real Estate'),
    sub: [
      SubCategory(
          id: 'land', name: L10n3(ar: 'أراضي', fr: 'Terrains', en: 'Land')),
      SubCategory(
          id: 'house', name: L10n3(ar: 'منازل', fr: 'Maisons', en: 'Houses')),
      SubCategory(
          id: 'apartment',
          name: L10n3(ar: 'شقق', fr: 'Appartements', en: 'Apartments')),
      SubCategory(
          id: 'rent', name: L10n3(ar: 'كراء', fr: 'Location', en: 'Rent')),
      SubCategory(
        id: 'shops',
        name: L10n3(
            ar: 'محلات/مكاتب', fr: 'Boutiques/Bureaux', en: 'Shops/Offices'),
      ),
    ],
  ),
  CategoryNode(
    id: 'electronics',
    name: L10n3(ar: 'الإلكترونيات', fr: 'Électronique', en: 'Electronics'),
    sub: [
      SubCategory(
          id: 'phones',
          name: L10n3(ar: 'هواتف', fr: 'Téléphones', en: 'Phones')),
      SubCategory(
          id: 'computers',
          name: L10n3(ar: 'كمبيوترات', fr: 'Ordinateurs', en: 'Computers')),
      SubCategory(
          id: 'tablets',
          name: L10n3(ar: 'ألواح/تابلت', fr: 'Tablettes', en: 'Tablets')),
      SubCategory(
          id: 'tv_audio',
          name: L10n3(ar: 'TV/صوتيات', fr: 'TV/Audio', en: 'TV/Audio')),
      SubCategory(
          id: 'gaming', name: L10n3(ar: 'ألعاب', fr: 'Gaming', en: 'Gaming')),
      SubCategory(
          id: 'cameras',
          name: L10n3(ar: 'كاميرات', fr: 'Caméras', en: 'Cameras')),
      SubCategory(
        id: 'wearables',
        name: L10n3(ar: 'ساعات/أساور ذكية', fr: 'Wearables', en: 'Wearables'),
      ),
      SubCategory(
        id: 'smart_home',
        name: L10n3(ar: 'منزل ذكي', fr: 'Maison connectée', en: 'Smart home'),
      ),
      SubCategory(
        id: 'printers',
        name: L10n3(
            ar: 'طابعات/سكانر',
            fr: 'Imprimantes/Scanner',
            en: 'Printers/Scanners'),
      ),
      SubCategory(
        id: 'network',
        name:
            L10n3(ar: 'شبكات/واي فاي', fr: 'Réseau/Wi‑Fi', en: 'Network/Wi‑Fi'),
      ),
      SubCategory(
        id: 'components',
        name:
            L10n3(ar: 'قطع كمبيوتر', fr: 'Composants PC', en: 'PC components'),
      ),
      SubCategory(
          id: 'accessories',
          name: L10n3(ar: 'ملحقات', fr: 'Accessoires', en: 'Accessories')),
    ],
  ),
  CategoryNode(
    id: 'home',
    name: L10n3(ar: 'البيت', fr: 'Maison', en: 'Home'),
    sub: [
      SubCategory(
          id: 'furniture',
          name: L10n3(ar: 'أثاث', fr: 'Meubles', en: 'Furniture')),
      SubCategory(
          id: 'appliances',
          name: L10n3(
              ar: 'أجهزة منزلية', fr: 'Électroménager', en: 'Appliances')),
      SubCategory(
          id: 'kitchen', name: L10n3(ar: 'مطبخ', fr: 'Cuisine', en: 'Kitchen')),
      SubCategory(
          id: 'bedding',
          name: L10n3(ar: 'مفروشات', fr: 'Literie', en: 'Bedding')),
      SubCategory(
          id: 'lighting',
          name: L10n3(ar: 'إنارة', fr: 'Éclairage', en: 'Lighting')),
      SubCategory(
          id: 'decor', name: L10n3(ar: 'ديكور', fr: 'Décoration', en: 'Decor')),
      SubCategory(
          id: 'storage',
          name: L10n3(
              ar: 'تخزين/تنظيم',
              fr: 'Rangement',
              en: 'Storage & organization')),
      SubCategory(
          id: 'bathroom',
          name: L10n3(ar: 'حمام', fr: 'Salle de bain', en: 'Bathroom')),
      SubCategory(
          id: 'cleaning_supplies',
          name: L10n3(ar: 'تنظيف', fr: 'Nettoyage', en: 'Cleaning')),
      SubCategory(
          id: 'renovation',
          name: L10n3(ar: 'ترميم/إصلاح', fr: 'Rénovation', en: 'Renovation')),
    ],
  ),
  CategoryNode(
    id: 'fashion',
    name: L10n3(ar: 'الأزياء', fr: 'Mode', en: 'Fashion'),
    sub: [
      SubCategory(
        id: 'ma_traditional',
        name: L10n3(
          ar: 'الأزياء الموريتانية التقليدية',
          fr: 'Tenue mauritanienne',
          en: 'Mauritanian traditional',
        ),
      ),
      SubCategory(
          id: 'melhafa',
          name: L10n3(ar: 'ملحفة', fr: 'Melhafa', en: 'Melhafa')),
      SubCategory(
          id: 'daraa', name: L10n3(ar: 'دراعة', fr: 'Daraa', en: 'Daraa')),
      SubCategory(
          id: 'women_clothing',
          name: L10n3(ar: 'ملابس نسائية', fr: 'Femme', en: 'Women')),
      SubCategory(
          id: 'men_clothing',
          name: L10n3(ar: 'ملابس رجالية', fr: 'Homme', en: 'Men')),
      SubCategory(
          id: 'kids_clothing',
          name: L10n3(ar: 'ملابس أطفال', fr: 'Enfants', en: 'Kids')),
      SubCategory(
          id: 'shoes', name: L10n3(ar: 'أحذية', fr: 'Chaussures', en: 'Shoes')),
      SubCategory(
          id: 'litham_turban',
          name: L10n3(
              ar: 'لثام/عمامة', fr: 'Litham/Turban', en: 'Litham/Turban')),
      SubCategory(id: 'bags', name: L10n3(ar: 'حقائب', fr: 'Sacs', en: 'Bags')),
      SubCategory(
          id: 'watches',
          name: L10n3(ar: 'ساعات', fr: 'Montres', en: 'Watches')),
      SubCategory(
          id: 'jewelry',
          name: L10n3(ar: 'مجوهرات', fr: 'Bijoux', en: 'Jewelry')),
      SubCategory(
          id: 'sunglasses',
          name: L10n3(ar: 'نظارات', fr: 'Lunettes', en: 'Eyewear')),
      SubCategory(
          id: 'perfume',
          name: L10n3(
              ar: 'عطور/تجميل', fr: 'Parfums/Beauté', en: 'Perfume/Beauty')),
      SubCategory(
          id: 'tailoring',
          name: L10n3(ar: 'خياطة/تفصال', fr: 'Couture', en: 'Tailoring')),
    ],
  ),
  CategoryNode(
    id: 'beauty',
    name:
        L10n3(ar: 'الجمال والعناية', fr: 'Beauté & soin', en: 'Beauty & care'),
    sub: [
      SubCategory(
          id: 'skincare',
          name: L10n3(ar: 'عناية بالبشرة', fr: 'Soins peau', en: 'Skincare')),
      SubCategory(
          id: 'makeup',
          name: L10n3(ar: 'مكياج', fr: 'Maquillage', en: 'Makeup')),
      SubCategory(
          id: 'hair', name: L10n3(ar: 'شعر', fr: 'Cheveux', en: 'Hair')),
      SubCategory(
          id: 'nails', name: L10n3(ar: 'أظافر', fr: 'Ongles', en: 'Nails')),
      SubCategory(
          id: 'men_grooming',
          name: L10n3(
              ar: 'عناية رجالية', fr: 'Soins hommes', en: 'Men grooming')),
      SubCategory(
          id: 'salon_tools',
          name:
              L10n3(ar: 'أدوات صالون', fr: 'Outils salon', en: 'Salon tools')),
      SubCategory(
          id: 'fragrance',
          name: L10n3(ar: 'عطور', fr: 'Parfums', en: 'Fragrance')),
      SubCategory(
          id: 'personal_care',
          name: L10n3(ar: 'عناية شخصية', fr: 'Hygiène', en: 'Personal care')),
    ],
  ),
  CategoryNode(
    id: 'kids_toys',
    name: L10n3(
        ar: 'الأطفال والألعاب', fr: 'Enfants & jouets', en: 'Kids & toys'),
    sub: [
      SubCategory(
          id: 'baby',
          name: L10n3(ar: 'مستلزمات الرضع', fr: 'Bébé', en: 'Baby')),
      SubCategory(
          id: 'toys', name: L10n3(ar: 'ألعاب', fr: 'Jouets', en: 'Toys')),
      SubCategory(
          id: 'school', name: L10n3(ar: 'مدرسة', fr: 'École', en: 'School')),
      SubCategory(
          id: 'strollers',
          name: L10n3(ar: 'عربات/كراسي', fr: 'Poussettes', en: 'Strollers')),
    ],
  ),
  CategoryNode(
    id: 'sports_hobbies',
    name: L10n3(
        ar: 'رياضة وهوايات', fr: 'Sport & loisirs', en: 'Sports & hobbies'),
    sub: [
      SubCategory(
          id: 'fitness',
          name: L10n3(ar: 'لياقة', fr: 'Fitness', en: 'Fitness')),
      SubCategory(
          id: 'outdoor',
          name: L10n3(ar: 'تخييم/خارجية', fr: 'Outdoor', en: 'Outdoor')),
      SubCategory(
          id: 'cycling',
          name: L10n3(ar: 'دراجات/إكسسوارات', fr: 'Cyclisme', en: 'Cycling')),
      SubCategory(
          id: 'fishing', name: L10n3(ar: 'صيد', fr: 'Pêche', en: 'Fishing')),
      SubCategory(
          id: 'music', name: L10n3(ar: 'موسيقى', fr: 'Musique', en: 'Music')),
    ],
  ),
  CategoryNode(
    id: 'tools',
    name: L10n3(ar: 'أدوات ومعدات', fr: 'Outils', en: 'Tools & equipment'),
    sub: [
      SubCategory(
          id: 'hardware',
          name: L10n3(ar: 'معدات يدوية', fr: 'Quincaillerie', en: 'Hardware')),
      SubCategory(
          id: 'power_tools',
          name: L10n3(
              ar: 'أدوات كهربائية',
              fr: 'Outils électriques',
              en: 'Power tools')),
      SubCategory(
          id: 'construction',
          name: L10n3(ar: 'مواد بناء', fr: 'Construction', en: 'Construction')),
      SubCategory(
          id: 'garden', name: L10n3(ar: 'حديقة', fr: 'Jardin', en: 'Garden')),
      SubCategory(
          id: 'safety', name: L10n3(ar: 'سلامة', fr: 'Sécurité', en: 'Safety')),
    ],
  ),
  CategoryNode(
    id: 'books',
    name: L10n3(
        ar: 'كتب وقرطاسية', fr: 'Livres & papeterie', en: 'Books & stationery'),
    sub: [
      SubCategory(
          id: 'books_only', name: L10n3(ar: 'كتب', fr: 'Livres', en: 'Books')),
      SubCategory(
          id: 'stationery',
          name: L10n3(ar: 'قرطاسية', fr: 'Papeterie', en: 'Stationery')),
      SubCategory(
          id: 'education',
          name: L10n3(ar: 'تعليم', fr: 'Éducation', en: 'Education')),
      SubCategory(id: 'art', name: L10n3(ar: 'رسم/فن', fr: 'Art', en: 'Art')),
    ],
  ),
  CategoryNode(
    id: 'agri_livestock',
    name: L10n3(
        ar: 'الزراعة والمواشي', fr: 'Agri & Bétail', en: 'Agri & Livestock'),
    sub: [
      SubCategory(
          id: 'sheep_cattle',
          name:
              L10n3(ar: 'أغنام/أبقار', fr: 'Ovins/Bovins', en: 'Sheep/Cattle')),
      SubCategory(
          id: 'camels', name: L10n3(ar: 'إبل', fr: 'Chameaux', en: 'Camels')),
      SubCategory(
          id: 'goats', name: L10n3(ar: 'ماعز', fr: 'Chèvres', en: 'Goats')),
      SubCategory(
          id: 'poultry',
          name: L10n3(ar: 'دواجن', fr: 'Volaille', en: 'Poultry')),
      SubCategory(
          id: 'feed', name: L10n3(ar: 'أعلاف', fr: 'Aliments', en: 'Feed')),
      SubCategory(
          id: 'seeds',
          name: L10n3(ar: 'بذور/شتلات', fr: 'Semences', en: 'Seeds')),
      SubCategory(
          id: 'equipment',
          name: L10n3(ar: 'معدات', fr: 'Équipements', en: 'Equipment')),
    ],
  ),

  CategoryNode(
    id: 'pets',
    name: L10n3(ar: 'مستلزمات الحيوانات', fr: 'Animaux', en: 'Pets'),
    sub: [
      SubCategory(
          id: 'pet_food',
          name: L10n3(ar: 'طعام', fr: 'Nourriture', en: 'Food')),
      SubCategory(
          id: 'pet_accessories',
          name: L10n3(ar: 'إكسسوارات', fr: 'Accessoires', en: 'Accessories')),
      SubCategory(
          id: 'pet_care', name: L10n3(ar: 'عناية', fr: 'Soin', en: 'Care')),
      SubCategory(
          id: 'pet_shelter',
          name: L10n3(ar: 'بيوت/أقفاص', fr: 'Cages', en: 'Shelters/Cages')),
    ],
  ),

  CategoryNode(
    id: 'services',
    name: L10n3(ar: 'الخدمات', fr: 'Services', en: 'Services'),
    sub: [
      SubCategory(
          id: 'repair',
          name: L10n3(ar: 'صيانة', fr: 'Réparation', en: 'Repair')),
      SubCategory(
          id: 'transport',
          name: L10n3(ar: 'نقل/ترحيل', fr: 'Transport', en: 'Transport')),
      SubCategory(
          id: 'cleaning',
          name: L10n3(ar: 'تنظيف', fr: 'Nettoyage', en: 'Cleaning')),
      SubCategory(
          id: 'construction_services',
          name: L10n3(ar: 'بناء/ترميم', fr: 'BTP', en: 'Construction')),
      SubCategory(
          id: 'wedding',
          name: L10n3(ar: 'أفراح/مناسبات', fr: 'Événements', en: 'Events')),
      SubCategory(
          id: 'lessons',
          name: L10n3(ar: 'دروس/تدريب', fr: 'Cours', en: 'Lessons')),
      SubCategory(
          id: 'beauty', name: L10n3(ar: 'تجميل', fr: 'Beauté', en: 'Beauty')),
      SubCategory(
          id: 'digital',
          name: L10n3(ar: 'خدمات رقمية', fr: 'Digital', en: 'Digital')),
    ],
  ),
  CategoryNode(
    id: 'jobs',
    name: L10n3(ar: 'وظائف', fr: 'Emplois', en: 'Jobs'),
    sub: [
      SubCategory(
          id: 'jobs_offers',
          name: L10n3(ar: 'عروض عمل', fr: 'Offres', en: 'Offers')),
      SubCategory(
          id: 'jobs_seek',
          name: L10n3(ar: 'باحث عن عمل', fr: 'Candidats', en: 'Seeking')),
    ],
  ),
  // Fallback bucket for uncategorized / unknown items.
  CategoryNode(
    id: 'other',
    name: L10n3(ar: 'أخرى', fr: 'Autre', en: 'Other'),
    sub: [kOtherSubcategory],
  ),
];
// Service tags for “Services” publish/filters
const maServiceTags = <ServiceTag>[
  ServiceTag(
      id: 'electrician',
      name: L10n3(ar: 'كهرباء منازل', fr: 'Électricité', en: 'Electrician')),
  ServiceTag(
      id: 'plumber', name: L10n3(ar: 'سباكة', fr: 'Plomberie', en: 'Plumber')),
  ServiceTag(
      id: 'ac',
      name: L10n3(ar: 'صيانة مكيفات', fr: 'Climatisation', en: 'AC Service')),
  ServiceTag(
      id: 'mechanic',
      name: L10n3(ar: 'ميكانيك سيارات', fr: 'Mécanique', en: 'Mechanic')),
  ServiceTag(
      id: 'phone_repair',
      name: L10n3(
          ar: 'صيانة هواتف', fr: 'Réparation téléphone', en: 'Phone Repair')),
  ServiceTag(
      id: 'computer_repair',
      name: L10n3(
          ar: 'صيانة كمبيوتر', fr: 'Réparation PC', en: 'Computer Repair')),
  ServiceTag(
      id: 'transport_city',
      name: L10n3(
          ar: 'نقل داخل المدينة',
          fr: 'Transport urbain',
          en: 'City Transport')),
  ServiceTag(
      id: 'transport_between',
      name: L10n3(
          ar: 'نقل بين الولايات',
          fr: 'Inter-wilaya',
          en: 'Intercity Transport')),
  ServiceTag(
      id: 'moving',
      name: L10n3(ar: 'ترحيل أثاث', fr: 'Déménagement', en: 'Moving')),
  ServiceTag(
      id: 'cleaning',
      name: L10n3(ar: 'تنظيف', fr: 'Nettoyage', en: 'Cleaning')),
  ServiceTag(
      id: 'tutoring',
      name: L10n3(ar: 'دروس خصوصية', fr: 'Cours particuliers', en: 'Tutoring')),
  ServiceTag(
      id: 'wedding_tents',
      name: L10n3(
          ar: 'خيمة وكراسي', fr: 'Tentes & chaises', en: 'Tents & Chairs')),
  ServiceTag(
      id: 'photo_video',
      name: L10n3(ar: 'تصوير مناسبات', fr: 'Photo/Vidéo', en: 'Photo/Video')),
  ServiceTag(
      id: 'catering',
      name: L10n3(ar: 'طبخ/تموين', fr: 'Traiteur', en: 'Catering')),
  ServiceTag(
      id: 'beauty_makeup',
      name: L10n3(
          ar: 'صالون/ميكاب', fr: 'Salon/Maquillage', en: 'Beauty/Makeup')),
  ServiceTag(
      id: 'design_print',
      name: L10n3(
          ar: 'تصميم/طباعة', fr: 'Design/Impression', en: 'Design/Printing')),
];

// ---------------------------------------------------------------------------
// Wilayas + moughataas (15 wilayas including 3 for Nouakchott)
// ---------------------------------------------------------------------------

const maWilayas = <Wilaya>[
  Wilaya(
    id: 'adrar',
    name: L10n3(ar: 'آدرار', fr: 'Adrar', en: 'Adrar'),
    moughataas: [
      Moughataa(
          id: 'aoujeft',
          name: L10n3(ar: 'أوجفت', fr: 'Aoujeft', en: 'Aoujeft')),
      Moughataa(id: 'atar', name: L10n3(ar: 'أطار', fr: 'Atar', en: 'Atar')),
      Moughataa(
          id: 'chinguetti',
          name: L10n3(ar: 'شنقيط', fr: 'Chinguetti', en: 'Chinguetti')),
      Moughataa(
          id: 'ouadane',
          name: L10n3(ar: 'وادان', fr: 'Ouadane', en: 'Ouadane')),
    ],
  ),
  Wilaya(
    id: 'assaba',
    name: L10n3(ar: 'لعصابه', fr: 'Assaba', en: 'Assaba'),
    moughataas: [
      Moughataa(id: 'kiffa', name: L10n3(ar: 'كيفة', fr: 'Kiffa', en: 'Kiffa')),
      Moughataa(
          id: 'kankossa',
          name: L10n3(ar: 'كنكوصه', fr: 'Kankossa', en: 'Kankossa')),
      Moughataa(
          id: 'guerou', name: L10n3(ar: 'گرو', fr: 'Guerou', en: 'Guerou')),
      Moughataa(
          id: 'barkeol',
          name: L10n3(ar: 'باركيول', fr: 'Barkéol', en: 'Barkeol')),
    ],
  ),
  Wilaya(
    id: 'brakna',
    name: L10n3(ar: 'لبراكنه', fr: 'Brakna', en: 'Brakna'),
    moughataas: [
      Moughataa(id: 'aleg', name: L10n3(ar: 'ألاگ', fr: 'Aleg', en: 'Aleg')),
      Moughataa(id: 'boghe', name: L10n3(ar: 'بوغي', fr: 'Boghé', en: 'Boghé')),
      Moughataa(
          id: 'bababe', name: L10n3(ar: 'بابابي', fr: 'Bababé', en: 'Bababé')),
      Moughataa(
          id: 'magta_lahjar',
          name:
              L10n3(ar: 'مقطع لحجار', fr: 'Magta-Lahjar', en: 'Magta-Lahjar')),
    ],
  ),
  Wilaya(
    id: 'dakhlet_nouadhibou',
    name: L10n3(
        ar: 'داخلت نواذيبو',
        fr: 'Dakhlet Nouadhibou',
        en: 'Dakhlet Nouadhibou'),
    moughataas: [
      Moughataa(
          id: 'nouadhibou',
          name: L10n3(ar: 'نواذيبو', fr: 'Nouadhibou', en: 'Nouadhibou')),
      Moughataa(
          id: 'chami', name: L10n3(ar: 'الشامي', fr: 'Chami', en: 'Chami')),
    ],
  ),
  Wilaya(
    id: 'gorgol',
    name: L10n3(ar: 'غورغول', fr: 'Gorgol', en: 'Gorgol'),
    moughataas: [
      Moughataa(
          id: 'kaedi', name: L10n3(ar: 'كيهيدي', fr: 'Kaédi', en: 'Kaédi')),
      Moughataa(
          id: 'lexeiba',
          name: L10n3(ar: 'لكصيبه 1', fr: 'Lexeiba 1', en: 'Lexeiba 1')),
      Moughataa(
          id: 'maghama',
          name: L10n3(ar: 'مقامة', fr: 'Maghama', en: 'Maghama')),
      Moughataa(
          id: 'mbout', name: L10n3(ar: 'امبود', fr: "M'Bout", en: "M'Bout")),
    ],
  ),
  Wilaya(
    id: 'guidimakha',
    name: L10n3(ar: 'گيديماغه', fr: 'Guidimakha', en: 'Guidimakha'),
    moughataas: [
      Moughataa(
          id: 'selibaby',
          name: L10n3(ar: 'سيلبابي', fr: 'Sélibaby', en: 'Sélibaby')),
      Moughataa(
          id: 'ould_yenge',
          name: L10n3(ar: 'ولد ينگه', fr: 'Ould Yengé', en: 'Ould Yengé')),
      Moughataa(
          id: 'wompou', name: L10n3(ar: 'وابو', fr: 'Wompou', en: 'Wompou')),
      Moughataa(
          id: 'ghabou', name: L10n3(ar: 'قابو', fr: 'Ghabou', en: 'Ghabou')),
    ],
  ),
  Wilaya(
    id: 'hodh_ech_chargui',
    name: L10n3(
        ar: 'الحوض الشرقي', fr: 'Hodh Ech Chargui', en: 'Hodh Ech Chargui'),
    moughataas: [
      Moughataa(id: 'nema', name: L10n3(ar: 'النعمة', fr: 'Néma', en: 'Néma')),
      Moughataa(
          id: 'bassikounou',
          name: L10n3(ar: 'باسكنو', fr: 'Bassikounou', en: 'Bassikounou')),
      Moughataa(
          id: 'timbedra',
          name: L10n3(ar: 'تمبدغة', fr: 'Timbedra', en: 'Timbedra')),
      Moughataa(
          id: 'oualata',
          name: L10n3(ar: 'ولاتة', fr: 'Oualata', en: 'Oualata')),
    ],
  ),
  Wilaya(
    id: 'hodh_el_gharbi',
    name: L10n3(ar: 'الحوض الغربي', fr: 'Hodh El Gharbi', en: 'Hodh El Gharbi'),
    moughataas: [
      Moughataa(
          id: 'aioun', name: L10n3(ar: 'العيون', fr: 'Aïoun', en: 'Aïoun')),
      Moughataa(
          id: 'kobonni',
          name: L10n3(ar: 'كوبني', fr: 'Kobonni', en: 'Kobonni')),
      Moughataa(
          id: 'tamchekett',
          name: L10n3(ar: 'تامشكط', fr: 'Tamchekett', en: 'Tamchekett')),
      Moughataa(
          id: 'tintane', name: L10n3(ar: 'تگنت', fr: 'Tintane', en: 'Tintane')),
    ],
  ),
  Wilaya(
    id: 'inchiri',
    name: L10n3(ar: 'إنشيري', fr: 'Inchiri', en: 'Inchiri'),
    moughataas: [
      Moughataa(
          id: 'akjoujt',
          name: L10n3(ar: 'أكجوجت', fr: 'Akjoujt', en: 'Akjoujt')),
      Moughataa(
          id: 'benichab',
          name: L10n3(ar: 'بنشاب', fr: 'Benichab', en: 'Benichab')),
    ],
  ),

  // Nouakchott split into 3 wilayas (each has 3 moughataa).
  Wilaya(
    id: 'nouakchott_nord',
    name: L10n3(
        ar: 'نواكشوط الشمالية', fr: 'Nouakchott-Nord', en: 'Nouakchott-North'),
    moughataas: [
      Moughataa(
          id: 'dar_naim',
          name: L10n3(ar: 'دار النعيم', fr: 'Dar-Naim', en: 'Dar-Naim')),
      Moughataa(
          id: 'teyarett',
          name: L10n3(ar: 'تيارت', fr: 'Teyarett', en: 'Teyarett')),
      Moughataa(
          id: 'toujounine',
          name: L10n3(ar: 'توجونين', fr: 'Toujounine', en: 'Toujounine')),
    ],
  ),
  Wilaya(
    id: 'nouakchott_ouest',
    name: L10n3(
        ar: 'نواكشوط الغربية', fr: 'Nouakchott-Ouest', en: 'Nouakchott-West'),
    moughataas: [
      Moughataa(id: 'ksar', name: L10n3(ar: 'لكصر', fr: 'Ksar', en: 'Ksar')),
      Moughataa(
          id: 'sebkha', name: L10n3(ar: 'السبخة', fr: 'Sebkha', en: 'Sebkha')),
      Moughataa(
          id: 'tevragh_zeina',
          name:
              L10n3(ar: 'تفرغ زينه', fr: 'Tevragh-Zeina', en: 'Tevragh-Zeina')),
    ],
  ),
  Wilaya(
    id: 'nouakchott_sud',
    name: L10n3(
        ar: 'نواكشوط الجنوبية', fr: 'Nouakchott-Sud', en: 'Nouakchott-South'),
    moughataas: [
      Moughataa(
          id: 'arafat', name: L10n3(ar: 'عرفات', fr: 'Arafat', en: 'Arafat')),
      Moughataa(
          id: 'el_mina',
          name: L10n3(ar: 'الميناء', fr: 'El Mina', en: 'El Mina')),
      Moughataa(
          id: 'riyad', name: L10n3(ar: 'الرياض', fr: 'Riyad', en: 'Riyad')),
    ],
  ),

  Wilaya(
    id: 'tagant',
    name: L10n3(ar: 'تكانت', fr: 'Tagant', en: 'Tagant'),
    moughataas: [
      Moughataa(
          id: 'tidjikdja',
          name: L10n3(ar: 'تجكجه', fr: 'Tidjikdja', en: 'Tidjikdja')),
      Moughataa(
          id: 'moudjeria',
          name: L10n3(ar: 'مجرية', fr: 'Moudjéria', en: 'Moudjéria')),
      Moughataa(
          id: 'tichitt',
          name: L10n3(ar: 'تيشيت', fr: 'Tichitt', en: 'Tichitt')),
    ],
  ),
  Wilaya(
    id: 'tiris_zemmour',
    name: L10n3(ar: 'تيرس زمور', fr: 'Tiris Zemmour', en: 'Tiris Zemmour'),
    moughataas: [
      Moughataa(
          id: 'zouerat',
          name: L10n3(ar: 'الزويرات', fr: 'Zouérat', en: 'Zouérat')),
      Moughataa(
          id: 'fderik',
          name: L10n3(ar: 'افديرك', fr: "F'Dérik", en: "F'Dérik")),
      Moughataa(
          id: 'bir_moghrein',
          name: L10n3(
              ar: 'بير أم اغرين', fr: 'Bir Moghrein', en: 'Bir Moghrein')),
    ],
  ),
  Wilaya(
    id: 'trarza',
    name: L10n3(ar: 'الترارزه', fr: 'Trarza', en: 'Trarza'),
    moughataas: [
      Moughataa(id: 'rosso', name: L10n3(ar: 'روصو', fr: 'Rosso', en: 'Rosso')),
      Moughataa(
          id: 'boutilimit',
          name: L10n3(ar: 'بوتلميت', fr: 'Boutilimit', en: 'Boutilimit')),
      Moughataa(
          id: 'mederdra',
          name: L10n3(ar: 'المذرذرة', fr: 'Méderdra', en: 'Méderdra')),
      Moughataa(id: 'rkiz', name: L10n3(ar: 'اركيز', fr: "R'Kiz", en: "R'Kiz")),
    ],
  ),
];

Wilaya? findWilayaById(String id) {
  for (final w in maWilayas) {
    if (w.id == id) return w;
  }
  return null;
}

CategoryNode? findCategoryById(String id) {
  for (final c in maCategories) {
    if (c.id == id) return c;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Helpers: resolve stored (id OR label) into the current locale label.
// This avoids mixed-language UI when old data stored 'آدرار' then user switches to FR.
// ---------------------------------------------------------------------------

String _maNorm(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');

/// Accepts wilaya id (e.g. 'adrar') OR any localized label (e.g. 'آدرار', 'Adrar').
/// Returns the label in the current locale. Falls back to [raw] if not found.
String resolveWilayaLabel(BuildContext context, String raw) {
  final v = raw.trim();
  if (v.isEmpty) return v;

  final n = _maNorm(v);
  for (final w in maWilayas) {
    if (n == _maNorm(w.id) ||
        n == _maNorm(w.name.ar) ||
        n == _maNorm(w.name.fr) ||
        n == _maNorm(w.name.en)) {
      return w.name.of(context);
    }
  }
  return v;
}

/// Accepts moughataa id OR any localized label.
/// Optionally pass [wilayaRaw] (id/label) to speed up matching in that wilaya first.
String resolveMoughataaLabel(BuildContext context, String raw,
    {String? wilayaRaw}) {
  final v = raw.trim();
  if (v.isEmpty) return v;

  final n = _maNorm(v);

  Iterable<Wilaya> scope = maWilayas;
  if (wilayaRaw != null && wilayaRaw.trim().isNotEmpty) {
    final wLabel = resolveWilayaLabel(context, wilayaRaw);
    final wNorm = _maNorm(wLabel);
    final found = maWilayas.where((w) =>
        wNorm == _maNorm(w.id) ||
        wNorm == _maNorm(w.name.ar) ||
        wNorm == _maNorm(w.name.fr) ||
        wNorm == _maNorm(w.name.en));
    if (found.isNotEmpty) scope = found;
  }

  for (final w in scope) {
    for (final m in w.moughataas) {
      if (n == _maNorm(m.id) ||
          n == _maNorm(m.name.ar) ||
          n == _maNorm(m.name.fr) ||
          n == _maNorm(m.name.en)) {
        return m.name.of(context);
      }
    }
  }

  // fallback: search globally (in case wilayaRaw didn't match)
  for (final w in maWilayas) {
    for (final m in w.moughataas) {
      if (n == _maNorm(m.id) ||
          n == _maNorm(m.name.ar) ||
          n == _maNorm(m.name.fr) ||
          n == _maNorm(m.name.en)) {
        return m.name.of(context);
      }
    }
  }

  return v;
}
