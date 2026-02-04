import 'package:flutter/foundation.dart';

enum ServiceReceiptKind {
  /// VIP promotion for a product listing (seller pays to boost a product).
  productVip,

  /// VIP promotion for a promo-ad/banner (seller pays for a promo slot).
  promoAdVip,

  /// Generic activation (reserved for later).
  productActivation,
}

enum ServiceReceiptStatus {
  pending,
  active,
  expired,
  cancelled,
  failed,
}

@immutable
class ServiceReceipt {
  const ServiceReceipt({
    required this.id,
    required this.kind,
    required this.status,
    required this.amountMru,
    required this.createdAt,
    this.transactionId,
    this.subjectId,
    this.subjectTitleAr,
    this.subjectTitleFr,
    this.subjectTitleEn,
    this.startsAt,
    this.endsAt,
    this.meta = const <String, dynamic>{},
  });

  final String id;
  final ServiceReceiptKind kind;
  final ServiceReceiptStatus status;

  /// Amount in MRU.
  final int amountMru;

  /// Bankily TX id or any payment reference.
  final String? transactionId;

  /// Associated entity id (product id, promo ad id, ...).
  final String? subjectId;

  /// Optional localized subject titles.
  final String? subjectTitleAr;
  final String? subjectTitleFr;
  final String? subjectTitleEn;

  /// Service time window.
  final DateTime? startsAt;
  final DateTime? endsAt;

  final DateTime createdAt;

  /// Extra data, schema-flexible (e.g. {"pkgId": "vip_3d"}).
  final Map<String, dynamic> meta;

  bool get hasWindow => startsAt != null && endsAt != null;

  Duration? get remaining {
    final e = endsAt;
    if (e == null) return null;
    return e.difference(DateTime.now());
  }

  ServiceReceipt copyWith({
    ServiceReceiptStatus? status,
    int? amountMru,
    String? transactionId,
    String? subjectId,
    String? subjectTitleAr,
    String? subjectTitleFr,
    String? subjectTitleEn,
    DateTime? startsAt,
    DateTime? endsAt,
    DateTime? createdAt,
    Map<String, dynamic>? meta,
  }) {
    return ServiceReceipt(
      id: id,
      kind: kind,
      status: status ?? this.status,
      amountMru: amountMru ?? this.amountMru,
      transactionId: transactionId ?? this.transactionId,
      subjectId: subjectId ?? this.subjectId,
      subjectTitleAr: subjectTitleAr ?? this.subjectTitleAr,
      subjectTitleFr: subjectTitleFr ?? this.subjectTitleFr,
      subjectTitleEn: subjectTitleEn ?? this.subjectTitleEn,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      createdAt: createdAt ?? this.createdAt,
      meta: meta ?? this.meta,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'kind': kind.name,
      'status': status.name,
      'amountMru': amountMru,
      'transactionId': transactionId,
      'subjectId': subjectId,
      'subjectTitleAr': subjectTitleAr,
      'subjectTitleFr': subjectTitleFr,
      'subjectTitleEn': subjectTitleEn,
      'startsAt': startsAt?.toIso8601String(),
      'endsAt': endsAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'meta': meta,
    };
  }

  static ServiceReceipt? tryFromJson(Object? json) {
    if (json is! Map) return null;
    String s(Object? v) => (v ?? '').toString();

    final id = s(json['id']).trim();
    if (id.isEmpty) return null;

    final kindStr = s(json['kind']).trim();
    final statusStr = s(json['status']).trim();

    final kind = ServiceReceiptKind.values
        .cast<ServiceReceiptKind?>()
        .firstWhere((e) => e?.name == kindStr, orElse: () => null);
    final status = ServiceReceiptStatus.values
        .cast<ServiceReceiptStatus?>()
        .firstWhere((e) => e?.name == statusStr, orElse: () => null);

    if (kind == null || status == null) return null;

    DateTime? dt(Object? v) {
      final t = s(v).trim();
      if (t.isEmpty) return null;
      return DateTime.tryParse(t);
    }

    int i(Object? v) {
      if (v is num) return v.toInt();
      return int.tryParse(s(v)) ?? 0;
    }

    final metaAny = json['meta'];
    final meta = (metaAny is Map)
        ? metaAny.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};

    return ServiceReceipt(
      id: id,
      kind: kind,
      status: status,
      amountMru: i(json['amountMru']),
      transactionId: s(json['transactionId']).trim().isEmpty
          ? null
          : s(json['transactionId']).trim(),
      subjectId: s(json['subjectId']).trim().isEmpty
          ? null
          : s(json['subjectId']).trim(),
      subjectTitleAr: s(json['subjectTitleAr']).trim().isEmpty
          ? null
          : s(json['subjectTitleAr']).trim(),
      subjectTitleFr: s(json['subjectTitleFr']).trim().isEmpty
          ? null
          : s(json['subjectTitleFr']).trim(),
      subjectTitleEn: s(json['subjectTitleEn']).trim().isEmpty
          ? null
          : s(json['subjectTitleEn']).trim(),
      startsAt: dt(json['startsAt']),
      endsAt: dt(json['endsAt']),
      createdAt: dt(json['createdAt']) ?? DateTime.now(),
      meta: meta,
    );
  }
}
