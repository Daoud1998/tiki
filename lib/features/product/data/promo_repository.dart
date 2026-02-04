import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final promoRepositoryProvider = Provider<PromoRepository>((ref) {
  return PromoRepository();
});

/// Promo plans live in Firestore at: `promo_plans/{planId}`.
///
/// Recommended structure for the VIP plan:
///
/// ```
/// promo_plans/vip {
///   "type": "vip",
///   "title": "VIP",
///   "durations": [
///     {"days": 1,  "priceMru": 1000},
///     {"days": 3,  "priceMru": 2000},
///     {"days": 7,  "priceMru": 4000},
///     {"days": 15, "priceMru": 8000},
///     {"days": 30, "priceMru": 14000}
///   ],
///   "active": true,
///   "updatedAt": <timestamp>
/// }
/// ```
///
/// Requests live in: `promo_requests/{requestId}`.
class PromoRepository {
  PromoRepository({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _plans =>
      _db.collection('promo_plans');

  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('promo_requests');

  /// Optional helper: create the default VIP plan document if missing.
  ///
  /// You can run this once (admin-only) so the app always finds a plan.
  /// In production, it's normal to edit pricing directly from Firestore.
  Future<void> seedVipPlanIfMissing() async {
    final ref = _plans.doc('vip');
    final doc = await ref.get(const GetOptions(source: Source.server));
    if (doc.exists) return;

    await ref.set({
      'type': 'vip',
      'title': 'VIP',
      'durations': [
        {'days': 1, 'priceMru': 1000},
        {'days': 3, 'priceMru': 2000},
        {'days': 7, 'priceMru': 4000},
        {'days': 15, 'priceMru': 8000},
        {'days': 30, 'priceMru': 14000},
      ],
      'active': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: false));
  }

  Stream<PromoPlan?> watchVipPlan() {
    return _plans.doc('vip').snapshots().map((doc) {
      if (!doc.exists) return null;
      return PromoPlan.fromDoc(doc);
    });
  }

  Future<PromoPlan?> getVipPlan({bool serverOnly = false}) async {
    final opt = serverOnly
        ? const GetOptions(source: Source.server)
        : const GetOptions(source: Source.serverAndCache);
    final doc = await _plans.doc('vip').get(opt);
    if (!doc.exists) return null;
    return PromoPlan.fromDoc(doc);
  }

  /// Creates a VIP promo request for a seller's product.
  ///
  /// Preferred path: calls the Cloud Function `requestVipPromo` to validate
  /// the plan/price on the server and avoid client tampering.
  ///
  /// Fallback: writes a pending request directly to Firestore.
  Future<String> requestVipPromo({
    required String productId,
    required int days,
    int? expectedPriceMru,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not signed in');
    }

    // 1) Try Cloud Function.
    try {
      final callable = _functions.httpsCallable('requestVipPromo');
      final res = await callable.call(<String, dynamic>{
        'productId': productId,
        'days': days,
        'expectedPriceMru': expectedPriceMru,
      });
      final data = (res.data as Map?)?.cast<String, dynamic>();
      final id = data?['requestId'] as String?;
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {
      // ignore and fall back
    }

    // 2) Firestore fallback (server should still approve via admin).
    final doc = _requests.doc();
    await doc.set(<String, dynamic>{
      'userId': uid,
      'productId': productId,
      'type': 'vip',
      'days': days,
      if (expectedPriceMru != null) 'expectedPriceMru': expectedPriceMru,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Stream<List<PromoRequest>> watchMyPromoRequests({int limit = 50}) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream<List<PromoRequest>>.empty();

    return _requests
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => PromoRequest.fromDoc(d)).toList());
  }
}

class PromoPlan {
  PromoPlan({
    required this.id,
    required this.type,
    required this.title,
    required this.active,
    required this.durations,
  });

  final String id;
  final String type;
  final String title;
  final bool active;
  final List<PromoDuration> durations;

  static PromoPlan fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final raw = (data['durations'] as List?) ?? const <dynamic>[];
    final durations = raw
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .map(PromoDuration.fromMap)
        .toList();

    durations.sort((a, b) => a.days.compareTo(b.days));

    return PromoPlan(
      id: doc.id,
      type: (data['type'] as String?) ?? doc.id,
      title: (data['title'] as String?) ?? 'VIP',
      active: (data['active'] as bool?) ?? true,
      durations: durations,
    );
  }
}

class PromoDuration {
  PromoDuration({required this.days, required this.priceMru});

  final int days;
  final int priceMru;

  static PromoDuration fromMap(Map<String, dynamic> map) {
    final days = (map['days'] as num?)?.toInt() ?? 0;
    final price = (map['priceMru'] as num?)?.toInt() ?? 0;
    return PromoDuration(days: days, priceMru: price);
  }
}

class PromoRequest {
  PromoRequest({
    required this.id,
    required this.userId,
    required this.productId,
    required this.type,
    required this.days,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String productId;
  final String type;
  final int days;
  final String status;
  final DateTime? createdAt;

  static PromoRequest fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return PromoRequest(
      id: doc.id,
      userId: (data['userId'] as String?) ?? '',
      productId: (data['productId'] as String?) ?? '',
      type: (data['type'] as String?) ?? 'vip',
      days: (data['days'] as num?)?.toInt() ?? 0,
      status: (data['status'] as String?) ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
