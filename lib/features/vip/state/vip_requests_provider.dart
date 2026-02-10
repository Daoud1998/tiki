import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class VipRequest {
  const VipRequest({
    required this.id,
    required this.productId,
    required this.status,
    required this.createdAtMs,
    this.planId,
    this.rejectReason,
  });

  final String id;
  final String productId;
  final String status; // pending | approved | rejected
  final int createdAtMs;
  final String? planId;
  final String? rejectReason;

  factory VipRequest.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse((v ?? '').toString()) ?? 0;
    }

    final createdAtMs = asInt(m['createdAtMs']);
    return VipRequest(
      id: d.id,
      productId: (m['productId'] ?? '').toString(),
      status: (m['status'] ?? '').toString().toLowerCase().trim(),
      createdAtMs: createdAtMs,
      planId: (m['planId'] ?? '').toString().trim().isEmpty
          ? null
          : (m['planId'] ?? '').toString().trim(),
      rejectReason: (m['rejectReason'] ?? m['reason'] ?? '')
              .toString()
              .trim()
              .isEmpty
          ? null
          : (m['rejectReason'] ?? m['reason']).toString().trim(),
    );
  }
}

/// Latest VIP request per product for the current signed-in user.
///
/// We query by uid only (stable + no composite index) and then keep the latest
/// request per product locally.
final myVipRequestsLatestProvider = StreamProvider<Map<String, VipRequest>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || uid.trim().isEmpty) {
    return Stream.value(const <String, VipRequest>{});
  }

  final q = FirebaseFirestore.instance
      .collection('vip_requests')
      .where('uid', isEqualTo: uid)
      .limit(200);

  return q.snapshots().map((snap) {
    final latest = <String, VipRequest>{};
    for (final d in snap.docs) {
      final m = d.data();
      final type = (m['type'] ?? '').toString().toLowerCase().trim();
      if (type.isNotEmpty && type != 'productvip') continue;
      final r = VipRequest.fromDoc(d);
      if (r.productId.trim().isEmpty) continue;
      final prev = latest[r.productId];
      if (prev == null || r.createdAtMs >= prev.createdAtMs) {
        latest[r.productId] = r;
      }
    }
    return latest;
  });
});
