import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/state/auth_state.dart' show authControllerProvider;
import '../domain/kyc_request.dart';

class KycRepository {
  const KycRepository();

  DocumentReference<Map<String, dynamic>> _reqDoc(String userId) {
    return FirebaseFirestore.instance.collection('kyc_requests').doc(userId);
  }

  /// Watch the current user's request.
  Stream<KycRequest?> watchRequest(String userId) {
    try {
      return _reqDoc(userId).snapshots().map((snap) {
        final data = snap.data();
        if (data == null) return null;
        return KycRequest.fromMap(data, userId: snap.id);
      });
    } catch (_) {
      // Firebase not ready / permissions / offline
      return const Stream<KycRequest?>.empty();
    }
  }

  /// Join a waitlist (best-effort).
  Future<void> joinWaitlist(String userId) async {
    try {
      await FirebaseFirestore.instance
          .collection('kyc_waitlist')
          .doc(userId)
          .set(
        <String, dynamic>{
          'userId': userId,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // ignore
    }
  }

  Future<String> _uploadXFile({
    required String path,
    required XFile file,
  }) async {
    final ref = FirebaseStorage.instance.ref(path);

    // Put bytes to keep implementation simple across platforms.
    final Uint8List bytes = await file.readAsBytes();
    await ref.putData(bytes);

    return ref.getDownloadURL();
  }

  /// Submit a verification request with ID images.
  ///
  /// Writes a single doc at `kyc_requests/{userId}` (one active request per user).
  Future<void> submitIdRequest({
    required String userId,
    required String statusWhenSubmitted,
    String? fullName,
    String? nationalId,
    String? phoneE164,
    String? notes,
    required String documentType,
    required XFile document,
    XFile? documentBack,
    required XFile selfie,
  }) async {
    try {
      final idFrontUrl = await _uploadXFile(
        path: 'kyc/$userId/id_front.jpg',
        file: document,
      );

      String? idBackUrl;
      if (documentBack != null) {
        idBackUrl = await _uploadXFile(
          path: 'kyc/$userId/id_back.jpg',
          file: documentBack,
        );
      }

      final selfieUrl = await _uploadXFile(
        path: 'kyc/$userId/selfie.jpg',
        file: selfie,
      );

      await _reqDoc(userId).set(
        <String, dynamic>{
          'userId': userId,
          'status': statusWhenSubmitted,
          'method': 'in_app',
          'docType': documentType,
          'fullName':
              fullName?.trim().isEmpty == true ? null : fullName?.trim(),
          'nationalId':
              nationalId?.trim().isEmpty == true ? null : nationalId?.trim(),
          'phoneE164':
              phoneE164?.trim().isEmpty == true ? null : phoneE164?.trim(),
          'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
          'idFrontUrl': idFrontUrl,
          'idBackUrl': idBackUrl,
          'selfieUrl': selfieUrl,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }..removeWhere((_, v) => v == null),
        SetOptions(merge: true),
      );
    } catch (e) {
      throw Exception('KYC submit failed: $e');
    }
  }
}

final kycRepositoryProvider = Provider<KycRepository>((ref) {
  return const KycRepository();
});

/// Watches the current user request (if signed in).
final kycMyRequestProvider = StreamProvider<KycRequest?>((ref) {
  final auth = ref.watch(authControllerProvider);
  final uid = (auth.userId ?? '').trim();
  if (uid.isEmpty) return const Stream<KycRequest?>.empty();

  final repo = ref.read(kycRepositoryProvider);
  return repo.watchRequest(uid);
});

// import 'dart:typed_data';

// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_storage/firebase_storage.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:image_picker/image_picker.dart';

// class KycRepository {
//   const KycRepository();

//   DocumentReference<Map<String, dynamic>> _reqDoc(String userId) {
//     return FirebaseFirestore.instance.collection('kyc_requests').doc(userId);
//   }

//   Future<String> _upload({
//     required String path,
//     required XFile file,
//   }) async {
//     final ref = FirebaseStorage.instance.ref(path);
//     final Uint8List bytes = await file.readAsBytes();
//     await ref.putData(bytes);
//     return ref.getDownloadURL();
//   }

//   Future<void> submitIdRequest({
//     required String userId,
//     required String statusWhenSubmitted,
//     String? fullName,
//     String? nationalId,
//     String? phoneE164,
//     String? notes,
//     required XFile idFront,
//     required XFile idBack,
//     XFile? selfie,
//   }) async {
//     final idFrontUrl =
//         await _upload(path: 'kyc/$userId/id_front.jpg', file: idFront);
//     final idBackUrl =
//         await _upload(path: 'kyc/$userId/id_back.jpg', file: idBack);

//     String? selfieUrl;
//     if (selfie != null) {
//       selfieUrl = await _upload(path: 'kyc/$userId/selfie.jpg', file: selfie);
//     }

//     await _reqDoc(userId).set(
//       <String, dynamic>{
//         'userId': userId,
//         'status': statusWhenSubmitted,
//         'method': 'id',
//         'fullName': fullName?.trim().isEmpty == true ? null : fullName?.trim(),
//         'nationalId':
//             nationalId?.trim().isEmpty == true ? null : nationalId?.trim(),
//         'phoneE164':
//             phoneE164?.trim().isEmpty == true ? null : phoneE164?.trim(),
//         'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
//         'idFrontUrl': idFrontUrl,
//         'idBackUrl': idBackUrl,
//         'selfieUrl': selfieUrl,
//         'createdAt': FieldValue.serverTimestamp(),
//         'updatedAt': FieldValue.serverTimestamp(),
//       }..removeWhere((_, v) => v == null),
//       SetOptions(merge: true),
//     );
//   }
// }

// final kycRepositoryProvider = Provider<KycRepository>((ref) {
//   return const KycRepository();
// });
