import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_products_db.dart';

/// Open the local SQLite cache (Android/iOS).
final localProductsDbProvider = FutureProvider<LocalProductsDb>((ref) async {
  final db = await LocalProductsDb.open();
  ref.onDispose(() => db.close());
  return db;
});

/// Keep the local cache in sync with Firestore.
/// Call `ref.watch(localProductsSyncProvider)` somewhere high in the widget tree (App).
final localProductsSyncProvider = Provider<void>((ref) {
  if (kIsWeb) return;

  final dbAsync = ref.watch(localProductsDbProvider);

  StreamSubscription? sub;

  dbAsync.whenData((db) {
    sub?.cancel();
    sub = FirebaseFirestore.instance
        .collection('products')
        // Public feed only (must match firestore.rules).
        .where('status', isEqualTo: 'active')
        .where('reviewStatus', isEqualTo: 'approved')
        .where('isHidden', isEqualTo: false)
        .snapshots()
        .listen(
            (snap) => db.applySnapshot(snap),
            onError: (e, st) {
              debugPrint('localProductsSyncProvider Firestore error: $e');
            },
          );
  });

  ref.onDispose(() async {
    await sub?.cancel();
  });
});
