import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

@immutable
class KycRequest {
  const KycRequest({
    required this.userId,
    required this.status,
    required this.method,
    this.docType,
    this.fullName,
    this.nationalId,
    this.phoneE164,
    this.notes,
    this.idFrontUrl,
    this.idBackUrl,
    this.selfieUrl,
    this.rejectionReason,
    this.createdAt,
    this.updatedAt,
  });

  /// App user id (local today, Firebase uid later).
  final String userId;

  /// none | pending | approved | rejected | wallet_verified
  final String status;

  /// id | wallet | whatsapp
  final String method;

  /// national_id | driver_license | residence
  final String? docType;

  final String? fullName;
  final String? nationalId;
  final String? phoneE164;
  final String? notes;

  final String? idFrontUrl;
  final String? idBackUrl;
  final String? selfieUrl;

  final String? rejectionReason;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  static DateTime? _dt(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  factory KycRequest.fromMap(Map<String, dynamic> m, {required String userId}) {
    final rawStatus = (m['status'] as String?)?.trim();
    final rawMethod = (m['method'] as String?)?.trim();
    return KycRequest(
      userId: userId,
      status: (rawStatus != null && rawStatus.isNotEmpty) ? rawStatus : 'none',
      method: (rawMethod != null && rawMethod.isNotEmpty) ? rawMethod : 'id',
      docType: (m['docType'] as String?)?.trim(),
      fullName: (m['fullName'] as String?)?.trim(),
      nationalId: (m['nationalId'] as String?)?.trim(),
      phoneE164: (m['phoneE164'] as String?)?.trim(),
      notes: (m['notes'] as String?)?.trim(),
      idFrontUrl: (m['idFrontUrl'] as String?)?.trim(),
      idBackUrl: (m['idBackUrl'] as String?)?.trim(),
      selfieUrl: (m['selfieUrl'] as String?)?.trim(),
      rejectionReason: (m['rejectionReason'] as String?)?.trim(),
      createdAt: _dt(m['createdAt']),
      updatedAt: _dt(m['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'status': status,
      'method': method,
      'docType': docType,
      'fullName': fullName,
      'nationalId': nationalId,
      'phoneE164': phoneE164,
      'notes': notes,
      'idFrontUrl': idFrontUrl,
      'idBackUrl': idBackUrl,
      'selfieUrl': selfieUrl,
      'rejectionReason': rejectionReason,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    }..removeWhere((_, v) => v == null);
  }
}
