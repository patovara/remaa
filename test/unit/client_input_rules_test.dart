import 'package:flutter_test/flutter_test.dart';
import 'package:rema_app/core/utils/client_input_rules.dart';

void main() {
  // ──────────────────────────────────────────────
  // normalizeEmail
  // ──────────────────────────────────────────────
  group('normalizeEmail', () {
    test('convierte a lowercase y elimina espacios', () {
      expect(ClientInputRules.normalizeEmail('  CORREO@TEST.COM  '), 'correo@test.com');
    });
    test('no altera correo ya normalizado', () {
      expect(ClientInputRules.normalizeEmail('correo@test.com'), 'correo@test.com');
    });
  });

  // ──────────────────────────────────────────────
  // isValidEmail
  // ──────────────────────────────────────────────
  group('isValidEmail', () {
    test('correo válido básico', () {
      expect(ClientInputRules.isValidEmail('aaaa@test.com'), isTrue);
    });
    test('correo válido con subdominio', () {
      expect(ClientInputRules.isValidEmail('user@mail.empresa.com.mx'), isTrue);
    });
    test('correo válido con mayúsculas (normalizado internamente)', () {
      expect(ClientInputRules.isValidEmail('USER@Domain.Com'), isTrue);
    });
    test('sin @', () {
      expect(ClientInputRules.isValidEmail('correo.com'), isFalse);
    });
    test('local part menor de 4 chars', () {
      expect(ClientInputRules.isValidEmail('u@test.com'), isFalse);
    });
    test('dominio sin punto', () {
      expect(ClientInputRules.isValidEmail('aaaa@testcom'), isFalse);
    });
    test('dominio empieza con punto', () {
      expect(ClientInputRules.isValidEmail('aaaa@.test.com'), isFalse);
    });
    test('espacios en local part', () {
      expect(ClientInputRules.isValidEmail('aa aa@test.com'), isFalse);
    });
    test('vacío', () {
      expect(ClientInputRules.isValidEmail(''), isFalse);
    });
  });

  // ──────────────────────────────────────────────
  // isValidTenDigitPhone
  // ──────────────────────────────────────────────
  group('isValidTenDigitPhone', () {
    test('10 dígitos exactos', () {
      expect(ClientInputRules.isValidTenDigitPhone('9981234567'), isTrue);
    });
    test('10 dígitos con prefijo +52 (se extrae dígitos)', () {
      expect(ClientInputRules.isValidTenDigitPhone('+529981234567'), isFalse); // 12 dígitos totales
    });
    test('9 dígitos', () {
      expect(ClientInputRules.isValidTenDigitPhone('998123456'), isFalse);
    });
    test('11 dígitos', () {
      expect(ClientInputRules.isValidTenDigitPhone('99812345678'), isFalse);
    });
    test('con letras', () {
      expect(ClientInputRules.isValidTenDigitPhone('998ABC1234'), isFalse);
    });
    test('vacío', () {
      expect(ClientInputRules.isValidTenDigitPhone(''), isFalse);
    });
  });

  // ──────────────────────────────────────────────
  // toE164Mx
  // ──────────────────────────────────────────────
  group('toE164Mx', () {
    test('10 dígitos → E.164', () {
      expect(ClientInputRules.toE164Mx('9981234567'), '+529981234567');
    });
    test('ya con +52 (12 dígitos con separador)', () {
      expect(ClientInputRules.toE164Mx('+52 9981234567'), '+529981234567');
    });
    test('12 dígitos sin +', () {
      expect(ClientInputRules.toE164Mx('529981234567'), '+529981234567');
    });
    test('8 dígitos → null (inválido)', () {
      expect(ClientInputRules.toE164Mx('99812345'), isNull);
    });
    test('vacío → null', () {
      expect(ClientInputRules.toE164Mx(''), isNull);
    });
  });

  // ──────────────────────────────────────────────
  // isValidTextOnly
  // ──────────────────────────────────────────────
  group('isValidTextOnly', () {
    test('nombre simple válido', () {
      expect(ClientInputRules.isValidTextOnly('Juan Pérez'), isTrue);
    });
    test('razón social con acentos', () {
      expect(ClientInputRules.isValidTextOnly('Constructora del Caribe'), isTrue);
    });
    test('nombre con ñ', () {
      expect(ClientInputRules.isValidTextOnly('Añoveros Arquitectos'), isTrue);
    });
    test('con número el sanitize los elimina, resultado es válido', () {
      // sanitizeTextOnly elimina números antes de validar.
      // La capa de UI usa formatters para bloquear entrada en tiempo real.
      expect(ClientInputRules.isValidTextOnly('Juan123'), isTrue);
    });
    test('carácter especial es eliminado por sanitize, resultado puede ser válido', () {
      // El guión es eliminado por sanitize; si queda texto suficiente es válido.
      expect(ClientInputRules.isValidTextOnly('Juan-Pérez'), isTrue);
    });
    test('1 char → inválido (min 2)', () {
      expect(ClientInputRules.isValidTextOnly('A'), isFalse);
    });
    test('más de 100 chars → inválido', () {
      expect(ClientInputRules.isValidTextOnly('A' * 101), isFalse);
    });
    test('exactamente 2 chars → válido', () {
      expect(ClientInputRules.isValidTextOnly('AB'), isTrue);
    });
    test('exactamente 100 chars → válido', () {
      expect(ClientInputRules.isValidTextOnly('A' * 100), isTrue);
    });
    test('solo espacios → inválido', () {
      expect(ClientInputRules.isValidTextOnly('   '), isFalse);
    });
    test('vacío → inválido', () {
      expect(ClientInputRules.isValidTextOnly(''), isFalse);
    });
  });

  // ──────────────────────────────────────────────
  // isValidAddress
  // ──────────────────────────────────────────────
  group('isValidAddress', () {
    test('dirección completa válida', () {
      expect(ClientInputRules.isValidAddress('Av. Tulum 123, Cancún, Quintana Roo'), isTrue);
    });
    test('mínimo 10 chars con letra y número', () {
      expect(ClientInputRules.isValidAddress('Calle A 123'), isTrue);
    });
    test('solo letras, sin número → inválido', () {
      expect(ClientInputRules.isValidAddress('Calle Avenida Boulevard'), isFalse);
    });
    test('solo números, sin letra → inválido', () {
      expect(ClientInputRules.isValidAddress('1234567890'), isFalse);
    });
    test('menos de 10 chars → inválido', () {
      expect(ClientInputRules.isValidAddress('Cal 1'), isFalse);
    });
    test('más de 255 chars → inválido', () {
      final long = 'Calle Larga 1 ${'X' * 242}';
      expect(ClientInputRules.isValidAddress(long), isFalse);
    });
    test('vacío → inválido', () {
      expect(ClientInputRules.isValidAddress(''), isFalse);
    });
    test('exactamente 10 chars con letra y número → válido', () {
      expect(ClientInputRules.isValidAddress('Av Test 12'), isTrue);
    });
  });

  // ──────────────────────────────────────────────
  // isValidRfc
  // ──────────────────────────────────────────────
  group('isValidRfc', () {
    test('RFC persona moral (12 chars) válido', () {
      expect(ClientInputRules.isValidRfc('XYZ850101AB1'), isTrue);
    });
    test('RFC persona física (13 chars) válido', () {
      expect(ClientInputRules.isValidRfc('ABCD850101XY3'), isTrue);
    });
    test('vacío → válido (campo opcional)', () {
      expect(ClientInputRules.isValidRfc(''), isTrue);
    });
    test('solo espacios → válido (opcional)', () {
      expect(ClientInputRules.isValidRfc('   '), isTrue);
    });
    test('11 chars → inválido', () {
      expect(ClientInputRules.isValidRfc('XYZ850101A1'), isFalse);
    });
    test('14 chars → inválido', () {
      expect(ClientInputRules.isValidRfc('ABCDE850101XY3'), isFalse);
    });
    test('con caracteres especiales → inválido', () {
      expect(ClientInputRules.isValidRfc('ABC-850101-AB1'), isFalse);
    });
    test('lowercase normalizado → válido', () {
      expect(ClientInputRules.isValidRfc('xyz850101ab1'), isTrue);
    });
  });

  // ──────────────────────────────────────────────
  // mapDbError
  // ──────────────────────────────────────────────
  group('mapDbError', () {
    test('error de email duplicado', () {
      final msg = ClientInputRules.mapDbError(
          'PostgrestException: duplicate key value violates unique constraint "clients_email_unique_ci"');
      expect(msg, contains('correo'));
    });
    test('error de RFC duplicado', () {
      final msg = ClientInputRules.mapDbError(
          'duplicate key violates unique constraint "clients_rfc_unique_ci"');
      expect(msg, contains('RFC'));
    });
    test('error de teléfono duplicado', () {
      final msg = ClientInputRules.mapDbError(
          'duplicate key violates unique constraint "clients_phone_unique"');
      expect(msg, contains('teléfono'));
    });
    test('error de razón social duplicada', () {
      final msg = ClientInputRules.mapDbError(
          'duplicate key violates unique constraint "clients_business_name_unique_ci"');
      expect(msg, contains('razón social'));
    });
    test('error no mapeado retorna null', () {
      expect(ClientInputRules.mapDbError('error desconocido xyz'), isNull);
    });
  });

  // ──────────────────────────────────────────────
  // sanitizeTextOnly
  // ──────────────────────────────────────────────
  group('sanitizeTextOnly', () {
    test('elimina números y símbolos', () {
      expect(ClientInputRules.sanitizeTextOnly('Juan123!'), 'JUAN');
    });
    test('normaliza espacios múltiples', () {
      expect(ClientInputRules.sanitizeTextOnly('Juan   Pérez'), 'JUAN PÉREZ');
    });
    test('convierte a mayúsculas', () {
      expect(ClientInputRules.sanitizeTextOnly('juan pérez'), 'JUAN PÉREZ');
    });
    test('vacío → vacío', () {
      expect(ClientInputRules.sanitizeTextOnly(''), '');
    });
  });
}
