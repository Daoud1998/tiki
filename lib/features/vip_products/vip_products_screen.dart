import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Admin screen: manually control VIP on products.
///
/// - Enable VIP (days + rank)
/// - Extend VIP (days)
/// - Disable VIP
///
/// Updates product VIP fields under: products/{productId}.attrs
/// Optional: writes an inbox item for the product owner:
/// user_inbox/{sellerId}/items/{autoId}
class VipProductsScreen extends StatefulWidget {
  const VipProductsScreen({super.key});

  @override
  State<VipProductsScreen> createState() => _VipProductsScreenState();
}

class _VipProductsScreenState extends State<VipProductsScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _productIdCtl = TextEditingController();
  DocumentSnapshot<Map<String, dynamic>>? _productSnap;
  bool _loading = false;
  String? _error;

  String get _adminUid => _auth.currentUser?.uid ?? 'unknown';

  @override
  void dispose() {
    _productIdCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = _productIdCtl.text.trim();
    if (id.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _productSnap = null;
    });

    try {
      final snap = await _db.collection('products').doc(id).get();
      if (!snap.exists) {
        setState(() {
          _error = 'Product not found';
          _loading = false;
        });
        return;
      }

      setState(() {
        _productSnap = snap;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Load failed: $e';
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _attrs(Map<String, dynamic> d) {
    final a = d['attrs'];
    return a is Map<String, dynamic> ? a : <String, dynamic>{};
  }

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return fallback;
  }

  String _asStr(dynamic v) => (v ?? '').toString();

  DateTime? _msToDate(int ms) =>
      ms <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);

  Future<void> _enableOrExtend({required bool extend}) async {
    final snap = _productSnap;
    if (snap == null) return;

    final d = snap.data() ?? <String, dynamic>{};
    final productId = snap.id;

    final sellerId = _asStr(d['sellerId']);
    final title = _asStr(d['title']);
    final attrs = _attrs(d);

    final currentUntilMs = _asInt(attrs['vipUntilMs']);
    final currentRank = _asInt(attrs['vipRank'], fallback: 1);

    final result = await _showVipDialog(
      context: context,
      extend: extend,
      defaultDays: 7,
      defaultRank: currentRank <= 0 ? 1 : currentRank,
      showRank: !extend,
    );

    if (result == null) return;

    final days = result.days;
    final rank = result.rank;

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final baseMs = (extend && currentUntilMs > nowMs) ? currentUntilMs : nowMs;
    final untilMs = DateTime.fromMillisecondsSinceEpoch(baseMs)
        .add(Duration(days: days))
        .millisecondsSinceEpoch;

    final updates = <String, dynamic>{
      'attrs.vipStatus': 'approved',
      'attrs.vipUntilMs': untilMs,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtMs': nowMs,
      'attrs.vipApprovedBy': _adminUid,
    };

    if (!extend) {
      updates['attrs.vipRank'] = rank;
      updates['attrs.vipApprovedAt'] = FieldValue.serverTimestamp();
    }

    try {
      setState(() => _loading = true);

      await _db.runTransaction((tx) async {
        tx.update(_db.collection('products').doc(productId), updates);

        if (sellerId.isNotEmpty) {
          final inboxRef = _db
              .collection('user_inbox')
              .doc(sellerId)
              .collection('items')
              .doc();
          tx.set(inboxRef, {
            'type': 'vip_product',
            'status': extend ? 'extended' : 'enabled',
            'productId': productId,
            'title': {
              'ar': extend ? 'تم تمديد VIP' : 'تم تفعيل VIP',
              'fr': extend ? 'VIP prolongé' : 'VIP activé',
              'en': extend ? 'VIP extended' : 'VIP enabled',
            },
            'body': {
              'ar': extend
                  ? 'تم تمديد VIP لمنتجك ${title.isEmpty ? "" : "($title)"} لمدة $days يوم.'
                  : 'تم تفعيل VIP لمنتجك ${title.isEmpty ? "" : "($title)"} لمدة $days يوم.',
              'fr': extend
                  ? 'VIP prolongé $days jours.'
                  : 'VIP activé $days jours.',
              'en': extend
                  ? 'VIP extended for $days days.'
                  : 'VIP enabled for $days days.',
            },
            'targetRoute': '/product/$productId',
            'createdAt': FieldValue.serverTimestamp(),
            'createdAtMs': nowMs,
            'read': false,
          });
        }
      });

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(extend ? 'Extended ✅' : 'Enabled ✅')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _disableVip() async {
    final snap = _productSnap;
    if (snap == null) return;

    final d = snap.data() ?? <String, dynamic>{};
    final productId = snap.id;
    final sellerId = _asStr(d['sellerId']);
    final title = _asStr(d['title']);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disable VIP'),
        content: const Text(
            'Are you sure you want to disable VIP for this product?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Disable')),
        ],
      ),
    );

    if (ok != true) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final updates = <String, dynamic>{
      'attrs.vipStatus': 'none',
      'attrs.vipRank': 0,
      'attrs.vipUntilMs': 0,
      'attrs.vipApprovedAt': FieldValue.delete(),
      'attrs.vipApprovedBy': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedAtMs': nowMs,
    };

    try {
      setState(() => _loading = true);

      await _db.runTransaction((tx) async {
        tx.update(_db.collection('products').doc(productId), updates);

        if (sellerId.isNotEmpty) {
          final inboxRef = _db
              .collection('user_inbox')
              .doc(sellerId)
              .collection('items')
              .doc();
          tx.set(inboxRef, {
            'type': 'vip_product',
            'status': 'disabled',
            'productId': productId,
            'title': {
              'ar': 'تم إيقاف VIP',
              'fr': 'VIP désactivé',
              'en': 'VIP disabled'
            },
            'body': {
              'ar': 'تم إيقاف VIP لمنتجك ${title.isEmpty ? "" : "($title)"}',
              'fr': 'Votre VIP a été désactivé.',
              'en': 'Your VIP was disabled.',
            },
            'targetRoute': '/product/$productId',
            'createdAt': FieldValue.serverTimestamp(),
            'createdAtMs': nowMs,
            'read': false,
          });
        }
      });

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disabled ✅')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Disable failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = _productSnap;
    final data = snap?.data() ?? <String, dynamic>{};
    final attrs = _attrs(data);

    final vipStatus = _asStr(attrs['vipStatus']);
    final vipRank = _asInt(attrs['vipRank']);
    final vipUntilMs = _asInt(attrs['vipUntilMs']);
    final vipUntil = _msToDate(vipUntilMs);

    final sellerId = _asStr(data['sellerId']);
    final title = _asStr(data['title']);
    final status = _asStr(data['status']);

    return Scaffold(
      appBar: AppBar(title: const Text('VIP Products')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _productIdCtl,
                    decoration: const InputDecoration(
                      labelText: 'Product ID',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.search),
                  label: const Text('Load'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              _Card(
                  child:
                      Text(_error!, style: const TextStyle(color: Colors.red))),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator()),
            if (snap != null) ...[
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.isEmpty ? 'Product' : title,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    _kv('Product ID', snap.id),
                    _kv('Seller', sellerId.isEmpty ? '-' : sellerId),
                    _kv('Status', status.isEmpty ? '-' : status),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('VIP', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    _kv('vipStatus', vipStatus.isEmpty ? '-' : vipStatus),
                    _kv('vipRank', vipRank.toString()),
                    _kv('vipUntil',
                        vipUntil == null ? '-' : vipUntil.toLocal().toString()),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: _loading
                              ? null
                              : () => _enableOrExtend(extend: false),
                          icon: const Icon(Icons.workspace_premium),
                          label: const Text('Enable VIP'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _loading
                              ? null
                              : () => _enableOrExtend(extend: true),
                          icon: const Icon(Icons.add),
                          label: const Text('Extend VIP'),
                        ),
                        TextButton.icon(
                          onPressed: _loading ? null : _disableVip,
                          icon: const Icon(Icons.block),
                          label: const Text('Disable VIP'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child:
                  Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}

class _VipDialogResult {
  final int days;
  final int rank;
  const _VipDialogResult({required this.days, required this.rank});
}

Future<_VipDialogResult?> _showVipDialog({
  required BuildContext context,
  required bool extend,
  required int defaultDays,
  required int defaultRank,
  required bool showRank,
}) async {
  final daysCtl = TextEditingController(text: defaultDays.toString());
  int rank = defaultRank;

  return showDialog<_VipDialogResult>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(extend ? 'Extend VIP' : 'Enable VIP'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: daysCtl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Days',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          if (showRank)
            DropdownButtonFormField<int>(
              value: rank,
              decoration: const InputDecoration(
                labelText: 'Rank',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 1, child: Text('Rank 1')),
                DropdownMenuItem(value: 2, child: Text('Rank 2')),
                DropdownMenuItem(value: 3, child: Text('Rank 3')),
              ],
              onChanged: (v) => rank = v ?? 1,
            )
          else
            const Text('Rank will remain unchanged.'),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final days = int.tryParse(daysCtl.text.trim()) ?? defaultDays;
            Navigator.pop(
                ctx,
                _VipDialogResult(
                    days: days <= 0 ? defaultDays : days, rank: rank));
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
