/// Reglas centralizadas de validación y normalización para campos de clientes.
/// Esta clase es la única fuente de verdad para todas las pantallas y el repositorio.
class ClientInputRules {
  // ── Límites generales ───────────────────────────────────────────────────────
  static const int minEmailLocalPart = 4;
  static const int minTextLength = 2;
  static const int maxTextLength = 100;
  static const int minAddressLength = 10;
  static const int maxAddressLength = 255;

  // ── Patrones ────────────────────────────────────────────────────────────────
  static final RegExp _textOnlyPattern = RegExp(r'^[A-ZÁÉÍÓÚÜÑ ]+$');
  // RFC México: 3-4 letras (incluye & y Ñ para personas morales) + 6 dígitos + 3 alfanum.
  static final RegExp _rfcPattern = RegExp(
    r'^[A-Z&Ñ]{3,4}[0-9]{6}[A-Z0-9]{3}$',
    caseSensitive: false,
  );
  // Dirección: debe contener al menos una letra y al menos un dígito.
  static final RegExp _addressHasLetter = RegExp(r'[A-Za-záéíóúüñÁÉÍÓÚÜÑ]');
  static final RegExp _addressHasDigit = RegExp(r'[0-9]');

  // ── Normalización ───────────────────────────────────────────────────────────

  static String normalizeEmail(String value) => value.trim().toLowerCase();

  static String digitsOnly(String value) =>
      value.replaceAll(RegExp(r'\D'), '');

  /// Construye teléfono canónico E.164 para México: "+52XXXXXXXXXX".
  /// Acepta entrada con o sin prefijo (+52 / 52) y con o sin separadores.
  /// Retorna null si los dígitos no suman exactamente 10 (local) o 12 (+52).
  static String? toE164Mx(String value) {
    final digits = digitsOnly(value);
    if (digits.length == 10) {
      return '+52$digits';
    }
    if (digits.length == 12 && digits.startsWith('52')) {
      return '+52${digits.substring(2)}';
    }
    return null;
  }

  static String sanitizeTextOnly(String value) {
    return value
        .replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toUpperCase();
  }

  // ── Validadores ─────────────────────────────────────────────────────────────

  /// Texto: solo letras, espacios y acentos. Longitud 2-100.
  static bool isValidTextOnly(String value) {
    final normalized = sanitizeTextOnly(value);
    return normalized.length >= minTextLength &&
        normalized.length <= maxTextLength &&
        _textOnlyPattern.hasMatch(normalized);
  }

  static bool isValidEmail(String value) {
    final email = normalizeEmail(value);
    final atIndex = email.indexOf('@');
    if (atIndex < minEmailLocalPart || atIndex == email.length - 1) {
      return false;
    }
    final localPart = email.substring(0, atIndex);
    final domainPart = email.substring(atIndex + 1);
    return localPart.length >= minEmailLocalPart &&
        !localPart.contains(' ') &&
        domainPart.contains('.') &&
        !domainPart.startsWith('.') &&
        !domainPart.endsWith('.') &&
        !domainPart.contains(' ');
  }

  /// Teléfono: valida que los dígitos sean exactamente 10 (MX).
  static bool isValidTenDigitPhone(String value) =>
      digitsOnly(value).length == 10;

  /// Dirección: 10-255 caracteres, debe contener letras y al menos un número.
  static bool isValidAddress(String value) {
    final trimmed = value.trim();
    return trimmed.length >= minAddressLength &&
        trimmed.length <= maxAddressLength &&
        _addressHasLetter.hasMatch(trimmed) &&
        _addressHasDigit.hasMatch(trimmed);
  }

  /// RFC México: 12 chars (moral) o 13 chars (física). Acepta null/vacío (campo optional).
  static bool isValidRfc(String value) {
    final normalized = value.trim().toUpperCase();
    if (normalized.isEmpty) {
      return true; // RFC es opcional
    }
    return (normalized.length == 12 || normalized.length == 13) &&
        _rfcPattern.hasMatch(normalized);
  }

  // ── Mensajes de error ───────────────────────────────────────────────────────

  static String emailErrorMessage({String fieldLabel = 'correo'}) =>
      'Ingresa un $fieldLabel valido con al menos 4 caracteres antes de @.';

  static String phoneTenDigitsErrorMessage({String fieldLabel = 'telefono'}) =>
      'Ingresa un $fieldLabel valido de 10 digitos.';

  static String phoneRequiredMessage({String fieldLabel = 'telefono'}) =>
      'Ingresa el $fieldLabel.';

  static String mexicoPhoneExactErrorMessage() =>
      'Para Mexico (+52) el telefono debe tener exactamente 10 digitos.';

  static String phoneMaxDigitsErrorMessage({
    required String countryName,
    required int maxDigits,
  }) =>
      'El telefono para $countryName permite maximo $maxDigits digitos.';

  static String textOnlyErrorMessage({required String fieldLabel}) =>
      'El $fieldLabel solo admite letras (min $minTextLength, max $maxTextLength).';

  static String addressErrorMessage({String fieldLabel = 'direccion'}) =>
      'La $fieldLabel debe tener entre $minAddressLength y $maxAddressLength caracteres, '
      'e incluir letras y numeros (ej: Av. Tulum 123, Cancun).';

  static String rfcErrorMessage() =>
      'El RFC no tiene un formato valido. '
      'Persona moral: 12 caracteres. Persona fisica: 13 caracteres.';

  // ── Mapeo de errores de base de datos ───────────────────────────────────────

  /// Convierte errores de PostgreSQL (constraint violations) a mensajes de negocio.
  /// [error] debe ser la representación toString() del PostgrestException o similar.
  static String? mapDbError(String error) {
    final e = error.toLowerCase();
    if (e.contains('clients_email_unique_ci') || e.contains('duplicate') && e.contains('email')) {
      return 'Este correo ya está registrado en otro cliente.';
    }
    if (e.contains('clients_rfc_unique_ci') || e.contains('duplicate') && e.contains('rfc')) {
      return 'Este RFC ya está registrado en otro cliente.';
    }
    if (e.contains('clients_phone_unique') || e.contains('duplicate') && e.contains('phone')) {
      return 'Este teléfono ya está registrado en otro cliente.';
    }
    if (e.contains('clients_business_name_unique_ci') ||
        e.contains('duplicate') && e.contains('business_name')) {
      return 'Esta razón social ya está registrada.';
    }
    if (e.contains('clients_rfc_format')) {
      return 'El formato de RFC no es válido según la base de datos.';
    }
    if (e.contains('clients_phone_e164')) {
      return 'El teléfono debe estar en formato +52XXXXXXXXXX.';
    }
    if (e.contains('clients_address_format')) {
      return 'La dirección tiene un formato inválido.';
    }
    if (e.contains('clients_business_name_notempty')) {
      return 'La razón social no puede estar vacía.';
    }
    return null; // error no mapeado, mostrar mensaje genérico
  }
}
