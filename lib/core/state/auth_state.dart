import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../storage/local_store.dart';

enum AuthProviderKind { local, google, apple, tiktok, whatsapp }

enum AuthStatus { loading, guest, signedIn }

class AuthState {
  const AuthState({
    required this.status,
    this.userId,
    this.name,
    this.phoneE164,
    this.email,
    this.provider,
  });

  final AuthStatus status;
  final String? userId;
  final String? name;
  final String? phoneE164;
  final String? email;
  final AuthProviderKind? provider;

  bool get isSignedIn => status == AuthStatus.signedIn;

  static const loading = AuthState(status: AuthStatus.loading);
  static const guest = AuthState(status: AuthStatus.guest);

  AuthState copyWith({
    AuthStatus? status,
    String? userId,
    String? name,
    String? phoneE164,
    String? email,
    AuthProviderKind? provider,
  }) {
    return AuthState(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      phoneE164: phoneE164 ?? this.phoneE164,
      email: email ?? this.email,
      provider: provider ?? this.provider,
    );
  }
}

class AuthOpResult {
  const AuthOpResult({required this.ok, this.message});
  const AuthOpResult.ok()
      : ok = true,
        message = null;
  const AuthOpResult.fail(this.message) : ok = false;

  final bool ok;
  final String? message;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref) : super(AuthState.loading) {
    _bindFirebaseAuth();
  }

  final Ref _ref;

  final Map<String, String> _verificationIdByPhone = <String, String>{};
  final Map<String, int?> _resendTokenByPhone = <String, int?>{};

  StreamSubscription<fb.User?>? _sub;

  // ---------------------------------------------------------------------------
  // Firebase binding
  // ---------------------------------------------------------------------------

  void _bindFirebaseAuth() {
    _sub?.cancel();

    final auth = fb.FirebaseAuth.instance;

    final u = auth.currentUser;
    if (u == null) {
      state = AuthState.guest;
    } else {
      state = AuthState(
        status: AuthStatus.signedIn,
        userId: u.uid,
        name: u.displayName,
        phoneE164: u.phoneNumber,
        email: _safeEmail(u.email),
        provider: _guessProvider(u),
      );
      unawaited(_ensureUserDoc(user: u));
    }

    _sub = auth.authStateChanges().listen((user) async {
      if (user == null) {
        state = AuthState.guest;
        await _persistSession(null);
        return;
      }

      await _ensureUserDoc(user: user);
      state = AuthState(
        status: AuthStatus.signedIn,
        userId: user.uid,
        name: user.displayName,
        phoneE164: user.phoneNumber,
        email: _safeEmail(user.email),
        provider: _guessProvider(user),
      );
      await _persistSession(state);
    });
  }

  AuthProviderKind _guessProvider(fb.User u) {
    // If signed in with a custom token, providerData can be empty.
    // We'll keep "local" as the safe default.
    final providers = u.providerData.map((e) => e.providerId).toList();
    if (providers.contains('google.com')) return AuthProviderKind.google;
    if (providers.contains('apple.com')) return AuthProviderKind.apple;
    if (providers.contains('phone')) return AuthProviderKind.local;
    return AuthProviderKind.local;
  }

  Future<void> _persistSession(AuthState? s) async {
    final store = _ref.read(localStoreProvider);

    if (s == null || !s.isSignedIn) {
      await store.setAuthSessionJson(null);
      return;
    }

    final m = <String, dynamic>{
      'status': 'signedIn',
      'userId': s.userId ?? '',
      'name': s.name ?? '',
      'phoneE164': s.phoneE164 ?? '',
      'email': s.email ?? '',
      'provider': (s.provider ?? AuthProviderKind.local).name,
    };
    await store.setAuthSessionJson(jsonEncode(m));
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';

    // Accept E.164 input.
    if (s.startsWith('+')) {
      final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
      return digits.isEmpty ? '' : '+$digits';
    }

    // Accept 00-prefixed international numbers (e.g. 00222XXXXXXXX).
    if (s.startsWith('00')) {
      final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length <= 2) return '';
      return '+${digits.substring(2)}';
    }

    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    // Mauritania (+222) national numbers are 8 digits.
    // If the user entered a local number, assume +222.
    if (digits.length == 8) return '+222$digits';

    // If the user pasted 222XXXXXXXX without '+', keep it ONLY if it looks like
    // country code + national number (222 + 8 digits => 11 digits total).
    if (digits.startsWith('222') && digits.length == 11) return '+$digits';

    // If it looks like a full international number without '+', keep it (E.164 max 15 digits).
    if (digits.length >= 10 && digits.length <= 15) return '+$digits';

    // Fallback to +222 (legacy behavior)
    return '+222$digits';
  }

  bool _isPseudoEmail(String? email) {
    final em = (email ?? '').trim().toLowerCase();
    return em.endsWith('@tiki.phone');
  }

  String _pseudoEmailForPhone(String phoneE164) {
    final digits = phoneE164.replaceAll(RegExp(r'[^0-9]'), '');
    return 'p$digits@tiki.phone';
  }


  /// Some older builds used a pseudo-email WITHOUT the country code for +222 numbers
  /// (e.g. p36566606@tiki.phone instead of p22236566606@tiki.phone).
  /// To keep backward compatibility, we try both variants when checking/login.
  List<String> _pseudoEmailCandidatesForPhone(String phoneE164) {
    final digits = phoneE164.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const <String>[];

    final out = <String>['p$digits@tiki.phone'];

    // Mauritania legacy: allow local 8-digit pseudo email.
    if (digits.startsWith('222') && digits.length == 11) {
      final local = digits.substring(3);
      if (local.length == 8) out.add('p$local@tiki.phone');
    }

    // Ensure uniqueness while keeping order.
    final seen = <String>{};
    final unique = <String>[];
    for (final e in out) {
      if (seen.add(e)) unique.add(e);
    }
    return unique;
  }

  Future<List<String>> _fetchMethodsForEmailCompat(String email) async {
    final auth = fb.FirebaseAuth.instance as dynamic;

    try {
      final res = await auth.fetchSignInMethodsForEmail(email);
      return (res as List).cast<String>();
    } catch (_) {
      try {
        // Compatibility with older firebase_auth versions
        final res = await auth.fetchProvidersForEmail(email);
        return (res as List).cast<String>();
      } catch (_) {
        return const <String>[];
      }
    }
  }

  /// Check if a phone already has password-based login enabled.
  /// This does NOT require the user to be signed in and does NOT read Firestore.
  Future<bool> phoneHasPasswordLogin({required String phoneE164}) async {
    final p = _normalizePhone(phoneE164);
    if (p.isEmpty) return false;

    // Try all backward-compatible pseudo emails.
    final emails = _pseudoEmailCandidatesForPhone(p);
    if (emails.isEmpty) return false;

    try {
      for (final email in emails) {
        final methods = await _fetchMethodsForEmailCompat(email);
        if (methods.contains('password')) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  String? _safeEmail(String? email) => _isPseudoEmail(email) ? null : email;

  String _mapFirebaseError(Object e) {
    if (e is fb.FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-phone-number':
          return 'invalid_phone';
        case 'too-many-requests':
          return 'too_many_requests';
        case 'quota-exceeded':
          return 'quota_exceeded';
        case 'session-expired':
          return 'otp_expired';
        case 'invalid-verification-code':
          return 'otp_invalid';
        case 'missing-verification-code':
          return 'otp_invalid';
        case 'network-request-failed':
          return 'network';
        case 'wrong-password':
          return 'wrong_password';
        case 'user-not-found':
          return 'user_not_found';
        case 'invalid-credential':
          return 'wrong_password';
        case 'account-exists-with-different-credential':
          return 'account_exists_with_different_credential';
        case 'email-already-in-use':
          return 'email_in_use';
        case 'weak-password':
          return 'weak_password';
        case 'requires-recent-login':
          return 'requires_recent_login';
        default:
          return e.code;
      }
    }
    return 'unknown';
  }

  String _mapFunctionsError(Object e) {
    if (e is FirebaseFunctionsException) {
      final msg = (e.message ?? '').toString();
      final details = e.details;

      // details is often a JSON-like map from Cloud Functions.
      Map<String, dynamic> d = <String, dynamic>{};
      if (details is Map) {
        try {
          d = Map<String, dynamic>.from(details);
        } catch (_) {}
      }

      final detMsg = (d['message'] ?? d['error'] ?? '').toString();
      final twilioCode = d['code'] == null ? '' : d['code'].toString();
      final combined = ('$msg $detMsg').toUpperCase();

      if (kDebugMode) {
        debugPrint(
            'FunctionsException code=${e.code} message=$msg details=$details');
      }

      switch (e.code) {
        case 'failed-precondition':
          if (combined.contains('TWILIO_NOT_CONFIGURED'))
            return 'twilio_not_configured';
          if (combined.contains('OTP_NOT_CONFIGURED'))
            return 'functions_not_configured';
          return 'functions_not_configured';

        case 'invalid-argument':
          return 'invalid_phone';

        case 'deadline-exceeded':
          return 'otp_expired';

        case 'permission-denied':
          return 'otp_invalid';

        case 'resource-exhausted':
          return 'too_many_requests';

        case 'unauthenticated':
          return 'unauthenticated';

        case 'unavailable':
          return 'network';

        case 'not-found':
          // callable function missing (not deployed / wrong region)
          return 'functions_not_found';

        case 'internal':
          // Twilio errors are thrown as internal with message markers.
          if (combined.contains('TWILIO_SEND_FAILED')) {
            return twilioCode.isNotEmpty
                ? 'twilio_send_failed_$twilioCode'
                : 'twilio_send_failed';
          }
          if (combined.contains('TWILIO_VERIFY_FAILED')) {
            return twilioCode.isNotEmpty
                ? 'twilio_verify_failed_$twilioCode'
                : 'twilio_verify_failed';
          }
          if (combined.contains('AUTH_LOOKUP_FAILED'))
            return 'auth_lookup_failed';

          // If Cloud Function didn't include a marker but provided Twilio-like details, still surface it.
          if (twilioCode.isNotEmpty) {
            return 'twilio_send_failed_$twilioCode';
          }
          return 'functions_internal';

        default:
          return 'functions_${e.code}';
      }
    }
    return 'unknown';
  }

  // ---------------------------------------------------------------------------
  // Firestore: users/{uid}
  // ---------------------------------------------------------------------------

  Future<void> _ensureUserDoc({
    required fb.User user,
    String? displayName,
    String? email,
    String? phoneE164Override,
  }) async {
    final uid = user.uid;
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await ref.get();

    final now = FieldValue.serverTimestamp();
    final phone = (phoneE164Override ?? user.phoneNumber)?.trim();

    final data = <String, dynamic>{
      'uid': uid,
      'lastSeenAt': now,
      'updatedAt': now,
    };

    if (phone != null && phone.isNotEmpty) data['phoneE164'] = phone;

    final dn = (displayName ?? user.displayName ?? '').trim();
    if (dn.isNotEmpty) data['displayName'] = dn;
    final em = (email ?? user.email ?? '').trim();
    if (em.isNotEmpty && !_isPseudoEmail(em)) data['email'] = em;

    if (!snap.exists) {
      data['createdAt'] = now;
      data['role'] = 'user';
    }

    await ref.set(data, SetOptions(merge: true));
  }

  // ---------------------------------------------------------------------------
  // Phone OTP (Firebase Phone Auth / SMS)
  // ---------------------------------------------------------------------------

  /// Request an SMS OTP.
  /// Returns:
  /// - 'sent'   => code sent (OTP dialog should be shown)
  /// - 'auto'   => auto verification completed (user already signed in)
  Future<String> requestPhoneOtp(String phone) async {
    final p = _normalizePhone(phone);
    if (p.isEmpty) {
      throw fb.FirebaseAuthException(code: 'invalid-phone-number');
    }

    final digitCount = p.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (p.startsWith('+222')) {
      if (digitCount != 11) {
        throw fb.FirebaseAuthException(code: 'invalid-phone-number');
      }
    } else {
      if (digitCount < 8 || digitCount > 15) {
        throw fb.FirebaseAuthException(code: 'invalid-phone-number');
      }
    }

    final completer = Completer<String>();
    await fb.FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: p,
      timeout: const Duration(seconds: 60),
      forceResendingToken: _resendTokenByPhone[p],
      verificationCompleted: (cred) async {
        try {
          await fb.FirebaseAuth.instance.signInWithCredential(cred);
          final u = fb.FirebaseAuth.instance.currentUser;
          if (u != null) {
            await _ensureUserDoc(user: u, phoneE164Override: p);
          }
          if (!completer.isCompleted) completer.complete('auto');
        } catch (e) {
          if (!completer.isCompleted) completer.completeError(e);
        }
      },
      verificationFailed: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      codeSent: (verificationId, resendToken) {
        _verificationIdByPhone[p] = verificationId;
        _resendTokenByPhone[p] = resendToken;
        if (!completer.isCompleted) completer.complete('sent');
      },
      codeAutoRetrievalTimeout: (verificationId) {
        _verificationIdByPhone[p] = verificationId;
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 65),
      onTimeout: () => 'sent',
    );
  }

  /// Sign in using the OTP code entered by the user.
  Future<AuthOpResult> signInWithOtp({
    required String phoneE164,
    required String code,
  }) async {
    final p = _normalizePhone(phoneE164);
    final vid = _verificationIdByPhone[p];

    if (vid == null || vid.isEmpty) {
      return const AuthOpResult.fail('otp_not_requested');
    }

    try {
      final cred =
          fb.PhoneAuthProvider.credential(verificationId: vid, smsCode: code);
      final res = await fb.FirebaseAuth.instance.signInWithCredential(cred);

      final u = res.user;
      if (u != null) {
        await _ensureUserDoc(user: u, phoneE164Override: p);
      }
      return const AuthOpResult.ok();
    } catch (e) {
      return AuthOpResult.fail(_mapFirebaseError(e));
    }
  }

  /// "Signup" over phone OTP is the same as sign-in, but we also store profile
  /// fields (name/email) in users/{uid}.
  Future<AuthOpResult> createAccountWithOtp({
    required String name,
    required String phoneE164,
    required String code,
    String? email,
  }) async {
    final res = await signInWithOtp(phoneE164: phoneE164, code: code);
    if (!res.ok) return res;

    final u = fb.FirebaseAuth.instance.currentUser;
    if (u == null) return const AuthOpResult.fail('unknown');

    final dn = name.trim();
    try {
      if (dn.isNotEmpty) {
        await u.updateDisplayName(dn);
      }
      await _ensureUserDoc(
          user: u,
          displayName: dn,
          email: email,
          phoneE164Override: _normalizePhone(phoneE164));
      return const AuthOpResult.ok();
    } catch (e) {
      return AuthOpResult.fail(_mapFirebaseError(e));
    }
  }

  // ---------------------------------------------------------------------------
  // WhatsApp OTP (Cloud Functions + Custom Token)
  // ---------------------------------------------------------------------------

  /// Send OTP via WhatsApp using callable function: sendWhatsappOtp
  Future<AuthOpResult> requestWhatsAppOtp({
    required String phoneE164,
    String languageCode = 'ar',
  }) async {
    return const AuthOpResult.fail('whatsapp_soon');
  }

  /// Verify OTP sent via WhatsApp and sign in using custom token.
  Future<AuthOpResult> signInWithWhatsAppOtp({
    required String phoneE164,
    required String code,
  }) async {
    return const AuthOpResult.fail('whatsapp_soon');
  }

  /// Signup via WhatsApp OTP then store profile info.
  Future<AuthOpResult> createAccountWithWhatsAppOtp({
    required String name,
    required String phoneE164,
    required String code,
    String? email,
  }) async {
    return const AuthOpResult.fail('whatsapp_soon');
  }

  // ---------------------------------------------------------------------------
  // Twilio Verify OTP (Cloud Functions + Custom Token)
  // ---------------------------------------------------------------------------

  FirebaseFunctions _functionsEU() =>
      FirebaseFunctions.instanceFor(region: 'europe-west1');

  /// Send OTP via Twilio Verify using callable function: twilioStartOtp
  Future<AuthOpResult> requestTwilioOtp({
    required String phoneE164,
    String channel = 'sms', // 'sms' | 'whatsapp'
  }) async {
    final p = _normalizePhone(phoneE164);
    if (p.isEmpty) return const AuthOpResult.fail('invalid_phone');

    try {
      final fn = _functionsEU().httpsCallable('twilioStartOtp');
      await fn.call(<String, dynamic>{
        'phoneE164': p,
        'channel': channel,
      });
      return const AuthOpResult.ok();
    } catch (e) {
      return AuthOpResult.fail(_mapFunctionsError(e));
    }
  }

  /// Verify OTP via Twilio and sign in using Firebase custom token.
  Future<AuthOpResult> signInWithTwilioOtp({
    required String phoneE164,
    required String code,
  }) async {
    final p = _normalizePhone(phoneE164);
    if (p.isEmpty) return const AuthOpResult.fail('invalid_phone');

    final c = code.trim();
    if (c.isEmpty) return const AuthOpResult.fail('otp_invalid');

    try {
      final fn = _functionsEU().httpsCallable('twilioVerifyOtp');
      final r = await fn.call(<String, dynamic>{'phoneE164': p, 'code': c});

      final raw = r.data;
      final data =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final ok = data['ok'] == true;

      if (!ok) {
        final st = (data['status'] ?? '').toString().toLowerCase();
        if (st == 'expired') return const AuthOpResult.fail('otp_expired');
        return const AuthOpResult.fail('otp_invalid');
      }

      final token = (data['customToken'] ?? '').toString();
      if (token.isEmpty) return const AuthOpResult.fail('unknown');

      // Sign in with Firebase custom token.
      final res = await fb.FirebaseAuth.instance.signInWithCustomToken(token);
      final u = res.user;

      // Don't block sign-in if Firestore/AppCheck prevents user doc write.
      if (u != null) {
        try {
          await _ensureUserDoc(user: u, phoneE164Override: p);
        } catch (e) {
          // ignore but log
          // ignore: avoid_print
          print('ensureUserDoc (twilio) skipped: $e');
        }
      }

      return const AuthOpResult.ok();
    } on fb.FirebaseAuthException catch (e) {
      // Return auth error so UI can show a meaningful message.
      // ignore: avoid_print
      print('signInWithCustomToken failed: code=${e.code} msg=${e.message}');
      return AuthOpResult.fail('auth_${e.code}');
    } catch (e) {
      return AuthOpResult.fail(_mapFunctionsError(e));
    }
  }

  /// Signup via Twilio OTP then store profile info (name/email) in users/{uid}.
  Future<AuthOpResult> createAccountWithTwilioOtp({
    required String name,
    required String phoneE164,
    required String code,
    String? email,
  }) async {
    final res = await signInWithTwilioOtp(phoneE164: phoneE164, code: code);
    if (!res.ok) return res;

    final u = fb.FirebaseAuth.instance.currentUser;
    if (u == null) return const AuthOpResult.fail('unknown');

    final dn = name.trim();
    try {
      if (dn.isNotEmpty) {
        await u.updateDisplayName(dn);
      }
      await _ensureUserDoc(
        user: u,
        displayName: dn,
        email: email,
        phoneE164Override: _normalizePhone(phoneE164),
      );
      return const AuthOpResult.ok();
    } catch (e) {
      return AuthOpResult.fail(_mapFirebaseError(e));
    }
  }
// ---------------------------------------------------------------------------
  // Phone + Password (implemented via hidden Email/Password on a pseudo email)
  // ---------------------------------------------------------------------------

  /// Login using "phone + password" (internally Email/Password on pseudo email).
  // NOTE: Password sign-in must NOT trigger OTP. OTP is only for SMS login / reset.
  Future<AuthOpResult> signInWithPhonePassword({
    required String phoneE164,
    required String password,
  }) async {
    final p = _normalizePhone(phoneE164);
    if (p.isEmpty) return const AuthOpResult.fail('invalid_phone');
    if (password.trim().isEmpty) {
      return const AuthOpResult.fail('empty_password');
    }

    final pw = password.trim();
    final emails = _pseudoEmailCandidatesForPhone(p);
    if (emails.isEmpty) return const AuthOpResult.fail('user_not_found');

    String? lastErr;

    for (final email in emails) {
      try {
        final res = await fb.FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: pw,
        );

        final u = res.user;
        if (u != null) {
          await _ensureUserDoc(user: u, phoneE164Override: p);
          await FirebaseFirestore.instance.collection('users').doc(u.uid).set({
            'hasPassword': true,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        return const AuthOpResult.ok();
      } catch (e) {
        final code = _mapFirebaseError(e);
        lastErr = code;

        // If this pseudo-email didn't exist in older builds, try the next variant.
        if (code == 'user_not_found') continue;

        // Wrong password might be for a different legacy pseudo-email; try others
        // before returning it.
        if (code == 'wrong_password') continue;

        return AuthOpResult.fail(code);
      }
    }

    return AuthOpResult.fail(lastErr ?? 'user_not_found');
  }


  /// After OTP signup/signin, call this once to enable password-based login.
  Future<AuthOpResult> enablePhonePasswordLogin({
    required String phoneE164,
    required String password,
  }) async {
    final u = fb.FirebaseAuth.instance.currentUser;
    if (u == null) return const AuthOpResult.fail('not_signed_in');

    final p = _normalizePhone(phoneE164);
    if (p.isEmpty) return const AuthOpResult.fail('invalid_phone');

    final email = _pseudoEmailForPhone(p);

    try {
      final cred = fb.EmailAuthProvider.credential(
        email: email,
        password: password.trim(),
      );

      await u.linkWithCredential(cred);

      await _ensureUserDoc(user: u, phoneE164Override: p);
      await FirebaseFirestore.instance.collection('users').doc(u.uid).set({
        'hasPassword': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return const AuthOpResult.ok();
    } catch (e) {
      if (e is fb.FirebaseAuthException) {
        // Treat already-linked as success.
        if (e.code == 'provider-already-linked') {
          await _ensureUserDoc(user: u, phoneE164Override: p);
          await FirebaseFirestore.instance.collection('users').doc(u.uid).set({
            'hasPassword': true,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return const AuthOpResult.ok();
        }
      }
      return AuthOpResult.fail(_mapFirebaseError(e));
    }
  }

  /// Reset or set password after verifying phone OTP.
  ///
  /// Flow: requestPhoneOtp -> signInWithOtp -> setPhonePasswordAfterOtp
  Future<AuthOpResult> setPhonePasswordAfterOtp({
    required String phoneE164,
    required String newPassword,
  }) async {
    final u = fb.FirebaseAuth.instance.currentUser;
    if (u == null) return const AuthOpResult.fail('not_signed_in');

    final p = _normalizePhone(phoneE164);
    if (p.isEmpty) return const AuthOpResult.fail('invalid_phone');

    final pw = newPassword.trim();
    if (pw.isEmpty) return const AuthOpResult.fail('empty_password');

    final hasRealEmail =
        !_isPseudoEmail(u.email) && (u.email ?? '').trim().isNotEmpty;
    final hasPasswordProvider =
        u.providerData.any((p) => p.providerId == 'password');

    // If the account already has a real email (Google/Apple), we avoid attaching a pseudo email
    // to prevent overwriting the primary email in Firebase Auth.
    if (hasRealEmail && !hasPasswordProvider) {
      return const AuthOpResult.fail('not_supported');
    }

    try {
      if (hasPasswordProvider) {
        await u.updatePassword(pw);
      } else {
        final email = _pseudoEmailForPhone(p);
        final cred =
            fb.EmailAuthProvider.credential(email: email, password: pw);
        await u.linkWithCredential(cred);
      }

      await FirebaseFirestore.instance.collection('users').doc(u.uid).set({
        'hasPassword': true,
        'phoneE164': p,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return const AuthOpResult.ok();
    } catch (e) {
      // If already linked, try update password as a fallback
      if (e is fb.FirebaseAuthException &&
          e.code == 'provider-already-linked') {
        try {
          await u.updatePassword(pw);
          await FirebaseFirestore.instance.collection('users').doc(u.uid).set({
            'hasPassword': true,
            'phoneE164': p,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return const AuthOpResult.ok();
        } catch (_) {}
      }
      return AuthOpResult.fail(_mapFirebaseError(e));
    }
  }

// ---------------------------------------------------------------------------
  // Third-party mock + profile
  // ---------------------------------------------------------------------------


  Future<AuthOpResult> signInThirdPartyMock({
    required AuthProviderKind provider,
    required String displayName,
  }) async {
    try {
      switch (provider) {
        case AuthProviderKind.google:
          final g = GoogleSignIn();
          final acc = await g.signIn();
          if (acc == null) return const AuthOpResult.fail('cancelled');

          final gAuth = await acc.authentication;
          final cred = fb.GoogleAuthProvider.credential(
            accessToken: gAuth.accessToken,
            idToken: gAuth.idToken,
          );

          final res = await fb.FirebaseAuth.instance.signInWithCredential(cred);
          final u = res.user;
          if (u != null) {
            await _ensureUserDoc(user: u);
          }
          return const AuthOpResult.ok();

        case AuthProviderKind.apple:
          final apple = await SignInWithApple.getAppleIDCredential(
            scopes: const [
              AppleIDAuthorizationScopes.email,
              AppleIDAuthorizationScopes.fullName,
            ],
          );

          final oauth = fb.OAuthProvider('apple.com');
          final cred = oauth.credential(
            idToken: apple.identityToken,
            accessToken: apple.authorizationCode,
          );

          final res = await fb.FirebaseAuth.instance.signInWithCredential(cred);
          final u = res.user;
          if (u != null) {
            final fullName = [apple.givenName, apple.familyName]
                .where((e) => (e ?? '').trim().isNotEmpty)
                .map((e) => e!.trim())
                .join(' ');
            if (fullName.isNotEmpty && (u.displayName ?? '').trim().isEmpty) {
              await u.updateDisplayName(fullName);
            }
            await _ensureUserDoc(
                user: u,
                displayName: fullName.isEmpty ? null : fullName,
                email: apple.email);
          }
          return const AuthOpResult.ok();

        default:
          return const AuthOpResult.fail('oauth_not_ready');
      }
    } catch (e) {
      return AuthOpResult.fail(_mapFirebaseError(e));
    }
  }

  Future<String?> updateProfile({required String name, String? email}) async {
    final u = fb.FirebaseAuth.instance.currentUser;
    if (u == null) return 'not_signed_in';

    final dn = name.trim();
    final emailProvided = email != null;
    final em = (email ?? '').trim();

    try {
      if (dn.isNotEmpty && dn != (u.displayName ?? '').trim()) {
        await u.updateDisplayName(dn);
      }

      final uid = u.uid;
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);

      final now = FieldValue.serverTimestamp();
      final data = <String, dynamic>{
        'uid': uid,
        'phoneE164': (u.phoneNumber ?? state.phoneE164),
        'displayName': dn,
        'lastSeenAt': now,
        'updatedAt': now,
      };

      if (emailProvided) {
        data['email'] = em.isEmpty ? FieldValue.delete() : em;
      }

      await ref.set(data, SetOptions(merge: true));

      state = state.copyWith(
        name: dn,
        email: emailProvided ? (em.isEmpty ? null : em) : state.email,
      );
      await _persistSession(state);

      return null;
    } catch (e) {
      return _mapFirebaseError(e);
    }
  }

  Future<String?> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final u = fb.FirebaseAuth.instance.currentUser;
    if (u == null) return 'not_signed_in';

    final hasPasswordProvider =
        u.providerData.any((p) => p.providerId == 'password');
    if (!hasPasswordProvider) return 'not_supported';

    final email = u.email;
    if (email == null || email.trim().isEmpty) return 'not_supported';

    try {
      final cred = fb.EmailAuthProvider.credential(
        email: email.trim(),
        password: currentPassword.trim(),
      );
      await u.reauthenticateWithCredential(cred);
      await u.updatePassword(newPassword.trim());
      return null;
    } catch (e) {
      return _mapFirebaseError(e);
    }
  }

  Future<void> signOut() async {
    try {
      await fb.FirebaseAuth.instance.signOut();
    } finally {
      await _persistSession(null);
      state = AuthState.guest;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref),
);

/// Live flag controlled by admins to block a user from publishing.
///
/// Admin sets one of these fields in users/{uid}:
/// - publishingDisabled: true
/// - publishDisabled: true
///
/// The user app uses this to disable the publish flow immediately (synced),
/// and Cloud Functions must also enforce it server-side.
final publishingDisabledProvider = StreamProvider<bool>((ref) {
  final uid = ref.watch(authControllerProvider).userId;
  final u = (uid ?? '').trim();
  if (u.isEmpty) return Stream<bool>.value(false);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(u)
      .snapshots()
      .map((snap) {
    final d = snap.data();
    if (d == null) return false;
    return d['publishingDisabled'] == true || d['publishDisabled'] == true;
  });
});
