import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../storage/local_store.dart';

enum AuthProviderKind { local, google, facebook, tiktok, whatsapp }

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
        email: u.email,
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
        email: user.email,
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
    if (providers.contains('facebook.com')) return AuthProviderKind.facebook;
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
    final digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.startsWith('+')) return digits;
    if (digits.isEmpty) return '';
    if (digits.startsWith('222')) return '+$digits';
    return '+222$digits';
  }

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
        default:
          return e.code;
      }
    }
    return 'unknown';
  }

  String _mapFunctionsError(Object e) {
    if (e is FirebaseFunctionsException) {
      // Common ones we may raise from functions:
      // - failed-precondition (missing env, etc.)
      // - invalid-argument
      // - internal (whatsapp api failure)
      switch (e.code) {
        case 'failed-precondition':
          return 'functions_not_configured';
        case 'invalid-argument':
          return 'invalid_phone';
        case 'resource-exhausted':
          return 'too_many_requests';
        case 'unauthenticated':
          return 'unauthenticated';
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
  }) async {
    final uid = user.uid;
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await ref.get();

    final now = FieldValue.serverTimestamp();
    final data = <String, dynamic>{
      'uid': uid,
      'phoneE164': user.phoneNumber,
      'lastSeenAt': now,
      'updatedAt': now,
    };

    final dn = (displayName ?? user.displayName ?? '').trim();
    if (dn.isNotEmpty) data['displayName'] = dn;

    final em = (email ?? user.email ?? '').trim();
    if (em.isNotEmpty) data['email'] = em;

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
            await _ensureUserDoc(user: u);
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
        await _ensureUserDoc(user: u);
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
      await _ensureUserDoc(user: u, displayName: dn, email: email);
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
    final p = _normalizePhone(phoneE164);
    if (p.isEmpty) return const AuthOpResult.fail('invalid_phone');

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('sendWhatsappOtp');
      final res = await callable.call(<String, dynamic>{
        'phoneE164': p,
        'languageCode': languageCode,
      });

      final data = (res.data is Map)
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final ok = data['ok'] == true;

      if (ok) return const AuthOpResult.ok();

      final msg = (data['message'] ?? '').toString();
      // If cooldown message, map to too_many_requests to reuse UI text.
      if (msg.toLowerCase().contains('wait'))
        return const AuthOpResult.fail('too_many_requests');
      return const AuthOpResult.fail('unknown');
    } catch (e) {
      return AuthOpResult.fail(_mapFunctionsError(e));
    }
  }

  /// Verify OTP sent via WhatsApp and sign in using custom token.
  Future<AuthOpResult> signInWithWhatsAppOtp({
    required String phoneE164,
    required String code,
  }) async {
    final p = _normalizePhone(phoneE164);
    if (p.isEmpty) return const AuthOpResult.fail('invalid_phone');

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('verifyWhatsappOtp');
      final res = await callable.call(<String, dynamic>{
        'phoneE164': p,
        'code': code.trim(),
      });

      final data = (res.data is Map)
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      final ok = data['ok'] == true;
      if (!ok) {
        final msg = (data['message'] ?? '').toString().toLowerCase();
        if (msg.contains('expired'))
          return const AuthOpResult.fail('otp_expired');
        if (msg.contains('invalid'))
          return const AuthOpResult.fail('otp_invalid');
        if (msg.contains('too many'))
          return const AuthOpResult.fail('too_many_requests');
        return const AuthOpResult.fail('unknown');
      }

      final token = (data['customToken'] ?? '').toString();
      if (token.isEmpty) return const AuthOpResult.fail('unknown');

      final signRes =
          await fb.FirebaseAuth.instance.signInWithCustomToken(token);
      final u = signRes.user;
      if (u != null) {
        await _ensureUserDoc(user: u);
      }
      return const AuthOpResult.ok();
    } catch (e) {
      return AuthOpResult.fail(_mapFunctionsError(e));
    }
  }

  /// Signup via WhatsApp OTP then store profile info.
  Future<AuthOpResult> createAccountWithWhatsAppOtp({
    required String name,
    required String phoneE164,
    required String code,
    String? email,
  }) async {
    final res = await signInWithWhatsAppOtp(phoneE164: phoneE164, code: code);
    if (!res.ok) return res;

    final u = fb.FirebaseAuth.instance.currentUser;
    if (u == null) return const AuthOpResult.fail('unknown');

    final dn = name.trim();
    try {
      if (dn.isNotEmpty) await u.updateDisplayName(dn);
      await _ensureUserDoc(user: u, displayName: dn, email: email);
      return const AuthOpResult.ok();
    } catch (e) {
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
    return const AuthOpResult.fail('oauth_not_ready');
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
        'phoneE164': u.phoneNumber,
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
    return 'not_supported';
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
