import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rema_app/app/app.dart';
import 'package:rema_app/app/router.dart';

void main() {
  setUp(() {
    appRouter.go('/levantamiento');
  });

  testWidgets('renderiza modulo inicial de levantamiento', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: RemaApp()));
    await tester.pumpAndSettle();

    expect(find.text('Levantamiento de Proyecto'), findsOneWidget);
    expect(find.text('Agregar a la cotizacion'), findsOneWidget);
  });

  testWidgets('navega a clientes desde menu', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(const ProviderScope(child: RemaApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clientes'));
    await tester.pumpAndSettle();

    expect(find.text('Clientes'), findsWidgets);
    expect(find.text('Anadir Cliente'), findsOneWidget);

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('abre presupuesto desde levantamiento', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: RemaApp()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Agregar a la cotizacion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar a la cotizacion'));
    await tester.pumpAndSettle();

    expect(find.text('COTIZACION'), findsOneWidget);
    expect(find.text('Agregar concepto'), findsOneWidget);
  });

  testWidgets('navega a nuevo cliente desde clientes', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: RemaApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clientes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anadir Cliente'));
    await tester.pumpAndSettle();

    expect(find.text('Nuevo Cliente'), findsOneWidget);
    expect(find.text('Guardar Cliente'), findsOneWidget);
  });

  testWidgets('navega a actas desde menu', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: RemaApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Actas'));
    await tester.pumpAndSettle();

    expect(find.text('Actas de Entrega'), findsOneWidget);
    expect(find.text('Cuerpo Acta'), findsOneWidget);
  });
}
