import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rema_app/core/utils/client_input_rules.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Widget mínimo de prueba que replica la lógica de validación de formularios
// de clientes sin depender de Supabase ni Navigator para poder ejecutarse
// como widget test puro.
// ─────────────────────────────────────────────────────────────────────────────

class _ValidationHarness extends StatefulWidget {
  const _ValidationHarness({required this.onSubmit});
  final void Function(bool valid, Map<String, String?> errors) onSubmit;

  @override
  State<_ValidationHarness> createState() => _ValidationHarnessState();
}

class _ValidationHarnessState extends State<_ValidationHarness> {
  final _businessCtrl = TextEditingController();
  final _rfcCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  String? _businessError;
  String? _rfcError;
  String? _phoneError;
  String? _emailError;
  String? _addressError;

  bool _validate() {
    final business = _businessCtrl.text.trim();
    final rfc = _rfcCtrl.text.trim().toUpperCase();
    final phone = ClientInputRules.digitsOnly(_phoneCtrl.text);
    final email = ClientInputRules.normalizeEmail(_emailCtrl.text);
    final address = _addressCtrl.text.trim();

    String? businessErr;
    String? rfcErr;
    String? phoneErr;
    String? emailErr;
    String? addressErr;

    if (business.length < ClientInputRules.minTextLength) {
      businessErr = 'min ${ClientInputRules.minTextLength} chars';
    } else if (business.length > ClientInputRules.maxTextLength) {
      businessErr = 'max ${ClientInputRules.maxTextLength} chars';
    }

    if (!ClientInputRules.isValidRfc(rfc)) {
      rfcErr = ClientInputRules.rfcErrorMessage();
    }

    if (!ClientInputRules.isValidTenDigitPhone(phone)) {
      phoneErr = ClientInputRules.phoneTenDigitsErrorMessage();
    }

    if (!ClientInputRules.isValidEmail(email)) {
      emailErr = ClientInputRules.emailErrorMessage();
    }

    if (address.isNotEmpty && !ClientInputRules.isValidAddress(address)) {
      addressErr = ClientInputRules.addressErrorMessage();
    }

    setState(() {
      _businessError = businessErr;
      _rfcError = rfcErr;
      _phoneError = phoneErr;
      _emailError = emailErr;
      _addressError = addressErr;
    });

    final valid = businessErr == null &&
        rfcErr == null &&
        phoneErr == null &&
        emailErr == null &&
        addressErr == null;

    widget.onSubmit(valid, {
      'business': businessErr,
      'rfc': rfcErr,
      'phone': phoneErr,
      'email': emailErr,
      'address': addressErr,
    });

    return valid;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            TextField(key: const Key('business'), controller: _businessCtrl),
            TextField(key: const Key('rfc'), controller: _rfcCtrl),
            TextField(key: const Key('phone'), controller: _phoneCtrl),
            TextField(key: const Key('email'), controller: _emailCtrl),
            TextField(key: const Key('address'), controller: _addressCtrl),
            if (_businessError != null) Text(_businessError!, key: const Key('err_business')),
            if (_rfcError != null) Text(_rfcError!, key: const Key('err_rfc')),
            if (_phoneError != null) Text(_phoneError!, key: const Key('err_phone')),
            if (_emailError != null) Text(_emailError!, key: const Key('err_email')),
            if (_addressError != null) Text(_addressError!, key: const Key('err_address')),
            ElevatedButton(
              key: const Key('submit'),
              onPressed: _validate,
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _businessCtrl.dispose();
    _rfcCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }
}

void main() {
  // ──────────────────────────────────────────────
  // Caso base: datos completamente válidos
  // ──────────────────────────────────────────────
  testWidgets('formulario válido no genera errores', (tester) async {
    bool? resultValid;
    await tester.pumpWidget(_ValidationHarness(
      onSubmit: (valid, _) => resultValid = valid,
    ));

    await tester.enterText(find.byKey(const Key('business')), 'CONSTRUCTORA DEL CARIBE');
    await tester.enterText(find.byKey(const Key('rfc')), 'XYZ850101AB1');
    await tester.enterText(find.byKey(const Key('phone')), '9981234567');
    await tester.enterText(find.byKey(const Key('email')), 'contacto@empresa.com');
    await tester.enterText(find.byKey(const Key('address')), 'Av. Tulum 123, Cancún');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();

    expect(resultValid, isTrue);
    expect(find.byKey(const Key('err_business')), findsNothing);
    expect(find.byKey(const Key('err_phone')), findsNothing);
    expect(find.byKey(const Key('err_email')), findsNothing);
  });

  // ──────────────────────────────────────────────
  // Casos inválidos – campos individuales
  // ──────────────────────────────────────────────
  testWidgets('nombre con solo 1 char muestra error', (tester) async {
    bool? resultValid;
    await tester.pumpWidget(_ValidationHarness(onSubmit: (v, _) => resultValid = v));

    await tester.enterText(find.byKey(const Key('business')), 'A');
    await tester.enterText(find.byKey(const Key('phone')), '9981234567');
    await tester.enterText(find.byKey(const Key('email')), 'aaaa@test.com');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();

    expect(resultValid, isFalse);
    expect(find.byKey(const Key('err_business')), findsOneWidget);
  });

  testWidgets('teléfono con letras muestra error', (tester) async {
    bool? resultValid;
    await tester.pumpWidget(_ValidationHarness(onSubmit: (v, _) => resultValid = v));

    await tester.enterText(find.byKey(const Key('business')), 'EMPRESA SA');
    await tester.enterText(find.byKey(const Key('phone')), '998ABC1234');
    await tester.enterText(find.byKey(const Key('email')), 'aaaa@test.com');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();

    expect(resultValid, isFalse);
    expect(find.byKey(const Key('err_phone')), findsOneWidget);
  });

  testWidgets('correo sin @ muestra error', (tester) async {
    bool? resultValid;
    await tester.pumpWidget(_ValidationHarness(onSubmit: (v, _) => resultValid = v));

    await tester.enterText(find.byKey(const Key('business')), 'EMPRESA SA');
    await tester.enterText(find.byKey(const Key('phone')), '9981234567');
    await tester.enterText(find.byKey(const Key('email')), 'correo.com');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();

    expect(resultValid, isFalse);
    expect(find.byKey(const Key('err_email')), findsOneWidget);
  });

  testWidgets('RFC con formato inválido muestra error', (tester) async {
    bool? resultValid;
    await tester.pumpWidget(_ValidationHarness(onSubmit: (v, _) => resultValid = v));

    await tester.enterText(find.byKey(const Key('business')), 'EMPRESA SA');
    await tester.enterText(find.byKey(const Key('rfc')), 'INVALIDO-RFC');
    await tester.enterText(find.byKey(const Key('phone')), '9981234567');
    await tester.enterText(find.byKey(const Key('email')), 'aaaa@test.com');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();

    expect(resultValid, isFalse);
    expect(find.byKey(const Key('err_rfc')), findsOneWidget);
  });

  testWidgets('dirección muy corta muestra error', (tester) async {
    bool? resultValid;
    await tester.pumpWidget(_ValidationHarness(onSubmit: (v, _) => resultValid = v));

    await tester.enterText(find.byKey(const Key('business')), 'EMPRESA SA');
    await tester.enterText(find.byKey(const Key('phone')), '9981234567');
    await tester.enterText(find.byKey(const Key('email')), 'aaaa@test.com');
    await tester.enterText(find.byKey(const Key('address')), 'Cal 1');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();

    expect(resultValid, isFalse);
    expect(find.byKey(const Key('err_address')), findsOneWidget);
  });

  // ──────────────────────────────────────────────
  // Edge cases
  // ──────────────────────────────────────────────
  testWidgets('email con espacios al inicio y fin es normalizado y válido', (tester) async {
    bool? resultValid;
    await tester.pumpWidget(_ValidationHarness(onSubmit: (v, _) => resultValid = v));

    await tester.enterText(find.byKey(const Key('business')), 'EMPRESA SA');
    await tester.enterText(find.byKey(const Key('phone')), '9981234567');
    await tester.enterText(find.byKey(const Key('email')), '  USUARIO@EMPRESA.COM  ');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();

    expect(find.byKey(const Key('err_email')), findsNothing);
  });

  testWidgets('RFC vacío es aceptado (campo opcional)', (tester) async {
    bool? resultValid;
    await tester.pumpWidget(_ValidationHarness(onSubmit: (v, _) => resultValid = v));

    await tester.enterText(find.byKey(const Key('business')), 'EMPRESA SA');
    await tester.enterText(find.byKey(const Key('rfc')), '');
    await tester.enterText(find.byKey(const Key('phone')), '9981234567');
    await tester.enterText(find.byKey(const Key('email')), 'aaaa@test.com');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();

    expect(find.byKey(const Key('err_rfc')), findsNothing);
  });

  testWidgets('múltiples errores se muestran simultáneamente', (tester) async {
    bool? resultValid;
    await tester.pumpWidget(_ValidationHarness(onSubmit: (v, _) => resultValid = v));

    await tester.enterText(find.byKey(const Key('business')), 'A');
    await tester.enterText(find.byKey(const Key('phone')), '123');
    await tester.enterText(find.byKey(const Key('email')), 'noatemail');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();

    expect(resultValid, isFalse);
    expect(find.byKey(const Key('err_business')), findsOneWidget);
    expect(find.byKey(const Key('err_phone')), findsOneWidget);
    expect(find.byKey(const Key('err_email')), findsOneWidget);
  });
}
