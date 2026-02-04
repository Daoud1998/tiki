import 'package:flutter/foundation.dart';
import '../search/ma_search_tokens.dart';

/// Simple in-memory mock data used across the app until Firestore is wired.
///
/// This model is intentionally a bit "wide" to keep the UI moving fast while
/// Firestore (and real schemas) are still pending.
@immutable
class MockProduct {
  MockProduct({
    required this.id,
    required this.title,
    required this.sellerId,
    required this.sellerName,
    required this.price,
    required this.wilaya,
    required this.moughataa,
    required this.neighborhood,
    required this.publishedAt,
    this.subtitle,
    this.description,
    this.details,
    this.category,
    this.subCategory,
    List<String>? images,
    String? imageUrl,
    this.isSold = false,
    this.oldPrice,
    this.phone,
    this.allowWhatsApp = true,
    this.allowCall = true,
    this.hasWarranty = false,
    this.warrantyValue,
    this.warrantyUnit,
    this.warrantyType,
    List<String>? searchTokens,
    this.attrs = const <String, String>{},
  }) : searchTokens = List<String>.unmodifiable(
            searchTokens ??
                maBuildSearchTokens(fields: <String>[
              title,
              subtitle ?? '',
              description ?? '',
              details ?? '',
              sellerName,
              category ?? '',
              subCategory ?? '',
              wilaya,
              moughataa,
              neighborhood,
              ...attrs.values,
            ]),
          ),
          images = images ??
              ((imageUrl != null && imageUrl.trim().isNotEmpty)
                  ? <String>[imageUrl.trim()]
                  : <String>[]);

  final String id;
  final String title;

  /// Stable seller identifier in mock mode.
  /// Later this becomes Firebase uid.
  final String sellerId;

  /// The only extra thing we show on product cards.
  final String sellerName;
  final String? subtitle;
  final String? description;
  final String? details;

  final String? category;
  final String? subCategory;

  /// Price in MRU (0 means negotiable).
  final int price;
  final int? oldPrice;

  /// Main media list. Can be empty.
  final List<String> images;

  /// Backward-compatible single-image getter.
  String get imageUrl => images.isNotEmpty ? images.first : '';

  final String wilaya;
  final String moughataa;
  final String neighborhood;

  final DateTime publishedAt;
  final bool isSold;

  /// Contact phone (can be WhatsApp too). Example: +222 33 12 45 67
  final String? phone;
  final bool allowWhatsApp;
  final bool allowCall;

  /// Warranty
  final bool hasWarranty;
  final int? warrantyValue;

  /// 'days' | 'weeks' | 'months' | 'years'
  final String? warrantyUnit;

  /// 'seller' | 'brand'
  final String? warrantyType;

  /// Normalized keywords for fast search (store this on Firestore later).
  final List<String> searchTokens;

  /// Extra optional attributes (quick fields).
  final Map<String, String> attrs;

  MockProduct copyWith({
    String? title,
    String? subtitle,
    String? description,
    String? details,
    String? category,
    String? subCategory,
    int? price,
    int? oldPrice,
    List<String>? images,
    String? wilaya,
    String? moughataa,
    String? neighborhood,
    DateTime? publishedAt,
    bool? isSold,
    String? phone,
    bool? allowWhatsApp,
    bool? allowCall,
    bool? hasWarranty,
    int? warrantyValue,
    String? warrantyUnit,
    String? warrantyType,
    List<String>? searchTokens,
    Map<String, String>? attrs,
    String? sellerId,
    String? sellerName,
  }) {
    return MockProduct(
      id: id,
      title: title ?? this.title,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      price: price ?? this.price,
      wilaya: wilaya ?? this.wilaya,
      moughataa: moughataa ?? this.moughataa,
      neighborhood: neighborhood ?? this.neighborhood,
      publishedAt: publishedAt ?? this.publishedAt,
      subtitle: subtitle ?? this.subtitle,
      description: description ?? this.description,
      details: details ?? this.details,
      category: category ?? this.category,
      subCategory: subCategory ?? this.subCategory,
      images: images ?? this.images,
      isSold: isSold ?? this.isSold,
      oldPrice: oldPrice ?? this.oldPrice,
      phone: phone ?? this.phone,
      allowWhatsApp: allowWhatsApp ?? this.allowWhatsApp,
      allowCall: allowCall ?? this.allowCall,
      hasWarranty: hasWarranty ?? this.hasWarranty,
      warrantyValue: warrantyValue ?? this.warrantyValue,
      warrantyUnit: warrantyUnit ?? this.warrantyUnit,
      warrantyType: warrantyType ?? this.warrantyType,
      searchTokens: searchTokens ?? this.searchTokens,
      attrs: attrs ?? this.attrs,
    );
  }
}

/// Growable list (Publish screen appends to it in mock mode).
final List<MockProduct> mockProducts = <MockProduct>[
  MockProduct(
    id: 'p1',
    title: 'هاتف iPhone 13 Pro #1',
    sellerId: 'demo_ahmed',
    sellerName: 'أحمد',
    price: 45000,
    oldPrice: 60000,
    images: const [
      'https://picsum.photos/600/800?10',
      'https://picsum.photos/600/800?110'
    ],
    wilaya: 'نواكشوط',
    moughataa: 'تفرغ زينه',
    neighborhood: 'حي S',
    phone: '+222 34 11 22 33',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: true,
    warrantyValue: 12,
    warrantyUnit: 'months',
    warrantyType: 'seller',
    publishedAt: DateTime.now().subtract(Duration(days: 0, hours: 0)),
    category: 'electronics',
    subCategory: 'phones',
    attrs: {
      '__promo_status': 'approved',
      '__promo_pkg_id': 'top',
      '__promo_tier': 'top',
      '__promo_appr_at_ms':
          '${DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch}',
      '__promo_until_ms':
          '${DateTime.now().add(const Duration(days: 5)).millisecondsSinceEpoch}',
      'type': 'iPhone',
      'storage': '256GB',
      'color': 'أسود',
      'condition': 'مستعمل'
    },
  ),
  MockProduct(
    id: 'p2',
    title: 'Samsung Galaxy A32 بحالة ممتازة #2',
    sellerId: 'demo_mariem',
    sellerName: 'مريم',
    price: 4500,
    oldPrice: 6500,
    images: const [
      'https://picsum.photos/600/800?11',
      'https://picsum.photos/600/800?111'
    ],
    wilaya: 'نواذيبو',
    moughataa: 'الرياض',
    neighborhood: 'الرياض 2',
    phone: '+222 33 12 45 67',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 1, hours: 3)),
    category: 'electronics',
    subCategory: 'phones',
    attrs: {
      '__promo_status': 'approved',
      '__promo_pkg_id': 'featured',
      '__promo_tier': 'featured',
      '__promo_appr_at_ms':
          '${DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch}',
      '__promo_until_ms':
          '${DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch}',
      'type': 'Samsung Galaxy',
      'storage': '128GB',
      'color': 'أبيض',
      'condition': 'مستعمل'
    },
  ),
  MockProduct(
    id: 'p3',
    title: 'Laptop Dell i5 8GB RAM #3',
    sellerId: 'demo_sidi',
    sellerName: 'سيدي',
    price: 18000,
    oldPrice: 24000,
    images: const [
      'https://picsum.photos/600/800?12',
      'https://picsum.photos/600/800?112'
    ],
    wilaya: 'ألاك',
    moughataa: 'دار النعيم',
    neighborhood: 'الميناء',
    phone: '+222 22 11 33 44',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 2, hours: 6)),
    category: 'electronics',
    subCategory: 'computers',
    attrs: {
      '__promo_status': 'approved',
      '__promo_pkg_id': 'boost',
      '__promo_tier': 'boost',
      '__promo_appr_at_ms':
          '${DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch}',
      '__promo_until_ms':
          '${DateTime.now().add(const Duration(days: 2)).millisecondsSinceEpoch}',
      'type': 'Laptop',
      'ram': '8GB',
      'condition': 'مستعمل'
    },
  ),
  MockProduct(
    id: 'p4',
    title: 'شقة للإيجار قرب السوق #4',
    sellerId: 'demo_fatma',
    sellerName: 'فاطمة',
    price: 12000,
    images: const [
      'https://picsum.photos/600/800?13',
      'https://picsum.photos/600/800?113'
    ],
    wilaya: 'كيفه',
    moughataa: 'لكصر',
    neighborhood: 'السويسي',
    phone: '+222 40 55 66 77',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 3, hours: 9)),
    category: 'real_estate',
    subCategory: 'apartment',
    attrs: const {
      'type': 'شقة',
      'rooms': '3',
      'area': '120',
      'condition': 'غير محدد'
    },
  ),
  MockProduct(
    id: 'p5',
    title: 'أرض للبيع على شارع رئيسي #5',
    sellerId: 'demo_mohamed',
    sellerName: 'محمد',
    price: 65000,
    images: const [
      'https://picsum.photos/600/800?14',
      'https://picsum.photos/600/800?114'
    ],
    wilaya: 'نواكشوط',
    moughataa: 'تفرغ زينه',
    neighborhood: 'حي S',
    phone: '+222 46 77 88 99',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 4, hours: 12)),
    category: 'real_estate',
    subCategory: 'land',
    attrs: const {'type': 'أرض تجارية', 'condition': 'غير محدد'},
  ),
  MockProduct(
    id: 'p6',
    title: 'Toyota Corolla 2014 نظيفة #6',
    sellerId: 'demo_hamza',
    sellerName: 'حمزة',
    price: 220000,
    oldPrice: 260000,
    images: const [
      'https://picsum.photos/600/800?15',
      'https://picsum.photos/600/800?115'
    ],
    wilaya: 'نواذيبو',
    moughataa: 'الرياض',
    neighborhood: 'الرياض 2',
    phone: '+222 36 10 20 30',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: true,
    warrantyValue: 12,
    warrantyUnit: 'months',
    warrantyType: 'seller',
    publishedAt: DateTime.now().subtract(Duration(days: 5, hours: 15)),
    category: 'vehicles',
    subCategory: 'cars',
    attrs: const {
      'type': 'Toyota',
      'year': '2014',
      'fuel': 'بنزين',
      'gear': 'أوتوماتيك',
      'condition': 'مستعمل'
    },
  ),
  MockProduct(
    id: 'p7',
    title: 'دراجة سكوتر اقتصادية #7',
    sellerId: 'demo_ahmed',
    sellerName: 'أحمد',
    price: 28000,
    images: const [
      'https://picsum.photos/600/800?16',
      'https://picsum.photos/600/800?116'
    ],
    wilaya: 'ألاك',
    moughataa: 'دار النعيم',
    neighborhood: 'الميناء',
    phone: '+222 32 55 11 00',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 6, hours: 18)),
    category: 'vehicles',
    subCategory: 'motorcycles',
    attrs: const {'type': 'Scooter', 'condition': 'مستعمل'},
  ),
  MockProduct(
    id: 'p8',
    title: 'Melhafa نسائية جديدة (قماش ممتاز) #8',
    sellerId: 'demo_mariem',
    sellerName: 'مريم',
    price: 2500,
    oldPrice: 3200,
    images: const [
      'https://picsum.photos/600/800?17',
      'https://picsum.photos/600/800?117'
    ],
    wilaya: 'كيفه',
    moughataa: 'لكصر',
    neighborhood: 'السويسي',
    phone: '+222 45 66 77 88',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 7, hours: 21)),
    category: 'fashion',
    subCategory: 'women',
    attrs: const {'type': 'ملابس', 'size': 'L', 'condition': 'جديد'},
  ),
  MockProduct(
    id: 'p9',
    title: 'قميص رجالي رسمي جديد #9',
    sellerId: 'demo_sidi',
    sellerName: 'سيدي',
    price: 1800,
    oldPrice: 2400,
    images: const [
      'https://picsum.photos/600/800?18',
      'https://picsum.photos/600/800?118'
    ],
    wilaya: 'نواكشوط',
    moughataa: 'تفرغ زينه',
    neighborhood: 'حي S',
    phone: '+222 41 22 33 44',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 8, hours: 0)),
    category: 'fashion',
    subCategory: 'men',
    attrs: const {'type': 'ملابس', 'size': 'M', 'condition': 'جديد'},
  ),
  MockProduct(
    id: 'p10',
    title: 'خدمة تصليح هواتف في المنزل #10',
    sellerId: 'demo_fatma',
    sellerName: 'فاطمة',
    price: 0,
    images: const [
      'https://picsum.photos/600/800?19',
      'https://picsum.photos/600/800?119'
    ],
    wilaya: 'نواذيبو',
    moughataa: 'الرياض',
    neighborhood: 'الرياض 2',
    phone: '+222 35 77 00 11',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 0, hours: 3)),
    category: 'services',
    subCategory: 'repair',
    attrs: const {'type': 'تصليح', 'condition': 'غير محدد'},
  ),
  MockProduct(
    id: 'p11',
    title: 'خدمة توصيل داخل نواكشوط #11',
    sellerId: 'demo_mohamed',
    sellerName: 'محمد',
    price: 0,
    images: const [
      'https://picsum.photos/600/800?20',
      'https://picsum.photos/600/800?120'
    ],
    wilaya: 'ألاك',
    moughataa: 'دار النعيم',
    neighborhood: 'الميناء',
    phone: '+222 37 88 99 00',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: true,
    warrantyValue: 12,
    warrantyUnit: 'months',
    warrantyType: 'seller',
    publishedAt: DateTime.now().subtract(Duration(days: 1, hours: 6)),
    category: 'services',
    subCategory: 'transport',
    attrs: const {'type': 'نقل', 'condition': 'غير محدد'},
  ),
  MockProduct(
    id: 'p12',
    title: 'مطلوب عامل مبيعات (دوام كامل) #12',
    sellerId: 'demo_hamza',
    sellerName: 'حمزة',
    price: 0,
    images: const [
      'https://picsum.photos/600/800?21',
      'https://picsum.photos/600/800?121'
    ],
    wilaya: 'كيفه',
    moughataa: 'لكصر',
    neighborhood: 'السويسي',
    phone: '+222 44 12 34 56',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 2, hours: 9)),
    category: 'jobs',
    subCategory: 'jobs',
    attrs: const {'condition': 'غير محدد'},
  ),
  MockProduct(
    id: 'p13',
    title: 'هاتف iPhone 13 Pro #13',
    sellerId: 'demo_ahmed',
    sellerName: 'أحمد',
    price: 45000,
    oldPrice: 58000,
    images: const [
      'https://picsum.photos/600/800?22',
      'https://picsum.photos/600/800?122'
    ],
    wilaya: 'نواكشوط',
    moughataa: 'تفرغ زينه',
    neighborhood: 'حي S',
    phone: '+222 34 11 22 33',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 3, hours: 12)),
    category: 'electronics',
    subCategory: 'phones',
    attrs: const {
      'type': 'iPhone',
      'storage': '256GB',
      'color': 'أسود',
      'condition': 'مستعمل'
    },
  ),
  MockProduct(
    id: 'p14',
    title: 'Samsung Galaxy A32 بحالة ممتازة #14',
    sellerId: 'demo_mariem',
    sellerName: 'مريم',
    price: 4500,
    oldPrice: 6200,
    images: const [
      'https://picsum.photos/600/800?23',
      'https://picsum.photos/600/800?123'
    ],
    wilaya: 'نواذيبو',
    moughataa: 'الرياض',
    neighborhood: 'الرياض 2',
    phone: '+222 33 12 45 67',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 4, hours: 15)),
    category: 'electronics',
    subCategory: 'phones',
    attrs: const {
      'type': 'Samsung Galaxy',
      'storage': '128GB',
      'color': 'أبيض',
      'condition': 'مستعمل'
    },
  ),
  MockProduct(
    id: 'p15',
    title: 'Laptop Dell i5 8GB RAM #15',
    sellerId: 'demo_sidi',
    sellerName: 'سيدي',
    price: 18000,
    images: const [
      'https://picsum.photos/600/800?24',
      'https://picsum.photos/600/800?124'
    ],
    wilaya: 'ألاك',
    moughataa: 'دار النعيم',
    neighborhood: 'الميناء',
    phone: '+222 22 11 33 44',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 5, hours: 18)),
    category: 'electronics',
    subCategory: 'computers',
    attrs: const {'type': 'Laptop', 'ram': '8GB', 'condition': 'مستعمل'},
  ),
  MockProduct(
    id: 'p16',
    title: 'شقة للإيجار قرب السوق #16',
    sellerId: 'demo_fatma',
    sellerName: 'فاطمة',
    price: 12000,
    images: const [
      'https://picsum.photos/600/800?25',
      'https://picsum.photos/600/800?125'
    ],
    wilaya: 'كيفه',
    moughataa: 'لكصر',
    neighborhood: 'السويسي',
    phone: '+222 40 55 66 77',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: true,
    warrantyValue: 12,
    warrantyUnit: 'months',
    warrantyType: 'seller',
    publishedAt: DateTime.now().subtract(Duration(days: 6, hours: 21)),
    category: 'real_estate',
    subCategory: 'apartment',
    attrs: const {
      'type': 'شقة',
      'rooms': '3',
      'area': '120',
      'condition': 'غير محدد'
    },
  ),
  MockProduct(
    id: 'p17',
    title: 'أرض للبيع على شارع رئيسي #17',
    sellerId: 'demo_mohamed',
    sellerName: 'محمد',
    price: 65000,
    images: const [
      'https://picsum.photos/600/800?26',
      'https://picsum.photos/600/800?126'
    ],
    wilaya: 'نواكشوط',
    moughataa: 'تفرغ زينه',
    neighborhood: 'حي S',
    phone: '+222 46 77 88 99',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 7, hours: 0)),
    category: 'real_estate',
    subCategory: 'land',
    attrs: const {'type': 'أرض تجارية', 'condition': 'غير محدد'},
  ),
  MockProduct(
    id: 'p18',
    title: 'Toyota Corolla 2014 نظيفة #18',
    sellerId: 'demo_hamza',
    sellerName: 'حمزة',
    price: 220000,
    images: const [
      'https://picsum.photos/600/800?27',
      'https://picsum.photos/600/800?127'
    ],
    wilaya: 'نواذيبو',
    moughataa: 'الرياض',
    neighborhood: 'الرياض 2',
    phone: '+222 36 10 20 30',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 8, hours: 3)),
    category: 'vehicles',
    subCategory: 'cars',
    attrs: const {
      'type': 'Toyota',
      'year': '2014',
      'fuel': 'بنزين',
      'gear': 'أوتوماتيك',
      'condition': 'مستعمل'
    },
  ),
  MockProduct(
    id: 'p19',
    title: 'دراجة سكوتر اقتصادية #19',
    sellerId: 'demo_ahmed',
    sellerName: 'أحمد',
    price: 28000,
    images: const [
      'https://picsum.photos/600/800?28',
      'https://picsum.photos/600/800?128'
    ],
    wilaya: 'ألاك',
    moughataa: 'دار النعيم',
    neighborhood: 'الميناء',
    phone: '+222 32 55 11 00',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 0, hours: 6)),
    category: 'vehicles',
    subCategory: 'motorcycles',
    attrs: const {'type': 'Scooter', 'condition': 'مستعمل'},
  ),
  MockProduct(
    id: 'p20',
    title: 'Melhafa نسائية جديدة (قماش ممتاز) #20',
    sellerId: 'demo_mariem',
    sellerName: 'مريم',
    price: 2500,
    images: const [
      'https://picsum.photos/600/800?29',
      'https://picsum.photos/600/800?129'
    ],
    wilaya: 'كيفه',
    moughataa: 'لكصر',
    neighborhood: 'السويسي',
    phone: '+222 45 66 77 88',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 1, hours: 9)),
    category: 'fashion',
    subCategory: 'women',
    attrs: const {'type': 'ملابس', 'size': 'L', 'condition': 'جديد'},
  ),
  MockProduct(
    id: 'p21',
    title: 'قميص رجالي رسمي جديد #21',
    sellerId: 'demo_sidi',
    sellerName: 'سيدي',
    price: 1800,
    images: const [
      'https://picsum.photos/600/800?30',
      'https://picsum.photos/600/800?130'
    ],
    wilaya: 'نواكشوط',
    moughataa: 'تفرغ زينه',
    neighborhood: 'حي S',
    phone: '+222 41 22 33 44',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: true,
    warrantyValue: 12,
    warrantyUnit: 'months',
    warrantyType: 'seller',
    publishedAt: DateTime.now().subtract(Duration(days: 2, hours: 12)),
    category: 'fashion',
    subCategory: 'men',
    attrs: const {'type': 'ملابس', 'size': 'M', 'condition': 'جديد'},
  ),
  MockProduct(
    id: 'p22',
    title: 'خدمة تصليح هواتف في المنزل #22',
    sellerId: 'demo_fatma',
    sellerName: 'فاطمة',
    price: 0,
    images: const [
      'https://picsum.photos/600/800?31',
      'https://picsum.photos/600/800?131'
    ],
    wilaya: 'نواذيبو',
    moughataa: 'الرياض',
    neighborhood: 'الرياض 2',
    phone: '+222 35 77 00 11',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 3, hours: 15)),
    category: 'services',
    subCategory: 'repair',
    attrs: const {'type': 'تصليح', 'condition': 'غير محدد'},
  ),
  MockProduct(
    id: 'p23',
    title: 'خدمة توصيل داخل نواكشوط #23',
    sellerId: 'demo_mohamed',
    sellerName: 'محمد',
    price: 0,
    images: const [
      'https://picsum.photos/600/800?32',
      'https://picsum.photos/600/800?132'
    ],
    wilaya: 'ألاك',
    moughataa: 'دار النعيم',
    neighborhood: 'الميناء',
    phone: '+222 37 88 99 00',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 4, hours: 18)),
    category: 'services',
    subCategory: 'transport',
    attrs: const {'type': 'نقل', 'condition': 'غير محدد'},
  ),
  MockProduct(
    id: 'p24',
    title: 'مطلوب عامل مبيعات (دوام كامل) #24',
    sellerId: 'demo_hamza',
    sellerName: 'حمزة',
    price: 0,
    images: const [
      'https://picsum.photos/600/800?33',
      'https://picsum.photos/600/800?133'
    ],
    wilaya: 'كيفه',
    moughataa: 'لكصر',
    neighborhood: 'السويسي',
    phone: '+222 44 12 34 56',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 5, hours: 21)),
    category: 'jobs',
    subCategory: 'jobs',
    attrs: const {'condition': 'غير محدد'},
  ),
  MockProduct(
    id: 'p25',
    title: 'هاتف iPhone 13 Pro #25',
    sellerId: 'demo_ahmed',
    sellerName: 'أحمد',
    price: 45000,
    images: const [
      'https://picsum.photos/600/800?34',
      'https://picsum.photos/600/800?134'
    ],
    wilaya: 'نواكشوط',
    moughataa: 'تفرغ زينه',
    neighborhood: 'حي S',
    phone: '+222 34 11 22 33',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 6, hours: 0)),
    category: 'electronics',
    subCategory: 'phones',
    attrs: const {
      'type': 'iPhone',
      'storage': '256GB',
      'color': 'أسود',
      'condition': 'مستعمل'
    },
  ),
  MockProduct(
    id: 'p26',
    title: 'Samsung Galaxy A32 بحالة ممتازة #26',
    sellerId: 'demo_mariem',
    sellerName: 'مريم',
    price: 4500,
    images: const [
      'https://picsum.photos/600/800?35',
      'https://picsum.photos/600/800?135'
    ],
    wilaya: 'نواذيبو',
    moughataa: 'الرياض',
    neighborhood: 'الرياض 2',
    phone: '+222 33 12 45 67',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: true,
    warrantyValue: 12,
    warrantyUnit: 'months',
    warrantyType: 'seller',
    publishedAt: DateTime.now().subtract(Duration(days: 7, hours: 3)),
    category: 'electronics',
    subCategory: 'phones',
    attrs: const {
      'type': 'Samsung Galaxy',
      'storage': '128GB',
      'color': 'أبيض',
      'condition': 'مستعمل'
    },
  ),
  MockProduct(
    id: 'p27',
    title: 'Laptop Dell i5 8GB RAM #27',
    sellerId: 'demo_sidi',
    sellerName: 'سيدي',
    price: 18000,
    images: const [
      'https://picsum.photos/600/800?36',
      'https://picsum.photos/600/800?136'
    ],
    wilaya: 'ألاك',
    moughataa: 'دار النعيم',
    neighborhood: 'الميناء',
    phone: '+222 22 11 33 44',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 8, hours: 6)),
    category: 'electronics',
    subCategory: 'computers',
    attrs: const {'type': 'Laptop', 'ram': '8GB', 'condition': 'مستعمل'},
  ),
  MockProduct(
    id: 'p28',
    title: 'شقة للإيجار قرب السوق #28',
    sellerId: 'demo_fatma',
    sellerName: 'فاطمة',
    price: 12000,
    images: const [
      'https://picsum.photos/600/800?37',
      'https://picsum.photos/600/800?137'
    ],
    wilaya: 'كيفه',
    moughataa: 'لكصر',
    neighborhood: 'السويسي',
    phone: '+222 40 55 66 77',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 0, hours: 9)),
    category: 'real_estate',
    subCategory: 'apartment',
    attrs: const {
      'type': 'شقة',
      'rooms': '3',
      'area': '120',
      'condition': 'غير محدد'
    },
  ),
  MockProduct(
    id: 'p29',
    title: 'أرض للبيع على شارع رئيسي #29',
    sellerId: 'demo_mohamed',
    sellerName: 'محمد',
    price: 65000,
    images: const [
      'https://picsum.photos/600/800?38',
      'https://picsum.photos/600/800?138'
    ],
    wilaya: 'نواكشوط',
    moughataa: 'تفرغ زينه',
    neighborhood: 'حي S',
    phone: '+222 46 77 88 99',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 1, hours: 12)),
    category: 'real_estate',
    subCategory: 'land',
    attrs: const {'type': 'أرض تجارية', 'condition': 'غير محدد'},
  ),
  MockProduct(
    id: 'p30',
    title: 'Toyota Corolla 2014 نظيفة #30',
    sellerId: 'demo_hamza',
    sellerName: 'حمزة',
    price: 220000,
    images: const [
      'https://picsum.photos/600/800?39',
      'https://picsum.photos/600/800?139'
    ],
    wilaya: 'نواذيبو',
    moughataa: 'الرياض',
    neighborhood: 'الرياض 2',
    phone: '+222 36 10 20 30',
    allowWhatsApp: true,
    allowCall: true,
    hasWarranty: false,
    warrantyValue: null,
    warrantyUnit: null,
    warrantyType: null,
    publishedAt: DateTime.now().subtract(Duration(days: 2, hours: 15)),
    category: 'vehicles',
    subCategory: 'cars',
    attrs: const {
      'type': 'Toyota',
      'year': '2014',
      'fuel': 'بنزين',
      'gear': 'أوتوماتيك',
      'condition': 'مستعمل'
    },
  ),
];
