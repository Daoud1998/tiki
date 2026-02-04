// moderation_repository.dart
// Sync seller blocks + user reports to Firestore.
// Suggested path in your app: lib/core/data/moderation_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Target types for reports.
class ReportTargetType {
  static const String product = 'product';
  static const String seller = 'seller';
  static const String message = 'message';
}

/// Lightweight block entry.
class BlockEntry {
  final String
      sellerKey; // usually sellerId (UID) or phone key if you still use phone keys.
  final String? sellerId;
  final String? sellerPhone;
  final DateTime? createdAt;

  BlockEntry({
    required this.sellerKey,
    this.sellerId,
    this.sellerPhone,
    this.createdAt,
  });

  factory BlockEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    final ts = d['createdAt'];
    return BlockEntry(
      sellerKey: doc.id,
      sellerId: (d['sellerId'] ?? '').toString().trim().isEmpty
          ? null
          : d['sellerId'].toString(),
      sellerPhone: (d['sellerPhone'] ?? '').toString().trim().isEmpty
          ? null
          : d['sellerPhone'].toString(),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// Lightweight report entry.
class ReportEntry {
  final String id;
  final String reporterId;
  final String targetType;
  final String? productId;
  final String? sellerId;
  final String? sellerPhone;
  final String reasonId;
  final String? note;
  final String status;
  final DateTime? createdAt;

  ReportEntry({
    required this.id,
    required this.reporterId,
    required this.targetType,
    required this.reasonId,
    required this.status,
    this.productId,
    this.sellerId,
    this.sellerPhone,
    this.note,
    this.createdAt,
  });

  factory ReportEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    final ts = d['createdAt'];
    return ReportEntry(
      id: doc.id,
      reporterId: (d['reporterId'] ?? '').toString(),
      targetType: (d['targetType'] ?? '').toString(),
      productId: (d['productId'] ?? '').toString().trim().isEmpty
          ? null
          : d['productId'].toString(),
      sellerId: (d['sellerId'] ?? '').toString().trim().isEmpty
          ? null
          : d['sellerId'].toString(),
      sellerPhone: (d['sellerPhone'] ?? '').toString().trim().isEmpty
          ? null
          : d['sellerPhone'].toString(),
      reasonId: (d['reasonId'] ?? '').toString(),
      note: (d['note'] ?? '').toString().trim().isEmpty
          ? null
          : d['note'].toString(),
      status: (d['status'] ?? 'open').toString(),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class ModerationRepository {
  ModerationRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _uid {
    final u = _auth.currentUser;
    if (u == null) {
      throw StateError('User must be signed in to use ModerationRepository.');
    }
    return u.uid;
  }

  /// Collection: users/{uid}/blocks/{sellerKey}
  CollectionReference<Map<String, dynamic>> _blocksCol(String uid) =>
      _db.collection('users').doc(uid).collection('blocks');

  /// Collection: reports/{reportId}
  CollectionReference<Map<String, dynamic>> get _reportsCol =>
      _db.collection('reports');

  /// Blocks a seller by key.
  /// Prefer passing sellerId (UID). If your project still uses phone as the key,
  /// pass sellerKey = phone and store sellerPhone too.
  Future<void> blockSeller({
    required String sellerKey,
    String? sellerId,
    String? sellerPhone,
    String? source, // screen/page name
  }) async {
    final uid = _uid;
    final key = sellerKey.trim();
    if (key.isEmpty) return;

    await _blocksCol(uid).doc(key).set({
      'sellerKey': key,
      'sellerId': (sellerId ?? '').trim().isEmpty ? null : sellerId!.trim(),
      'sellerPhone':
          (sellerPhone ?? '').trim().isEmpty ? null : sellerPhone!.trim(),
      'blockedBy': uid,
      'source': (source ?? '').trim().isEmpty ? null : source!.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> unblockSeller(String sellerKey) async {
    final uid = _uid;
    final key = sellerKey.trim();
    if (key.isEmpty) return;
    await _blocksCol(uid).doc(key).delete();
  }

  /// Checks if a seller is blocked.
  /// If you support both sellerId and sellerPhone, call twice with both keys.
  Future<bool> isBlocked(String sellerKey) async {
    final uid = _uid;
    final key = sellerKey.trim();
    if (key.isEmpty) return false;
    final doc = await _blocksCol(uid).doc(key).get();
    return doc.exists;
  }

  /// Stream of blocked entries (real-time).
  Stream<List<BlockEntry>> watchBlocks() {
    final uid = _uid;
    return _blocksCol(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => BlockEntry.fromDoc(d)).toList(growable: false));
  }

  /// Stream of blocked keys only.
  Stream<Set<String>> watchBlockedKeys() {
    return watchBlocks().map((list) => list.map((e) => e.sellerKey).toSet());
  }

  /// Creates a report in `reports` for admin review.
  Future<String> submitReport({
    required String targetType,
    String? productId,
    String? sellerId,
    String? sellerPhone,
    required String reasonId,
    String? note,
    Map<String, dynamic>? extra,
  }) async {
    final uid = _uid;

    final doc = _reportsCol.doc();
    final payload = <String, dynamic>{
      'reporterId': uid,
      'targetType': targetType,
      'productId': (productId ?? '').trim().isEmpty ? null : productId!.trim(),
      'sellerId': (sellerId ?? '').trim().isEmpty ? null : sellerId!.trim(),
      'sellerPhone':
          (sellerPhone ?? '').trim().isEmpty ? null : sellerPhone!.trim(),
      'reasonId': reasonId.trim(),
      'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      'status': 'open',
      // Keep both a server timestamp (for audit) and a numeric ms field (for ordering).
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
      'clientCreatedAtMs': DateTime.now().millisecondsSinceEpoch,
    };

    if (extra != null && extra.isNotEmpty) {
      payload['extra'] = extra;
    }

    await doc.set(payload);
    return doc.id;
  }

  /// Watch reports created by current user (for a "My reports" screen).
  /// If Firestore asks for an index, create it via the Console link.
  Stream<List<ReportEntry>> watchMyReports({int limit = 50}) {
    final uid = _uid;
    return _reportsCol
        .where('reporterId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => ReportEntry.fromDoc(d)).toList(growable: false));
  }
}
