import 'package:go_router/go_router.dart';

import '../core/widgets/rema_shell.dart';
import '../features/ajustes/presentation/ajustes_page.dart';
import '../features/actas/presentation/actas_page.dart';
import '../features/clientes/presentation/cliente_detalle_page.dart';
import '../features/clientes/presentation/clientes_page.dart';
import '../features/cotizaciones/presentation/cotizaciones_page.dart';
import '../features/levantamiento/presentation/levantamiento_page.dart';
import '../features/nuevo_cliente/presentation/nuevo_cliente_page.dart';
import '../features/presupuesto/presentation/presupuesto_page.dart';

final appRouter = GoRouter(
  initialLocation: '/levantamiento',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return RemaShell(location: state.uri.toString(), child: child);
      },
      routes: [
        GoRoute(
          path: '/levantamiento',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: LevantamientoPage(),
          ),
        ),
        GoRoute(
          path: '/cotizaciones',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: CotizacionesPage(),
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
          pageBuilder: (context, state) => const NoTransitionPage(
            child: ActasPage(),
          ),
        ),
        GoRoute(
          path: '/nuevo-cliente',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: NuevoClientePage(),
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
