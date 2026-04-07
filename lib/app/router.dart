import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_bootstrap.dart';
import '../core/widgets/rema_shell.dart';
import '../features/ajustes/presentation/ajustes_page.dart';
import '../features/actas/presentation/actas_page.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/register_page.dart';
import '../features/catalogo/presentation/catalogo_page.dart';
import '../features/clientes/presentation/cliente_detalle_page.dart';
import '../features/clientes/presentation/clientes_page.dart';
import '../features/cotizaciones/presentation/cotizaciones_page.dart';
import '../features/levantamiento/presentation/levantamiento_page.dart';
import '../features/nuevo_cliente/presentation/nuevo_cliente_page.dart';
import '../features/presupuesto/presentation/presupuesto_page.dart';
import '../features/surveys_staff/presentation/surveys_staff_page.dart';

final _authRefresh = _AuthRefreshListenable();

const _staffAllowedRoutes = <String>{
  '/levantamiento',
  '/surveys-staff',
  '/ajustes',
};

final appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: _authRefresh,
  redirect: (context, state) {
    final location = state.matchedLocation;
    final isAuthRoute = location == '/login' || location == '/register';
    final hasSession = SupabaseBootstrap.client?.auth.currentSession != null;
    final isActive = _isCurrentUserActive();
    final isAdmin = _isAdminSession();

    if (!hasSession && !isAuthRoute) {
      return '/login';
    }
    if (hasSession && !isActive && !isAuthRoute) {
      SupabaseBootstrap.client?.auth.signOut();
      return '/login';
    }
    if (hasSession && isAuthRoute) {
      // Invited/reset users land on /register?mode=invite with a new session.
      // Allow them through so they can set their password.
      if (location == '/register') {
        final mode = state.uri.queryParameters['mode'];
        if (mode == 'invite' || mode == 'reset') return null;
      }
      return '/levantamiento';
    }
    if (hasSession && !isAdmin && !_staffAllowedRoutes.contains(location)) {
      return '/levantamiento';
    }
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) => const NoTransitionPage(
        child: LoginPage(),
      ),
    ),
    GoRoute(
      path: '/register',
      pageBuilder: (context, state) => NoTransitionPage(
        child: RegisterPage(mode: state.uri.queryParameters['mode']),
      ),
    ),
    ShellRoute(
      builder: (context, state, child) {
        return RemaShell(location: state.uri.toString(), child: child);
      },
      routes: [
        GoRoute(
          path: '/levantamiento',
          pageBuilder: (context, state) => NoTransitionPage(
            child: LevantamientoPage(
              initialClientId: state.uri.queryParameters['clientId'],
            ),
          ),
        ),
        GoRoute(
          path: '/surveys-staff',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SurveysStaffPage(),
          ),
        ),
        GoRoute(
          path: '/cotizaciones',
          pageBuilder: (context, state) => NoTransitionPage(
            child: CotizacionesPage(
              initialClientId: state.uri.queryParameters['clientId'],
              openComposerOnLoad: state.uri.queryParameters['new'] == '1',
            ),
          ),
        ),
        GoRoute(
          path: '/catalogo',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: CatalogoPage(),
          ),
        ),
        GoRoute(
          path: '/clientes',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ClientesPage(),
          ),
        ),
        GoRoute(
          path: '/clientes/:clientId',
          pageBuilder: (context, state) => NoTransitionPage(
            child: ClienteDetallePage(
              clientId: state.pathParameters['clientId'] ?? '',
            ),
          ),
        ),
        GoRoute(
          path: '/ajustes',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: AjustesPage(),
          ),
        ),
        GoRoute(
          path: '/actas',
          pageBuilder: (context, state) => NoTransitionPage(
            child: ActasPage(
              clientId: state.uri.queryParameters['clientId'],
              quoteId: state.uri.queryParameters['quoteId'],
            ),
          ),
        ),
        GoRoute(
          path: '/nuevo-cliente',
          pageBuilder: (context, state) => NoTransitionPage(
            child: NuevoClientePage(
              returnTo: state.uri.queryParameters['returnTo'],
            ),
          ),
        ),
        GoRoute(
          path: '/presupuesto',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: PresupuestoPage(quoteId: 'seed-quote-001'),
          ),
        ),
        GoRoute(
          path: '/presupuesto/:quoteId',
          pageBuilder: (context, state) => NoTransitionPage(
            child: PresupuestoPage(
              quoteId: state.pathParameters['quoteId'] ?? 'seed-quote-001',
            ),
          ),
        ),
      ],
    ),
  ],
);

class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable() {
    final client = SupabaseBootstrap.client;
    if (client != null) {
      _subscription = client.auth.onAuthStateChange.listen((_) {
        notifyListeners();
      });
    }
  }

  StreamSubscription<AuthState>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

bool _isAdminSession() {
  final user = SupabaseBootstrap.client?.auth.currentUser;
  if (user == null) {
    return false;
  }

  if (!_isUserActive(user.appMetadata, user.userMetadata)) {
    return false;
  }

  return _metadataHasAdminRole(user.appMetadata) || _metadataHasAdminRole(user.userMetadata);
}

bool _isCurrentUserActive() {
  final user = SupabaseBootstrap.client?.auth.currentUser;
  if (user == null) {
    return false;
  }
  return _isUserActive(user.appMetadata, user.userMetadata);
}

bool _metadataHasAdminRole(Map<String, dynamic>? metadata) {
  if (metadata == null) {
    return false;
  }

  final roleValue = '${metadata['role']}'.trim().toLowerCase();
  if (
      roleValue == 'admin' ||
      roleValue == 'administrator' ||
      roleValue == 'super_admin' ||
      roleValue == 'superadmin' ||
      roleValue == 'owner') {
    return true;
  }

  final roles = metadata['roles'];
  if (roles is Iterable) {
    for (final value in roles) {
      final normalized = '$value'.trim().toLowerCase();
      if (
          normalized == 'admin' ||
          normalized == 'administrator' ||
          normalized == 'super_admin' ||
          normalized == 'superadmin' ||
          normalized == 'owner') {
        return true;
      }
    }
  }

  return false;
}

bool _isUserActive(Map<String, dynamic>? appMetadata, Map<String, dynamic>? userMetadata) {
  final appActive = appMetadata?['is_active'];
  if (appActive is bool) {
    return appActive;
  }

  final userActive = userMetadata?['is_active'];
  if (userActive is bool) {
    return userActive;
  }

  return true;
}

