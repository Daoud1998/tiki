import 'package:flutter/material.dart';

import '../../../core/i18n/tikki_tr.dart';
import '../../../core/widgets/dir_chevrons.dart';

class KycSection extends StatelessWidget {
  const KycSection({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: t.colorScheme.primary),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(title, style: t.textTheme.titleMedium),
            ),
          ],
        ),
        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: t.textTheme.bodySmall),
        ],
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class KycHeaderCard extends StatelessWidget {
  const KycHeaderCard({
    super.key,
    required this.statusLabel,
    required this.statusIcon,
    required this.enabled,
  });

  final String statusLabel;
  final IconData statusIcon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final enabledLabel = enabled
        ? tikkiTr(context, ar: 'مفعّل', fr: 'Actif', en: 'Enabled')
        : tikkiTr(context, ar: 'مطفأ', fr: 'Désactivé', en: 'Disabled');

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: t.colorScheme.primaryContainer,
              ),
              child: Icon(Icons.verified_outlined,
                  color: t.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _KycChip(
                        icon: statusIcon,
                        label: statusLabel,
                      ),
                      _KycChip(
                        icon: enabled ? Icons.toggle_on : Icons.toggle_off,
                        label: enabledLabel,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tikkiTr(
                      context,
                      ar:
                          'التوثيق يزيد الثقة ويقلل الحسابات الوهمية. لا نعرض هويتك للناس.',
                      fr:
                          'La vérification renforce la confiance. Votre identité reste privée.',
                      en:
                          'Verification increases trust. Your identity stays private.',
                    ),
                    style: t.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class KycOptionCard extends StatelessWidget {
  const KycOptionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.badge,
    this.enabled = true,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String? badge;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    final cardColor = enabled ? null : t.colorScheme.surfaceVariant;
    final iconBg = enabled ? t.colorScheme.secondaryContainer : t.colorScheme.surfaceVariant;
    final iconFg = enabled ? t.colorScheme.onSecondaryContainer : t.colorScheme.onSurfaceVariant;

    return Card(
      elevation: 0,
      color: cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: iconBg,
                ),
                child: Icon(icon, color: iconFg),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(title, style: t.textTheme.titleSmall),
                        ),
                        if (badge != null && badge!.trim().isNotEmpty)
                          _Badge(label: badge!, dim: !enabled),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(subtitle, style: t.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              enabled
                  ? DirChevrons.forward(context, color: t.colorScheme.onSurfaceVariant)
                  : const Icon(Icons.lock_outline),
            ],
          ),
        ),
      ),
    );
  }
}

class KycHintCard extends StatelessWidget {
  const KycHintCard({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: t.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: t.textTheme.bodySmall)),
            if (action != null) ...[
              const SizedBox(width: 10),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class KycValueRow extends StatelessWidget {
  const KycValueRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: t.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(label, style: t.textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              style: t.textTheme.bodyMedium?.copyWith(
                color: t.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _KycChip extends StatelessWidget {
  const _KycChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: t.colorScheme.surfaceVariant,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: t.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.dim});

  final String label;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: dim ? t.colorScheme.surfaceVariant : t.colorScheme.primaryContainer,
      ),
      child: Text(
        label,
        style: t.textTheme.labelSmall?.copyWith(
          color: dim ? t.colorScheme.onSurfaceVariant : t.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
