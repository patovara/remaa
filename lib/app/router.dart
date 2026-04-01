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

final _authRefresh = _AuthRefreshListenable();

final appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: _authRefresh,
  redirect: (context, state) {
    final location = state.matchedLocation;
    final isAuthRoute = location == '/login' || location == '/register';
    final hasSession = SupabaseBootstrap.client?.auth.currentSession != null;

    if (!hasSession && !isAuthRoute) {
      return '/login';
    }
    if (hasSession && isAuthRoute) {
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
      pageBuilder: (context, state) => const NoTransitionPage(
        child: RegisterPage(),
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
