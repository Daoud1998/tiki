import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True when the current signed-in user is allowlisted as an Admin.
///
/// Firestore rule expects a document to exist at: /admins/{uid}
final isAdminProvider = StreamProvider<bool>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || uid.trim().isEmpty) return Stream.value(false);

  final doc = FirebaseFirestore.instance.collection('admins').doc(uid.trim());
  return doc.snapshots().map((s) => s.exists).handleError((_) => false);
});
