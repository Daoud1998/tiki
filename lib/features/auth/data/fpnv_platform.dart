import 'package:flutter/services.dart';

class FpnvResult {
  final String phoneNumber;
  final String token;
  const FpnvResult({required this.phoneNumber, required this.token});

  factory FpnvResult.fromMap(Map<dynamic, dynamic> map) {
    return FpnvResult(
      phoneNumber: (map['phoneNumber'] ?? '').toString(),
      token: (map['token'] ?? '').toString(),
    );
  }
}

class FpnvPlatform {
  static const MethodChannel _ch = MethodChannel('tiki/fpnv');

  static Future<bool> isSupported() async {
    try {
      return (await _ch.invokeMethod<bool>('isSupported')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<FpnvResult?> getVerifiedPhoneNumber({
    required String privacyPolicyUrl,
  }) async {
    try {
      final res = await _ch.invokeMethod<Map<dynamic, dynamic>>(
        'getVerifiedPhoneNumber',
        {'privacyPolicyUrl': privacyPolicyUrl},
      );
      if (res == null) return null;
      return FpnvResult.fromMap(res);
    } catch (_) {
      return null;
    }
  }
}
