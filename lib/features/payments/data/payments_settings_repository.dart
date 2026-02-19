import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

@immutable
class PaymentWallet {
  const PaymentWallet({
    required this.id,
    required this.enabled,
    required this.labels,
    required this.displayName,
    required this.number,
    required this.icon,
    this.sort = 0,
  });

  final String id;
  final bool enabled;

  /// Localized labels: {"ar":"بنكيلي","fr":"Bankily","en":"Bankily"}
  final Map<String, String> labels;

  /// Receiver name shown to users (e.g. Tkii).
  final String displayName;

  /// Wallet number (e.g. +222..).
  final String number;

  /// Optional icon key (e.g. 'bank', 'wallet').
  final String icon;

  /// Optional ordering (lower first).
  final int sort;

  String labelForLocale(String langCode) {
    final code = (langCode).trim().toLowerCase();
    return labels[code] ?? labels['ar'] ?? labels['en'] ?? id;
  }
}

class PaymentsSettingsRepository {
  PaymentsSettingsRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _db.collection('app_settings').doc('payments');

  Stream<List<PaymentWallet>> watchEnabledWallets() {
    return _doc.snapshots().map((snap) {
      final data = snap.data() ?? const <String, dynamic>{};
      final wallets = _parseWallets(data);
      // Only enabled wallets, stable sort
      final enabled = wallets.where((w) => w.enabled).toList(growable: false);
      enabled.sort((a, b) {
        final s = a.sort.compareTo(b.sort);
        if (s != 0) return s;
        return a.id.compareTo(b.id);
      });
      return enabled;
    });
  }

  static List<PaymentWallet> _parseWallets(Map<String, dynamic> data) {
    final out = <PaymentWallet>[];

    // New schema: wallets: [ {...}, {...} ]
    final raw = data['wallets'];
    if (raw is List) {
      for (final v in raw) {
        if (v is! Map) continue;
        final id = (v['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;

        final enabled = _asBool(v['enabled'], fallback: true);
        final displayName = (v['displayName'] ?? '').toString().trim();
        final number = (v['number'] ?? '').toString().trim();
        final icon = (v['icon'] ?? '').toString().trim();
        final sort = _asInt(v['sort'], fallback: 0);

        final labels = <String, String>{};
        final lab = v['label'] ?? v['labels'];
        if (lab is Map) {
          for (final e in lab.entries) {
            final k = (e.key ?? '').toString().trim().toLowerCase();
            final val = (e.value ?? '').toString().trim();
            if (k.isEmpty || val.isEmpty) continue;
            labels[k] = val;
          }
        }

        out.add(PaymentWallet(
          id: id,
          enabled: enabled,
          labels: labels,
          displayName: displayName,
          number: number,
          icon: icon,
          sort: sort,
        ));
      }
    }

    // Fallback legacy schema (optional)
    if (out.isEmpty) {
      final bankily = (data['bankilyNumber'] ?? data['bankily'] ?? '').toString().trim();
      final masrivi = (data['masriviNumber'] ?? data['masrivi'] ?? '').toString().trim();
      final name = (data['receiverName'] ?? data['name'] ?? 'Tkii').toString().trim();

      if (bankily.isNotEmpty) {
        out.add(PaymentWallet(
          id: 'bankily',
          enabled: true,
          labels: const {'ar': 'بنكيلي', 'fr': 'Bankily', 'en': 'Bankily'},
          displayName: name,
          number: bankily,
          icon: 'bank',
          sort: 0,
        ));
      }
      if (masrivi.isNotEmpty) {
        out.add(PaymentWallet(
          id: 'masrivi',
          enabled: true,
          labels: const {'ar': 'مصرفي', 'fr': 'Masrivi', 'en': 'Masrivi'},
          displayName: name,
          number: masrivi,
          icon: 'bank',
          sort: 1,
        ));
      }
    }

    return out;
  }

  static bool _asBool(Object? v, {required bool fallback}) {
    if (v is bool) return v;
    final s = (v ?? '').toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return fallback;
  }

  static int _asInt(Object? v, {required int fallback}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse((v ?? '').toString()) ?? fallback;
  }
}
