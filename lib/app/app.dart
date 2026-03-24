import 'package:flutter/material.dart';

import '../core/theme/rema_theme.dart';
import 'router.dart';

class RemaApp extends StatelessWidget {
  const RemaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'REMA Arquitectura',
      debugShowCheckedModeBanner: false,
      theme: RemaTheme.light,
      routerConfig: appRouter,
    );
  }
}
