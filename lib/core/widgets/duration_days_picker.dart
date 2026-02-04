import 'package:flutter/material.dart';

/// Simple day picker with presets + stepper.
/// Use [minDays]=1 and [maxDays]=60 for VIP durations.
class DurationDaysPicker extends StatelessWidget {
  const DurationDaysPicker({
    super.key,
    required this.days,
    required this.onChanged,
    this.minDays = 1,
    this.maxDays = 60,
    this.presets = const [1, 3, 7, 15, 30],
  });

  final int days;
  final ValueChanged<int> onChanged;
  final int minDays;
  final int maxDays;
  final List<int> presets;

  int _clamp(int v) => v < minDays ? minDays : (v > maxDays ? maxDays : v);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget chip(int d) {
      final selected = days == d;
      return ChoiceChip(
        label: Text('$d'),
        selected: selected,
        onSelected: (_) => onChanged(_clamp(d)),
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          color: selected ? cs.onPrimary : null,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in presets) chip(d),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              tooltip: 'ناقص يوم',
              onPressed: () => onChanged(_clamp(days - 1)),
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Expanded(
              child: Slider(
                value: _clamp(days).toDouble(),
                min: minDays.toDouble(),
                max: maxDays.toDouble(),
                divisions: (maxDays - minDays),
                label: '${_clamp(days)}',
                onChanged: (v) => onChanged(_clamp(v.round())),
              ),
            ),
            IconButton(
              tooltip: 'زِد يوم',
              onPressed: () => onChanged(_clamp(days + 1)),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        Text(
          'المدة: ${_clamp(days)} يوم (حد أقصى $maxDays)',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
