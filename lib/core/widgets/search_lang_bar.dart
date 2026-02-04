import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tiki/app/localization/l10n.dart';
import 'package:tiki/core/utils/helper.dart';

/// Reusable, Temu-like header row: search pill (optionally with camera).
///
/// RTL note:
/// This widget respects [Directionality]. Avoid forcing LTR layout here.
class TikkiSearchLangBar extends StatelessWidget {
  const TikkiSearchLangBar({
    super.key,
    required this.hint,
    this.padding = const EdgeInsetsDirectional.fromSTEB(14, 8, 14, 6),
    this.showCameraButton = true,
    this.onSearchTap,
    this.onCameraTap,
  });

  final String hint;
  final EdgeInsetsGeometry padding;
  final bool showCameraButton;
  final VoidCallback? onSearchTap;
  final VoidCallback? onCameraTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: padding,
      child: _TemuSearchPill(
        hint: hint,
        showCameraButton: showCameraButton,
        onSearchTap: onSearchTap ?? () => context.go('/search'),
        onCameraTap: () {
          if (onCameraTap != null) {
            onCameraTap!();
            return;
          }
          // Default: open image search (same as Home). Keep it safe.
          try {
            context.push('/search?img=1');
          } catch (_) {
            showQuickSnack(
              context,
              context.tr('common.unavailable_feature'),
            );
          }
        },
      ),
    );
  }
}

class _TemuSearchPill extends StatelessWidget {
  const _TemuSearchPill({
    required this.hint,
    required this.showCameraButton,
    required this.onSearchTap,
    required this.onCameraTap,
  });

  final String hint;
  final bool showCameraButton;
  final VoidCallback onSearchTap;
  final VoidCallback onCameraTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Temu-like pill
    final pillBg = isDark ? cs.surface : Colors.white;
    final borderColor =
        isDark ? cs.outline.withOpacity(0.50) : const Color(0xFFE2E2E2);

    // Black circle in light mode; in dark mode use primary so it stays visible.
    final circleColor = isDark ? cs.primary : Colors.black;
    final iconOnCircle = Colors.white;

    final cameraColor = isDark ? cs.onSurface : const Color(0xFF111111);
    final hintColor = cs.onSurface.withOpacity(isDark ? 0.78 : 0.58);

    final tooltipCamera = context.tr('common.camera');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onSearchTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: pillBg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // Text stays at the start (RTL/LTR). Icons stay at the end, like Temu.
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: hintColor,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.start,
                  ),
                ),
              ),

              if (showCameraButton) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: onCameraTap,
                  icon: const Icon(Icons.camera_alt_outlined, size: 21),
                  color: cameraColor,
                  tooltip: tooltipCamera,
                ),
                const SizedBox(width: 4),
              ],

              InkResponse(
                radius: 18,
                onTap: onSearchTap,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: circleColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.search, color: iconOnCircle, size: 19),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
