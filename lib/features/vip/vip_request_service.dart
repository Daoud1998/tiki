import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VipRequestService {
  VipRequestService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  /// Create a VIP request for a specific product.
  ///
  /// Writes to: vip_requests/{autoId}
  Future<void> requestProductVip({
    required String productId,
    String? planId,
    int? days,
    int? rank,
    String? note,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not signed in');
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await _db.collection('vip_requests').add({
      'uid': uid,
      'productId': productId,
      'type': 'productVip',
      'status': 'pending',
      'planId': (planId ?? '').trim().isEmpty ? null : planId!.trim(),
      'days': days,
      'requestedRank': rank ?? 1,
      'note': (note ?? '').trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtMs': nowMs,
    });
  }
}
