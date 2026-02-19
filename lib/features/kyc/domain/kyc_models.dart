import 'package:flutter/foundation.dart';

/// Verification settings controlled by Admin (ideally via Firestore).
///
/// By default it's **disabled** so it won't block publishing until you enable it.
@immutable
class KycSettings {
  const KycSettings({
    required this.enabled,
    required this.mode,
    required this.graceAdsCount,
    required this.priceThresholdMru,
    required this.requiredCategories,
    required this.unverifiedAdsLimit,
  });

  /// Master switch.
  final bool enabled;

  /// "optional" | "high_risk_only" | "after_grace" | "on_publish" | "payments_only"
  final String mode;

  /// Allow the first N publishes without verification (used in "after_grace").
  final int graceAdsCount;

  /// If price is >= this threshold, verification becomes required (in high-risk modes).
  final int priceThresholdMru;

  /// Category ids that are considered high risk (e.g. vehicles, real_estate).
  final List<String> requiredCategories;

  /// A hard limit for unverified accounts (can be used even when mode is optional).
  final int unverifiedAdsLimit;

  static KycSettings defaults() => const KycSettings(
        enabled: false,
        mode: 'optional',
        graceAdsCount: 2,
        priceThresholdMru: 10000,
        requiredCategories: <String>['vehicles', 'real_estate'],
        unverifiedAdsLimit: 2,
      );

  static KycSettings fromMap(Map<String, dynamic> m) {
    final d = defaults();
    return KycSettings(
      enabled: (m['enabled'] as bool?) ?? d.enabled,
      mode: (m['mode'] as String?) ?? d.mode,
      graceAdsCount: (m['graceAdsCount'] as num?)?.toInt() ??
          (m['grace_ads_count'] as num?)?.toInt() ??
          d.graceAdsCount,
      priceThresholdMru: (m['priceThresholdMru'] as num?)?.toInt() ??
          (m['price_threshold_mru'] as num?)?.toInt() ??
          d.priceThresholdMru,
      requiredCategories: (m['requiredCategories'] as List?)
              ?.whereType<String>()
              .toList() ??
          (m['required_categories'] as List?)?.whereType<String>().toList() ??
          d.requiredCategories,
      unverifiedAdsLimit: (m['unverifiedAdsLimit'] as num?)?.toInt() ??
          (m['unverified_ads_limit'] as num?)?.toInt() ??
          d.unverifiedAdsLimit,
    );
  }
}

@immutable
class KycDecision {
  const KycDecision({required this.required, required this.reason});

  final bool required;

  /// Human-readable reason key (for UI).
  final String reason;
}

class KycPolicy {
  static KycDecision decide({
    required KycSettings settings,
    required String? categoryId,
    required int? priceMru,
    required int publishedCount,
    required String kycStatus, // 'none'|'pending'|'approved'|'rejected'
  }) {
    if (!settings.enabled) {
      return const KycDecision(required: false, reason: 'disabled');
    }

    if (kycStatus == 'approved') {
      return const KycDecision(required: false, reason: 'approved');
    }

    // Hard limit for unverified accounts (if enabled).
    if (settings.unverifiedAdsLimit > 0 &&
        publishedCount >= settings.unverifiedAdsLimit) {
      return const KycDecision(required: true, reason: 'limit');
    }

    // Optional mode: never blocks publish (but the hard limit above can still apply).
    if (settings.mode == 'optional' || settings.mode == 'payments_only') {
      return const KycDecision(required: false, reason: 'optional');
    }

    if (settings.mode == 'on_publish') {
      return const KycDecision(required: true, reason: 'on_publish');
    }

    if (settings.mode == 'after_grace') {
      if (publishedCount >= settings.graceAdsCount) {
        return const KycDecision(required: true, reason: 'after_grace');
      }
      return const KycDecision(required: false, reason: 'grace');
    }

    // high_risk_only
    final cat = (categoryId ?? '').trim();
    final inRisk = cat.isNotEmpty && settings.requiredCategories.contains(cat);

    final p = (priceMru ?? 0);
    final priceKnown = p > 0;
    final priceHigh = priceKnown && p >= settings.priceThresholdMru;

    if (inRisk) {
      return const KycDecision(required: true, reason: 'category');
    }
    if (priceHigh) {
      return const KycDecision(required: true, reason: 'price');
    }

    return const KycDecision(required: false, reason: 'low_risk');
  }
}

@immutable
class KycVerificationUiSettings {
  const KycVerificationUiSettings({
    required this.allowInApp,
    required this.allowWhatsApp,
    required this.whatsAppNumber,
    required this.whatsAppTemplateAr,
    required this.whatsAppTemplateFr,
    required this.whatsAppTemplateEn,
    required this.benefitsAr,
    required this.benefitsFr,
    required this.benefitsEn,
    required this.fastTrackCategories,
  });

  /// Show the "verify in-app" flow (upload document + selfie).
  final bool allowInApp;

  /// Show the "verify via WhatsApp" option.
  final bool allowWhatsApp;

  /// Support WhatsApp number in E.164 format, e.g. +222XXXXXXXX
  final String whatsAppNumber;

  /// WhatsApp message templates.
  ///
  /// Supported placeholders:
  /// - {{uid}}
  /// - {{name}}
  /// - {{phone}}
  final String whatsAppTemplateAr;
  final String whatsAppTemplateFr;
  final String whatsAppTemplateEn;

  /// Benefit lines (one line per bullet).
  final List<String> benefitsAr;
  final List<String> benefitsFr;
  final List<String> benefitsEn;

  /// Category ids that get faster moderation when verified (UI hint only).
  final List<String> fastTrackCategories;

  static KycVerificationUiSettings defaults() =>
      const KycVerificationUiSettings(
        allowInApp: true,
        allowWhatsApp: true,
        whatsAppNumber: '+22236566606',
        whatsAppTemplateAr:
            'السلام عليكم، أريد توثيق حسابي في تيكي.\nUID: {{uid}}\nالاسم: {{name}}\nالهاتف: {{phone}}\nسأرسل: (وثيقة + سيلفي)',
        whatsAppTemplateFr:
            'Bonjour, je souhaite vérifier mon compte sur Tkii.\nUID: {{uid}}\nNom: {{name}}\nTéléphone: {{phone}}\nJe vais envoyer: (Document + selfie)',
        whatsAppTemplateEn:
            'Hello, I want to verify my account on Tkii.\nUID: {{uid}}\nName: {{name}}\nPhone: {{phone}}\nI will send: (Document + selfie)',
        benefitsAr: <String>[
          '✅ معاينة أسرع (غالباً أقل من دقيقة)',
          '✅ نشر غير محدود (حسب سياسة الإدارة)',
          '✅ نشر أسرع لفئات: العقارات، السيارات، الهواتف',
        ],
        benefitsFr: <String>[
          '✅ Examen plus rapide (souvent moins d’une minute)',
          '✅ Publication plus flexible (selon la politique admin)',
          '✅ Publication plus rapide: immobilier, voitures, téléphones',
        ],
        benefitsEn: <String>[
          '✅ Faster review (often under a minute)',
          '✅ More flexible posting (per admin policy)',
          '✅ Faster posting: real estate, cars, phones',
        ],
        fastTrackCategories: <String>['real_estate', 'cars', 'phones'],
      );

  static bool _asBool(dynamic v, bool d) {
    if (v == null) return d;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return d;
  }

  static String _asStr(dynamic v, String d) {
    if (v == null) return d;
    final s = v.toString().trim();
    return s.isEmpty ? d : s;
  }

  static List<String> _asStrList(dynamic v) {
    if (v == null) return const <String>[];
    if (v is List) {
      return v
          .map((e) => e == null ? '' : e.toString())
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  String whatsAppTemplateFor(String languageCode) {
    final c = languageCode.trim().toLowerCase();
    if (c == 'fr') return whatsAppTemplateFr.isNotEmpty ? whatsAppTemplateFr : whatsAppTemplateAr;
    if (c == 'en') return whatsAppTemplateEn.isNotEmpty ? whatsAppTemplateEn : whatsAppTemplateAr;
    return whatsAppTemplateAr;
  }

  List<String> benefitsFor(String languageCode) {
    final c = languageCode.trim().toLowerCase();
    if (c == 'fr') return benefitsFr.isNotEmpty ? benefitsFr : benefitsAr;
    if (c == 'en') return benefitsEn.isNotEmpty ? benefitsEn : benefitsAr;
    return benefitsAr;
  }

  static KycVerificationUiSettings fromMap(Map<String, dynamic> m) {
    final d = defaults();

    final benefitsAr = _asStrList(m['benefitsAr']);
    final benefitsFr = _asStrList(m['benefitsFr']);
    final benefitsEn = _asStrList(m['benefitsEn']);

    final cats = _asStrList(m['fastTrackCategories']);

    return KycVerificationUiSettings(
      allowInApp: _asBool(m['allowInApp'], d.allowInApp),
      allowWhatsApp: _asBool(m['allowWhatsApp'], d.allowWhatsApp),
      whatsAppNumber: _asStr(m['whatsAppNumber'], d.whatsAppNumber),
      whatsAppTemplateAr: _asStr(m['whatsAppTemplateAr'], d.whatsAppTemplateAr),
      whatsAppTemplateFr: _asStr(m['whatsAppTemplateFr'], d.whatsAppTemplateFr),
      whatsAppTemplateEn: _asStr(m['whatsAppTemplateEn'], d.whatsAppTemplateEn),
      benefitsAr: benefitsAr.isEmpty ? d.benefitsAr : benefitsAr,
      benefitsFr: benefitsFr.isEmpty ? d.benefitsFr : benefitsFr,
      benefitsEn: benefitsEn.isEmpty ? d.benefitsEn : benefitsEn,
      fastTrackCategories: cats.isEmpty ? d.fastTrackCategories : cats,
    );
  }
}
