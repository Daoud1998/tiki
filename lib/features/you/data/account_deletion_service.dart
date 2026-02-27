import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Result wrapper so UI can show a friendly message.
class AccountDeletionResult {
  const AccountDeletionResult({required this.ok, this.message});
  final bool ok;
  final String? message;
}

/// "Soft" account deletion:
/// - Deletes the Firebase Authentication user.
/// - Does NOT delete Firestore documents.
/// - Scrubs personal fields in users/{uid} and marks isDeleted=true.
///
/// Why this helps:
/// - Avoids long-running Firestore deletions (can appear "stuck").
/// - Still satisfies App Review: user can delete their account, and personal
///   data is removed/anonymized.
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
      // 1) Scrub personal data in Firestore (best-effort, no deletes).
      await _softScrubUser(uid);

      // 2) Optional: scrub phone from listings but keep content.
      // Comment this out if you prefer not to touch listings.
      await _scrubListings(uid);

      // 3) Delete Auth user.
      try {
        // Add a timeout so UI never stays loading forever.
        await user.delete().timeout(const Duration(seconds: 20));
      } on TimeoutException {
        return const AccountDeletionResult(
          ok: false,
          message: 'Delete request timed out. Please check your internet and try again.',
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          return const AccountDeletionResult(
            ok: false,
            message: 'Please sign out and sign in again, then retry deleting your account.',
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

  static Future<void> _softScrubUser(String uid) async {
    final ref = _db.collection('users').doc(uid);
    try {
      await ref.set({
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        // Remove / blank PII fields commonly used in this app.
        'name': 'Deleted user',
        'email': FieldValue.delete(),
        'phone': FieldValue.delete(),
        'phoneE164': FieldValue.delete(),
        'photoUrl': FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best effort only.
    }
  }

  static Future<void> _scrubListings(String uid) async {
    try {
      final q = await _db.collection('products').where('sellerId', isEqualTo: uid).limit(200).get();
      for (final doc in q.docs) {
        try {
          await doc.reference.update({
            'phone': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {
          // ignore
        }
      }
    } catch (_) {
      // ignore
    }
  }
}
