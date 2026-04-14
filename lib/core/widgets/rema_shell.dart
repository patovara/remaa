import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/admin_access.dart';
import '../theme/rema_colors.dart';

class _NavItem {
  const _NavItem(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}

const _navItems = <_NavItem>[
  _NavItem('Levantamiento', Icons.architecture, '/levantamiento'),
  _NavItem('Mis Levantamientos', Icons.assignment_turned_in, '/surveys-staff'),
  _NavItem('Cotizacion', Icons.request_quote, '/cotizaciones'),
  _NavItem('Actas', Icons.description, '/actas'),
  _NavItem('Clientes', Icons.group, '/clientes'),
  _NavItem('Catalogo', Icons.inventory_2, '/catalogo'),
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

class _MobileNav extends StatefulWidget {
  const _MobileNav({required this.location, required this.navItems});

  final String location;
  final List<_NavItem> navItems;

  @override
  State<_MobileNav> createState() => _MobileNavState();
}

class _MobileNavState extends State<_MobileNav> {
  late final ScrollController _scrollController;
  bool _showLeftHint = false;
  bool _showRightHint = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_updateEdgeHints);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateEdgeHints());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateEdgeHints)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MobileNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateEdgeHints());
  }

  void _updateEdgeHints() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    final showLeft = position.pixels > 2;
    final showRight = position.maxScrollExtent - position.pixels > 2;
    if (showLeft == _showLeftHint && showRight == _showRightHint) {
      return;
    }
    setState(() {
      _showLeftHint = showLeft;
      _showRightHint = showRight;
    });
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!_scrollController.hasClients || event is! PointerScrollEvent) {
      return;
    }
    final delta = event.scrollDelta.dx != 0 ? event.scrollDelta.dx : event.scrollDelta.dy;
    _scrollBy(delta);
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    _scrollBy(-details.delta.dx);
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients || delta == 0) {
      return;
    }
    final position = _scrollController.position;
    final target =
        (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
    if (target == position.pixels) {
      return;
    }
    _scrollController.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          color: RemaColors.surface.withValues(alpha: 0.86),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Listener(
            onPointerSignal: _handlePointerSignal,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: _handleHorizontalDragUpdate,
              child: Stack(
                children: [
                  ScrollConfiguration(
                    behavior: const MaterialScrollBehavior().copyWith(
                      scrollbars: false,
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.stylus,
                        PointerDeviceKind.unknown,
                      },
                    ),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      dragStartBehavior: DragStartBehavior.down,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          for (final item in widget.navItems)
                            _MobileNavTile(
                              item: item,
                              isActive: widget.location.startsWith(item.route),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_showLeftHint)
                    const Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: _ScrollHintEdge(isLeft: true),
                      ),
                    ),
                  if (_showRightHint)
                    const Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: _ScrollHintEdge(isLeft: false),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrollHintEdge extends StatelessWidget {
  const _ScrollHintEdge({required this.isLeft});

  final bool isLeft;

  @override
  Widget build(BuildContext context) {
    final icon = isLeft ? Icons.chevron_left : Icons.chevron_right;
    final begin = isLeft ? Alignment.centerLeft : Alignment.centerRight;
    final end = isLeft ? Alignment.centerRight : Alignment.centerLeft;
    return Container(
      width: 28,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: begin,
          end: end,
          colors: [
            RemaColors.surface.withValues(alpha: 0.95),
            RemaColors.surface.withValues(alpha: 0),
          ],
        ),
      ),
      child: Align(
        alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
        child: Icon(icon, size: 16, color: RemaColors.onSurfaceVariant.withValues(alpha: 0.8)),
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
    return InkWell(
      onTap: () => context.go(item.route),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              size: 20,
              color: isActive ? RemaColors.primaryDark : RemaColors.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? RemaColors.primaryDark : RemaColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
