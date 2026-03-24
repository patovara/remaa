import 'package:flutter/material.dart';

import '../theme/rema_colors.dart';

class RemaPanel extends StatelessWidget {
  const RemaPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(28),
    this.backgroundColor = RemaColors.surfaceWhite,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: child,
    );
  }
}

class RemaSectionHeader extends StatelessWidget {
  const RemaSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Expanded(
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: RemaColors.primaryDark, size: 20),
              const SizedBox(width: 8),
            ],
            Container(
              width: 4,
              height: 24,
              color: RemaColors.primary,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    ];

    if (trailing case final trailingWidget?) {
      children.add(trailingWidget);
    }

    return Row(children: children);
  }
}

class RemaMetricTile extends StatelessWidget {
  const RemaMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.backgroundColor = RemaColors.surfaceLow,
    this.foregroundColor = RemaColors.onSurface,
  });

  final String label;
  final String value;
  final String? caption;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 152),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foregroundColor.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
          ),
          const SizedBox(height: 28),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: foregroundColor,
                ),
          ),
          if (caption case final captionText?) ...[
            const SizedBox(height: 6),
            Text(
              captionText,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foregroundColor.withValues(alpha: 0.65),
                  ),
            ),
          ],
        ],
      ),
    );
  }
}