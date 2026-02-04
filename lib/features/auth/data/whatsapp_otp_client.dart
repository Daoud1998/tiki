// whatsapp_otp_client.dart
// Calls Cloud Functions to send/verify OTP via WhatsApp.
// Place in: lib/features/auth/data/whatsapp_otp_client.dart
//
// Requires:
//   flutter pub add cloud_functions firebase_auth cloud_firestore
//
// Notes:
// - This uses callable functions: sendWhatsappOtp + verifyWhatsappOtp.
// - After verify you receive a customToken; sign in with:
//     FirebaseAuth.instance.signInWithCustomToken(token)

import 'package:cloud_functions/cloud_functions.dart';

class WhatsAppOtpResult {
  final String uid;
  final String customToken;

  WhatsAppOtpResult({required this.uid, required this.customToken});

  factory WhatsAppOtpResult.fromMap(Map<String, dynamic> map) {
    return WhatsAppOtpResult(
      uid: (map['uid'] ?? '').toString(),
      customToken: (map['customToken'] ?? '').toString(),
    );
  }
}

class WhatsAppOtpClient {
  WhatsAppOtpClient({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// If you deployed functions to a specific region, use:
  /// FirebaseFunctions.instanceFor(region: 'europe-west1')
  /// and pass it into this client.
  static WhatsAppOtpClient forRegion(String region) {
    return WhatsAppOtpClient(
        functions: FirebaseFunctions.instanceFor(region: region));
  }

  /// Send OTP to WhatsApp using your approved template.
  /// phoneE164 example: +222XXXXXXXX
  Future<void> sendOtp({
    required String phoneE164,
    String languageCode = 'ar', // your template language, e.g. 'ar' or 'fr'
  }) async {
    final callable = _functions.httpsCallable('sendWhatsappOtp');
    final res = await callable.call(<String, dynamic>{
      'phoneE164': phoneE164,
      'languageCode': languageCode,
    });

    // If the function throws, this won't run.
    final data = (res.data is Map)
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};
    final ok = data['ok'] == true;
    if (!ok) {
      final msg = (data['message'] ?? 'sendOtp failed').toString();
      throw StateError(msg);
    }
  }

  /// Verify OTP and receive a Firebase custom token.
  Future<WhatsAppOtpResult> verifyOtp({
    required String phoneE164,
    required String code,
  }) async {
    final callable = _functions.httpsCallable('verifyWhatsappOtp');
    final res = await callable.call(<String, dynamic>{
      'phoneE164': phoneE164,
      'code': code,
    });

    final data = (res.data is Map)
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};
    final ok = data['ok'] == true;
    if (!ok) {
      final msg = (data['message'] ?? 'verifyOtp failed').toString();
      throw StateError(msg);
    }
    return WhatsAppOtpResult.fromMap(Map<String, dynamic>.from(data));
  }
}
