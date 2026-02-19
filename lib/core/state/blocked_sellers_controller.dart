import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/moderation_repository.dart';
import '../storage/local_store.dart';
import 'auth_state.dart';

/// Holds blocked seller keys (synced to Firestore).
///
/// Firestore path: `users/{uid}/blocks/{sellerKey}`
///
/// - Prefer `sellerKey = seller UID`.
/// - For backward compatibility we also support phone keys (E164 or digits).
final blockedSellersProvider =
    StateNotifierProvider<BlockedSellersController, Set<String>>((ref) {
  final store = ref.watch(localStoreProvider);
  final c = BlockedSellersController(ref, store);

  // Re-bind when auth changes (sign-in / sign-out).
  ref.listen<AuthState>(authControllerProvider, (prev, next) {
    unawaited(c._onAuthChanged(next));
  });

  unawaited(c.init());
  return c;
});

class BlockedSellersController extends StateNotifier<Set<String>> {
  BlockedSellersController(this._ref, this._store) : super(const <String>{});

  final Ref _ref;
  final LocalStore _store;

  StreamSubscription<Set<String>>? _sub;
  bool _inited = false;
  bool _migratedLocalOnce = false;

  Future<void> init() async {
    if (_inited) return;
    _inited = true;

    // 1) Load local blocks first (fast UI).
    final local = await _store.getBlockedSellerKeys();
    state = local.map(_normalizeKey).where((e) => e.isNotEmpty).toSet();

    // 2) Overlay Firestore blocks if signed in.
    final auth = _ref.read(authControllerProvider);
    await _startOrStopRemote(auth);
  }

  Future<void> _onAuthChanged(AuthState next) async {
    await _startOrStopRemote(next);
  }

  Future<void> _startOrStopRemote(AuthState auth) async {
    await _sub?.cancel();
    _sub = null;

    if (!auth.isSignedIn) {
      final local = await _store.getBlockedSellerKeys();
      state = local.map(_normalizeKey).where((e) => e.isNotEmpty).toSet();
      return;
    }

    // Best-effort migration: push local phone blocks to Firestore once so they
    // become synced across devices (and survive reinstall).
    if (!_migratedLocalOnce) {
      _migratedLocalOnce = true;
      try {
        final mod = ModerationRepository();
        final local = await _store.getBlockedSellerKeys();
        for (final k in local) {
          final phone = _normalizePhone(k);
          if (phone.isEmpty) continue;
          unawaited(mod.blockSeller(
            sellerKey: phone,
            sellerPhone: phone,
            source: 'migrate_local',
          ));
        }
      } catch (_) {
        // ignore
      }
    }

    // Live stream from Firestore.
    try {
      final mod = ModerationRepository();
      _sub = mod.watchBlockedKeys().listen((remoteKeys) async {
        final local = await _store.getBlockedSellerKeys();
        final merged = <String>{
          ...remoteKeys.map(_normalizeKey),
          ...local.map(_normalizeKey),
        }..removeWhere((e) => e.trim().isEmpty);
        state = merged;
      }, onError: (_) async {
        final local = await _store.getBlockedSellerKeys();
        state = local.map(_normalizeKey).where((e) => e.isNotEmpty).toSet();
      });
    } catch (_) {
      final local = await _store.getBlockedSellerKeys();
      state = local.map(_normalizeKey).where((e) => e.isNotEmpty).toSet();
    }
  }

  String _normalizeKey(String v) {
    final s = v.trim();
    if (s.isEmpty) return '';
    // Phone-like keys: keep digits/+ only.
    if (s.startsWith('+') || RegExp(r'^\d+$').hasMatch(s)) {
      return _normalizePhone(s);
    }
    return s; // seller UID etc
  }

  String _normalizePhone(String v) {
    return v.trim().replaceAll(RegExp(r'[^0-9\+]'), '');
  }

  /// Backward-compatible API.
  bool isBlocked(String phoneOrKey) =>
      state.contains(_normalizeKey(phoneOrKey));

  /// Blocks a seller and syncs to Firestore when signed in.
  ///
  /// Prefer sellerId (UID) when available, but we also store sellerPhone.
  Future<void> blockSeller({
    String? sellerId,
    String? sellerPhone,
    String? source,
  }) async {
    final sid = (sellerId ?? '').trim();
    final phone = _normalizePhone(sellerPhone ?? '');
    final key = sid.isNotEmpty ? sid : phone;
    if (key.trim().isEmpty) return;

    // Local cache for instant filtering + backward compatibility.
    if (phone.isNotEmpty) {
      await _store.blockSeller(phone);
    }

    // Firestore sync.
    final auth = _ref.read(authControllerProvider);
    if (auth.isSignedIn) {
      await ModerationRepository().blockSeller(
        sellerKey: key,
        sellerId: sid.isEmpty ? null : sid,
        sellerPhone: phone.isEmpty ? null : phone,
        source: source,
      );
    }

    state = {
      ...state,
      _normalizeKey(key),
      if (phone.isNotEmpty) phone,
    };
  }

  /// Backward-compatible API (phone-based).
  Future<void> block(String phone) async {
    await blockSeller(sellerPhone: phone, source: 'ui');
  }

  Future<void> unblock(String phoneOrKey) async {
    final key = _normalizeKey(phoneOrKey);
    if (key.isEmpty) return;

    // Local cache cleanup (no-op if key isn't a phone).
    await _store.unblockSeller(key);

    final auth = _ref.read(authControllerProvider);
    if (auth.isSignedIn) {
      try {
        await ModerationRepository().unblockSeller(key);
      } catch (_) {
        // ignore
      }
    }

    final next = {...state}..remove(key);
    state = next;
  }

  Future<void> clear() async {
    await _store.clearBlockedSellers();

    // Best-effort remote clear (chunked).
    final uid = fb.FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.trim().isNotEmpty) {
      try {
        final db = FirebaseFirestore.instance;
        final col = db.collection('users').doc(uid).collection('blocks');
        var snap = await col.limit(400).get();
        while (snap.docs.isNotEmpty) {
          final batch = db.batch();
          for (final d in snap.docs) {
            batch.delete(d.reference);
          }
          await batch.commit();
          snap = await col.limit(400).get();
        }
      } catch (_) {
        // ignore
      }
    }

    state = const <String>{};
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
