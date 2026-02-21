import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Result wrapper so UI can show a friendly message.
class AccountDeletionResult {
  const AccountDeletionResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

/// Deletes (or scrubs) user data and then deletes the Firebase Auth account.
///
/// Notes:
/// - `FirebaseAuth.currentUser.delete()` may require a recent sign-in.
///   For App Review, the reviewer usually signs in immediately before testing,
///   so deletion should succeed.
/// - For real users, if deletion fails with "requires-recent-login", ask them
///   to sign out/in and try again.
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
      // 1) Hide/delete the user's listings (keep content but remove personal phone).
      await _scrubListings(uid);

      // 2) Delete per-user tokens and inbox items.
      await _deleteCollection(_db.collection('user_devices').doc(uid).collection('tokens'));
      await _deleteCollection(_db.collection('user_inbox').doc(uid).collection('items'));

      // 3) Delete support ticket + messages (ticketId == uid).
      await _deleteCollection(_db.collection('supportTickets').doc(uid).collection('messages'));
      await _safeDelete(_db.collection('supportTickets').doc(uid));

      // 4) Delete KYC docs (if any).
      await _safeDelete(_db.collection('kyc_requests').doc(uid));
      await _safeDelete(_db.collection('kyc_waitlist').doc(uid));

      // 5) Delete user profile doc.
      await _safeDelete(_db.collection('users').doc(uid));

      // 6) Delete Auth user.
      try {
        await user.delete();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          // User data already scrubbed; ask them to re-login then try again.
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
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Ignore individual failures.
      }
    }
  }

  static Future<void> _deleteCollection(CollectionReference<Map<String, dynamic>> col) async {
    // Delete docs in small batches.
    while (true) {
      final snap = await col.limit(50).get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  static Future<void> _safeDelete(DocumentReference<Map<String, dynamic>> doc) async {
    try {
      await doc.delete();
    } catch (_) {
      // Best effort.
    }
  }
}
