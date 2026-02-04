// support_repository.dart
// Support tickets + messages synced to Firestore.
// Suggested path in your app: lib/core/data/support_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SupportTicketStatus {
  static const String open = 'open';
  static const String reviewing = 'reviewing';
  static const String resolved = 'resolved';
}

class SupportMessage {
  final String id;
  final String senderId;
  final bool fromAdmin;
  final String text;
  final DateTime? createdAt;

  SupportMessage({
    required this.id,
    required this.senderId,
    required this.fromAdmin,
    required this.text,
    required this.createdAt,
  });

  factory SupportMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    final ts = d['createdAt'];
    return SupportMessage(
      id: doc.id,
      senderId: (d['senderId'] ?? '').toString(),
      fromAdmin: (d['fromAdmin'] ?? false) == true,
      text: (d['text'] ?? '').toString(),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class SupportTicket {
  final String id; // ticketId (we use uid by default)
  final String userId;
  final String status;
  final String? lastMessageText;
  final DateTime? lastMessageAt;

  SupportTicket({
    required this.id,
    required this.userId,
    required this.status,
    this.lastMessageText,
    this.lastMessageAt,
  });

  factory SupportTicket.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? <String, dynamic>{};
    final ts = d['lastMessageAt'];
    return SupportTicket(
      id: doc.id,
      userId: (d['userId'] ?? '').toString(),
      status: (d['status'] ?? SupportTicketStatus.open).toString(),
      lastMessageText: (d['lastMessageText'] ?? '').toString().trim().isEmpty
          ? null
          : d['lastMessageText'].toString(),
      lastMessageAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

class SupportRepository {
  SupportRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get _uid {
    final u = _auth.currentUser;
    if (u == null) {
      throw StateError('User must be signed in to use SupportRepository.');
    }
    return u.uid;
  }

  CollectionReference<Map<String, dynamic>> get _tickets =>
      _db.collection('supportTickets');

  DocumentReference<Map<String, dynamic>> ticketRef(String ticketId) =>
      _tickets.doc(ticketId);

  CollectionReference<Map<String, dynamic>> messagesCol(String ticketId) =>
      ticketRef(ticketId).collection('messages');

  /// Default ticket id is the user's uid (simple and stable).
  Future<String> ensureMyTicket({Map<String, dynamic>? profileHint}) async {
    final uid = _uid;
    final ref = ticketRef(uid);
    final snap = await ref.get();
    if (snap.exists) return uid;

    await ref.set({
      'userId': uid,
      'status': SupportTicketStatus.open,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageText': null,
      'profile': profileHint ?? null,
    }, SetOptions(merge: true));

    return uid;
  }

  Stream<SupportTicket?> watchMyTicket() {
    final uid = _uid;
    return ticketRef(uid)
        .snapshots()
        .map((d) => d.exists ? SupportTicket.fromDoc(d) : null);
  }

  Stream<List<SupportMessage>> watchMyMessages({int limit = 200}) {
    final uid = _uid;
    return messagesCol(uid)
        .orderBy('createdAt', descending: false)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map((d) => SupportMessage.fromDoc(d))
            .toList(growable: false));
  }

  Future<void> sendMyMessage(String text, {Map<String, dynamic>? extra}) async {
    final uid = _uid;
    final msg = text.trim();
    if (msg.isEmpty) return;

    // Ensure ticket exists
    await ensureMyTicket();

    final mref = messagesCol(uid).doc();
    await _db.runTransaction((tx) async {
      tx.set(mref, {
        'senderId': uid,
        'fromAdmin': false,
        'text': msg,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAtMs': DateTime.now().millisecondsSinceEpoch,
        'extra': extra,
      });

      tx.set(
          ticketRef(uid),
          {
            'userId': uid,
            'status': SupportTicketStatus.open,
            'lastMessageAt': FieldValue.serverTimestamp(),
            'lastMessageText': msg,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    });
  }

  /// Optional admin helper: send message to a ticket as admin.
  /// Note: your security rules must allow admins (allowlist) to write these.
  Future<void> adminSendMessage({
    required String ticketId,
    required String adminId,
    required String text,
  }) async {
    final msg = text.trim();
    if (msg.isEmpty) return;

    final mref = messagesCol(ticketId).doc();
    await _db.runTransaction((tx) async {
      tx.set(mref, {
        'senderId': adminId,
        'fromAdmin': true,
        'text': msg,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAtMs': DateTime.now().millisecondsSinceEpoch,
      });

      tx.set(
          ticketRef(ticketId),
          {
            'lastMessageAt': FieldValue.serverTimestamp(),
            'lastMessageText': msg,
            'status': SupportTicketStatus.reviewing,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    });
  }

  /// Optional admin helper: list recent tickets.
  Stream<List<SupportTicket>> watchRecentTickets({int limit = 100}) {
    return _tickets
        .orderBy('lastMessageAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map((d) => SupportTicket.fromDoc(d))
            .toList(growable: false));
  }
}
