import 'package:flutter/material.dart';

import '../../../core/theme/rema_colors.dart';

class AuthFrame extends StatelessWidget {
  const AuthFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.cardChild,
    this.bottomChild,
  });

  final String title;
  final String subtitle;
  final Widget cardChild;
  final Widget? bottomChild;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1024;

    return Scaffold(
      body: Stack(
        children: [
          const _AuthBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isDesktop ? 980 : 540),
                  child: isDesktop
                      ? IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Expanded(child: _DesktopBrandPanel()),
                              const SizedBox(width: 24),
                              Expanded(
                                child: _AuthCard(
                                  title: title,
                                  subtitle: subtitle,
                                  bottomChild: bottomChild,
                                  child: cardChild,
                                ),
                              ),
                            ],
                          ),
                        )
                      : _AuthCard(
                          title: title,
                          subtitle: subtitle,
                          bottomChild: bottomChild,
                          child: cardChild,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthBackground extends StatelessWidget {
  const _AuthBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: RemaColors.surface,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF9F9F9), Color(0xFFF0F0F1)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(),
            ),
          ),
          const Positioned(
            top: -120,
            right: -120,
            child: _BlurCircle(color: Color(0x22F7BB22)),
          ),
          const Positioned(
            bottom: -120,
            left: -120,
            child: _BlurCircle(color: Color(0x14795900)),
          ),
        ],
      ),
    );
  }
}

class _BlurCircle extends StatelessWidget {
  const _BlurCircle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      height: 320,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _DesktopBrandPanel extends StatelessWidget {
  const _DesktopBrandPanel();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Image.asset(
            'assets/images/logo_remaa.png',
            height: 58,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 28),
          Text(
            'REMA ARQUITECTURA',
            style: textTheme.headlineMedium?.copyWith(
              letterSpacing: 1.8,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Portal de gestion de proyectos, clientes y cotizaciones.',
            style: textTheme.bodyMedium?.copyWith(
              color: RemaColors.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            'SECURE PORTAL',
            style: textTheme.labelSmall?.copyWith(
              letterSpacing: 2.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.bottomChild,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? bottomChild;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        border: Border.all(color: RemaColors.outlineVariant.withValues(alpha: 0.15)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x141A1C1C),
            blurRadius: 32,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (MediaQuery.sizeOf(context).width < 1024) ...[
            Align(
              alignment: Alignment.center,
              child: Image.asset(
                'assets/images/logo_remaa.png',
                height: 54,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 14),
          ],
          Text(title, style: textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: textTheme.bodyMedium?.copyWith(color: RemaColors.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  child,
                  if (bottomChild != null) ...[
                    const SizedBox(height: 18),
                    bottomChild!,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = 1;

    const step = 40.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
