import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/admin_access.dart';
import '../theme/rema_colors.dart';

class _NavItem {
  const _NavItem(this.label, this.icon, this.route, {this.shortLabel});

  final String label;
  final String? shortLabel;
  final IconData icon;
  final String route;
}

const _navItems = <_NavItem>[
  _NavItem('Levantamiento', Icons.architecture, '/levantamiento', shortLabel: 'Levant.'),
  _NavItem('Mis Levantamientos', Icons.assignment_turned_in, '/surveys-staff', shortLabel: 'Mis Lev.'),
  _NavItem('Cotizacion', Icons.request_quote, '/cotizaciones', shortLabel: 'Cotiz.'),
  _NavItem('Actas', Icons.description, '/actas'),
  _NavItem('Clientes', Icons.group, '/clientes'),
  _NavItem('Catalogo', Icons.inventory_2, '/catalogo', shortLabel: 'Catalogo'),
  _NavItem('Ajustes', Icons.settings, '/ajustes'),
];

class RemaShell extends ConsumerWidget {
  const RemaShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1024;
    final isAdmin = ref.watch(isAdminProvider);
    final navItems = isAdmin
        ? _navItems
        : [
            for (final item in _navItems)
              if (item.route == '/levantamiento' || item.route == '/surveys-staff' || item.route == '/ajustes') item,
          ];

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            _DesktopNav(location: location, navItems: navItems),
            Expanded(child: SelectionArea(child: child)),
          ],
        ),
      );
    }

    return Scaffold(
      body: SelectionArea(child: child),
      bottomNavigationBar: _MobileNav(location: location, navItems: navItems),
      floatingActionButton: location == '/clientes'
          ? FloatingActionButton(
              onPressed: () => context.go('/nuevo-cliente'),
              backgroundColor: RemaColors.primary,
              foregroundColor: const Color(0xFF694C00),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
              child: const Icon(Icons.person_add),
            )
          : null,
    );
  }
}

class _DesktopNav extends StatelessWidget {
  const _DesktopNav({required this.location, required this.navItems});

  final String location;
  final List<_NavItem> navItems;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      color: RemaColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 36, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'REMA\nARQUITECTURA',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 28),
          for (final item in navItems)
            _DesktopNavTile(
              item: item,
              isActive: location.startsWith(item.route),
            ),
        ],
      ),
    );
  }
}

class _DesktopNavTile extends StatelessWidget {
  const _DesktopNavTile({required this.item, required this.isActive});

  final _NavItem item;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(item.route),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? RemaColors.surfaceLow : Colors.transparent,
          border: isActive
              ? const Border(
                  bottom: BorderSide(color: RemaColors.primary, width: 2),
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(item.icon,
                size: 18,
                color: isActive
                    ? RemaColors.primaryDark
                    : RemaColors.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? RemaColors.primaryDark
                      : RemaColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileNav extends StatelessWidget {
  const _MobileNav({required this.location, required this.navItems});

  final String location;
  final List<_NavItem> navItems;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          color: RemaColors.surface.withValues(alpha: 0.86),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              for (final item in navItems)
                Expanded(
                  child: _MobileNavTile(
                    item: item,
                    isActive: location.startsWith(item.route),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileNavTile extends StatelessWidget {
  const _MobileNavTile({required this.item, required this.isActive});

  final _NavItem item;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final mobileLabel = item.shortLabel ?? item.label;

    return InkWell(
      onTap: () => context.go(item.route),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              size: 18,
              color: isActive ? RemaColors.primaryDark : RemaColors.onSurfaceVariant,
            ),
            const SizedBox(height: 2),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  mobileLabel,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.2,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? RemaColors.primaryDark : RemaColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
