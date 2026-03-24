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
    final isDesktop = MediaQuery.sizeOf(context).width >= 1024;
    final horizontalPadding = isDesktop ? 40.0 : 20.0;
    final subtitleText = subtitle;
    final headerChildren = <Widget>[
      Expanded(
        child: Column(
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
        ),
      ),
    ];
    if (trailing != null) {
      headerChildren.add(trailing!);
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
              child: Row(children: headerChildren),
            ),
            const Divider(height: 1, color: Color(0x10D3C5AD)),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(horizontalPadding, 24, horizontalPadding, 120),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
