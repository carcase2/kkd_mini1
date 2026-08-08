import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 탭 하단 고정 액션 바 (종료 / 기록 / 시작 등)
class StickyBottomBar extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const StickyBottomBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 12),
  });

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(
          top: BorderSide(color: c.border.withValues(alpha: 0.8)),
        ),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 풀 너비 액션 버튼 (고정 바용)
class StickyActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color? soft;
  final bool filled;
  final VoidCallback? onTap;
  final bool enabled;

  const StickyActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    this.soft,
    this.filled = true,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = enabled && onTap != null;
    final bg = filled
        ? (isEnabled ? color : color.withValues(alpha: 0.4))
        : (soft ?? color.withValues(alpha: 0.12));
    final fg = filled
        ? Colors.white
        : (isEnabled ? color : color.withValues(alpha: 0.45));

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: filled
                ? null
                : Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
