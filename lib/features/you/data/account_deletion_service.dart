import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Result wrapper so UI can show a friendly message.
class AccountDeletionResult {
  const AccountDeletionResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

/// Account deletion policy (soft delete in Firestore + hard delete in Auth).
///
/// What this does:
/// - Keeps Firestore documents (NO Firestore deletes).
/// - Scrubs personal fields from the user profile and marks it as deleted.
/// - Marks the user's listings as deleted and removes phone from them.
/// - Revokes notification tokens (marks inactive) so you can stop sending pushes.
/// - Deletes the Firebase Auth user (so the account is deleted).
///
/// Note:
/// - `FirebaseAuth.currentUser.delete()` may require a recent sign-in.
///   If it fails with "requires-recent-login", ask the user to sign out/in then retry.
class AccountDeletionService {
  static final _db = FirebaseFirestore.instance;

  static Future<AccountDeletionResult> deleteCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const AccountDeletionResult(ok: false, message: 'Not signed in');
    }

    final uid = user.uid.trim();
    if (uid.isEmpty) {
      return const AccountDeletionResult(ok: false, message: 'Invalid user');
    }

    try {
      // 1) Mark listings as deleted + remove phone/contact fields.
      await _scrubListings(uid);

      // 2) Scrub profile doc (keep doc, remove personal fields).
      await _scrubUserProfile(uid);

      // 3) Mark support tickets / KYC docs as deleted (keep docs).
      await _markDocDeleted(_db.collection('supportTickets').doc(uid));
      await _markDocDeleted(_db.collection('kyc_requests').doc(uid), extra: {'status': 'deleted'});
      await _markDocDeleted(_db.collection('kyc_waitlist').doc(uid));

      // 4) Revoke notification tokens (keep docs; note: token may be in docId).
      await _markCollectionDocs(
        _db.collection('user_devices').doc(uid).collection('tokens'),
        {
          'active': false,
          'revokedAt': FieldValue.serverTimestamp(),
        },
      );

      // 5) Mark inbox items as read (rules allow only read-related fields).
      await _markCollectionDocs(
        _db.collection('user_inbox').doc(uid).collection('items'),
        {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      // 6) Delete Auth user (hard delete).
      try {
        await user.delete();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          return const AccountDeletionResult(
            ok: false,
            message: 'Please sign in again, then retry deleting your account.',
          );
        }
        return AccountDeletionResult(ok: false, message: e.message ?? e.code);
      }

      await FirebaseAuth.instance.signOut();
      return const AccountDeletionResult(ok: true);
    } catch (e) {
      return AccountDeletionResult(ok: false, message: e.toString());
    }
  }

  static Future<void> _scrubListings(String uid) async {
    // Best effort: mark products as deleted and remove phone field.
    final q = await _db.collection('products').where('sellerId', isEqualTo: uid).get();
    for (final doc in q.docs) {
      try {
        await doc.reference.update({
          'status': 'deleted',
          'phone': FieldValue.delete(),
          'phoneE164': FieldValue.delete(),
          'contactPhone': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Ignore individual failures.
      }
    }
  }

  static Future<void> _scrubUserProfile(String uid) async {
    final ref = _db.collection('users').doc(uid);
    try {
      await ref.set({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        // Remove common personal fields if present.
        'displayName': FieldValue.delete(),
        'name': FieldValue.delete(),
        'email': FieldValue.delete(),
        'phone': FieldValue.delete(),
        'phoneE164': FieldValue.delete(),
        'photoUrl': FieldValue.delete(),
        'photoURL': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best effort.
    }
  }

  static Future<void> _markDocDeleted(
    DocumentReference<Map<String, dynamic>> doc, {
    Map<String, Object?> extra = const {},
  }) async {
    try {
      final snap = await doc.get();
      if (!snap.exists) return;
      await doc.set({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        ...extra,
      }, SetOptions(merge: true));
    } catch (_) {
      // Best effort.
    }
  }

  static Future<void> _markCollectionDocs(
    CollectionReference<Map<String, dynamic>> col,
    Map<String, Object?> patch,
  ) async {
    // Update docs in small batches.
    while (true) {
      final snap = await col.limit(50).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.set(d.reference, patch, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }
}
