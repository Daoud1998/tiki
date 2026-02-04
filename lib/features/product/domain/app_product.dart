import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore-backed product model.
/// Designed to be API-compatible with the old MockProduct UI usage.
class AppProduct {
  AppProduct({
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
    this.videoUrl,
    this.status = 'active',
    this.oldPrice,
    this.phone,
    this.allowWhatsApp = true,
    this.allowCall = true,
    this.hasWarranty = false,
    this.warrantyValue,
    this.warrantyUnit,
    this.warrantyType,
    List<String>? searchTokens,
    Map<String, String>? attrs,
    this.viewCount = 0,
  })  : images = List<String>.unmodifiable(images ?? const <String>[]),
        searchTokens = List<String>.unmodifiable(searchTokens ?? const <String>[]),
        attrs = Map<String, String>.unmodifiable(attrs ?? const <String, String>{});

  final String id;
  final String title;

  final String sellerId;
  final String sellerName;

  final String? subtitle;
  final String? description;
  final String? details;

  final String? category;
  final String? subCategory;

  /// Price in MRU (0 means negotiable / unspecified).
  final int price;
  final int? oldPrice;

  final List<String> images;
  final String? videoUrl;
  String get imageUrl => images.isNotEmpty ? images.first : '';

  final String wilaya;
  final String moughataa;
  final String neighborhood;

  final DateTime publishedAt;

  /// 'active' | 'sold' | 'deleted'
  final String status;

  bool get isSold => status == 'sold';

  final String? phone;
  final bool allowWhatsApp;
  final bool allowCall;

  final bool hasWarranty;
  final int? warrantyValue;
  final String? warrantyUnit;
  final String? warrantyType;

  final List<String> searchTokens;
  final Map<String, String> attrs;

  final int viewCount;

  factory AppProduct.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};

    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is String) {
        return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    int parseInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    List<String> parseList(dynamic v) {
      if (v is List) {
        return v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
      }
      return <String>[];
    }

    Map<String, String> parseAttrs(dynamic v) {
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), (val ?? '').toString()));
      }
      return <String, String>{};
    }

    final images = parseList(d['images']);
    final videoUrlRaw = (d['videoUrl'] ?? d['video'] ?? '').toString().trim();
    final videoUrlValue = videoUrlRaw.isEmpty ? null : videoUrlRaw;
    return AppProduct(
      id: (d['id'] ?? doc.id).toString(),
      title: (d['title'] ?? '').toString(),
      sellerId: (d['sellerId'] ?? 'guest').toString(),
      sellerName: (d['sellerName'] ?? '').toString(),
      price: parseInt(d['price']),
      oldPrice: d.containsKey('oldPrice') ? (parseInt(d['oldPrice'])) : null,
      images: images,
        videoUrl: videoUrlValue,
      wilaya: (d['wilaya'] ?? '').toString(),
      moughataa: (d['moughataa'] ?? '').toString(),
      neighborhood: (d['neighborhood'] ?? '').toString(),
      publishedAt: parseDate(d['publishedAt']),
      subtitle: (d['subtitle'] ?? '').toString().trim().isEmpty ? null : (d['subtitle'] ?? '').toString(),
      description: (d['description'] ?? '').toString().trim().isEmpty ? null : (d['description'] ?? '').toString(),
      details: (d['details'] ?? '').toString().trim().isEmpty ? null : (d['details'] ?? '').toString(),
      category: (d['category'] ?? '').toString().trim().isEmpty ? null : (d['category'] ?? '').toString(),
      subCategory: (d['subCategory'] ?? '').toString().trim().isEmpty ? null : (d['subCategory'] ?? '').toString(),
      status: (d['status'] ?? 'active').toString(),
      phone: (d['phone'] ?? '').toString().trim().isEmpty ? null : (d['phone'] ?? '').toString(),
      allowWhatsApp: (d['allowWhatsApp'] ?? true) == true,
      allowCall: (d['allowCall'] ?? true) == true,
      hasWarranty: (d['hasWarranty'] ?? false) == true,
      warrantyValue: d['warrantyValue'] == null ? null : parseInt(d['warrantyValue']),
      warrantyUnit: (d['warrantyUnit'] ?? '').toString().trim().isEmpty ? null : (d['warrantyUnit'] ?? '').toString(),
      warrantyType: (d['warrantyType'] ?? '').toString().trim().isEmpty ? null : (d['warrantyType'] ?? '').toString(),
      searchTokens: parseList(d['searchTokens']),
      attrs: parseAttrs(d['attrs']),
      viewCount: parseInt(d['viewCount']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'sellerId': sellerId,
      'sellerName': sellerName,
      'subtitle': subtitle,
      'description': description,
      'details': details,
      'category': category,
      'subCategory': subCategory,
      'price': price,
      'oldPrice': oldPrice,
      'images': images,
      'videoUrl': videoUrl,
      'wilaya': wilaya,
      'moughataa': moughataa,
      'neighborhood': neighborhood,
      'publishedAt': Timestamp.fromDate(publishedAt),
      'status': status,
      'phone': phone,
      'allowWhatsApp': allowWhatsApp,
      'allowCall': allowCall,
      'hasWarranty': hasWarranty,
      'warrantyValue': warrantyValue,
      'warrantyUnit': warrantyUnit,
      'warrantyType': warrantyType,
      'searchTokens': searchTokens,
      'attrs': attrs,
      'viewCount': viewCount,
    };
  }


  /// Build from a plain JSON-like map (e.g. from SQLite cache).
  /// Expects the same keys as Firestore documents.
  factory AppProduct.fromMap(Map<String, dynamic> d) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      if (v is String) {
        return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    int parseInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    List<String> parseList(dynamic v) {
      if (v is List) {
        return v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
      }
      return <String>[];
    }

    Map<String, String> parseAttrs(dynamic v) {
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), (val ?? '').toString()));
      }
      return <String, String>{};
    }

    final id = (d['id'] ?? '').toString();
    final images = parseList(d['images']);
    final videoUrlRaw = (d['videoUrl'] ?? d['video'] ?? '').toString().trim();
    final videoUrlValue = videoUrlRaw.isEmpty ? null : videoUrlRaw;

    return AppProduct(
      id: id,
      title: (d['title'] ?? '').toString(),
      sellerId: (d['sellerId'] ?? 'guest').toString(),
      sellerName: (d['sellerName'] ?? '').toString(),
      price: parseInt(d['price']),
      oldPrice: d.containsKey('oldPrice') ? parseInt(d['oldPrice']) : null,
      images: images,
      videoUrl: videoUrlValue,
      wilaya: (d['wilaya'] ?? '').toString(),
      moughataa: (d['moughataa'] ?? '').toString(),
      neighborhood: (d['neighborhood'] ?? '').toString(),
      publishedAt: parseDate(d['publishedAt']),
      subtitle: (d['subtitle'] ?? '').toString().trim().isEmpty ? null : (d['subtitle'] ?? '').toString(),
      description: (d['description'] ?? '').toString().trim().isEmpty ? null : (d['description'] ?? '').toString(),
      details: (d['details'] ?? '').toString().trim().isEmpty ? null : (d['details'] ?? '').toString(),
      category: (d['category'] ?? '').toString().trim().isEmpty ? null : (d['category'] ?? '').toString(),
      subCategory: (d['subCategory'] ?? '').toString().trim().isEmpty ? null : (d['subCategory'] ?? '').toString(),
      status: (d['status'] ?? 'active').toString(),
      phone: (d['phone'] ?? '').toString().trim().isEmpty ? null : (d['phone'] ?? '').toString(),
      allowWhatsApp: (d['allowWhatsApp'] ?? true) == true,
      allowCall: (d['allowCall'] ?? true) == true,
      hasWarranty: (d['hasWarranty'] ?? false) == true,
      warrantyValue: d['warrantyValue'] == null ? null : parseInt(d['warrantyValue']),
      warrantyUnit: (d['warrantyUnit'] ?? '').toString().trim().isEmpty ? null : (d['warrantyUnit'] ?? '').toString(),
      warrantyType: (d['warrantyType'] ?? '').toString().trim().isEmpty ? null : (d['warrantyType'] ?? '').toString(),
      searchTokens: parseList(d['searchTokens']),
      attrs: parseAttrs(d['attrs']),
      viewCount: parseInt(d['viewCount']),
    );
  }
}