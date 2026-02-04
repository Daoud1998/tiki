import 'dart:convert';

/// A local, resumable draft for the publish/edit wizard.
///
/// Design goals:
/// - Drafts survive leaving the wizard, changing language, or app restarts.
/// - Store stable IDs (categoryId, wilayaId...) whenever possible.
/// - Keep a flexible payload in [data] so the wizard can evolve.
class PublishDraft {
  const PublishDraft({
    required this.id,
    required this.kind,
    required this.mode,
    required this.step,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.schemaVersion,
    required this.data,
    this.targetId,
    this.name,
  });

  /// Unique draft id.
  final String id;

  /// e.g. 'product' or 'ad' (future-proof).
  final String kind;

  /// 'create' or 'edit'.
  final String mode;

  /// When editing, points to the target product/ad id.
  final String? targetId;

  /// Optional user-facing label.
  final String? name;

  /// Current wizard step (0..4).
  final int step;

  /// Milliseconds since epoch.
  final int createdAtMs;
  final int updatedAtMs;

  /// Payload schema version for migrations.
  final int schemaVersion;

  /// Flexible payload (must be JSON-friendly).
  final Map<String, dynamic> data;

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedAtMs);

  PublishDraft copyWith({
    String? kind,
    String? mode,
    String? targetId,
    String? name,
    int? step,
    int? createdAtMs,
    int? updatedAtMs,
    int? schemaVersion,
    Map<String, dynamic>? data,
  }) {
    return PublishDraft(
      id: id,
      kind: kind ?? this.kind,
      mode: mode ?? this.mode,
      targetId: targetId ?? this.targetId,
      name: name ?? this.name,
      step: step ?? this.step,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      data: data ?? this.data,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'kind': kind,
      'mode': mode,
      'targetId': targetId,
      'name': name,
      'step': step,
      'createdAtMs': createdAtMs,
      'updatedAtMs': updatedAtMs,
      'schemaVersion': schemaVersion,
      'data': data,
    };
  }

  static PublishDraft? tryFromJson(dynamic raw) {
    try {
      if (raw is! Map) return null;

      final id = (raw['id'] ?? '').toString().trim();
      if (id.isEmpty) return null;

      final kind = (raw['kind'] ?? 'product').toString().trim();
      final mode = (raw['mode'] ?? 'create').toString().trim();

      final step = _toInt(raw['step'], 0);
      final createdAtMs = _toInt(raw['createdAtMs'], 0);
      final updatedAtMs = _toInt(raw['updatedAtMs'], createdAtMs);
      final schemaVersion = _toInt(raw['schemaVersion'], 1);

      final targetId = (raw['targetId'] ?? '').toString().trim();
      final name = (raw['name'] ?? '').toString().trim();

      final dataRaw = raw['data'];
      final data = <String, dynamic>{};
      if (dataRaw is Map) {
        for (final e in dataRaw.entries) {
          final k = (e.key ?? '').toString();
          if (k.isEmpty) continue;
          data[k] = e.value;
        }
      }

      final nowMs = DateTime.now().millisecondsSinceEpoch;

      return PublishDraft(
        id: id,
        kind: kind.isEmpty ? 'product' : kind,
        mode: (mode == 'edit') ? 'edit' : 'create',
        targetId: targetId.isEmpty ? null : targetId,
        name: name.isEmpty ? null : name,
        step: step.clamp(0, 10),
        createdAtMs: createdAtMs > 0 ? createdAtMs : nowMs,
        updatedAtMs: updatedAtMs > 0
            ? updatedAtMs
            : (createdAtMs > 0 ? createdAtMs : nowMs),
        schemaVersion: schemaVersion <= 0 ? 1 : schemaVersion,
        data: data,
      );
    } catch (_) {
      return null;
    }
  }

  static List<PublishDraft> decodeList(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return <PublishDraft>[];
    try {
      final decoded = jsonDecode(s);
      if (decoded is! List) return <PublishDraft>[];
      final out = <PublishDraft>[];
      for (final item in decoded) {
        final d = PublishDraft.tryFromJson(item);
        if (d != null) out.add(d);
      }
      out.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      return out;
    } catch (_) {
      return <PublishDraft>[];
    }
  }

  static String encodeList(List<PublishDraft> drafts) {
    final list = drafts.map((e) => e.toJson()).toList(growable: false);
    return jsonEncode(list);
  }

  static int _toInt(dynamic v, int fallback) {
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}'.trim()) ?? fallback;
  }
}
