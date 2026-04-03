import 'package:flutter/material.dart';

import '../theme/rema_colors.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 1024;
    final isMobile = screenWidth < 600;
    final horizontalPadding = isDesktop ? 40.0 : 20.0;
    final subtitleText = subtitle;

    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (subtitleText != null) const SizedBox(height: 8),
        if (subtitleText != null)
          Text(
            subtitleText,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: RemaColors.onSurfaceVariant),
          ),
      ],
    );

    final Widget headerContent;
    if (trailing == null) {
      headerContent = titleColumn;
    } else if (isMobile) {
      headerContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleColumn,
          const SizedBox(height: 12),
          trailing!,
        ],
      );
    } else {
      headerContent = Row(
        children: [
          Expanded(child: titleColumn),
          trailing!,
        ],
      );
    }

    return SafeArea(
      child: Container(
        color: RemaColors.surface,
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                20,
                horizontalPadding,
                12,
              ),
              child: headerContent,
            ),
            const Divider(height: 1, color: Color(0x10D3C5AD)),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 120),
                child: SizedBox(
                  width: double.infinity,
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
