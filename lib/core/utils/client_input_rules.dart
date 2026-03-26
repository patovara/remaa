class ClientInputRules {
  static const int minEmailLocalPart = 4;
  static final RegExp _textOnlyPattern = RegExp(r'^[A-ZÁÉÍÓÚÜÑ ]+$');

  static String normalizeEmail(String value) {
    return value.trim().toLowerCase();
  }

  static String digitsOnly(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  static String sanitizeTextOnly(String value) {
    return value
        .replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toUpperCase();
  }

  static bool isValidTextOnly(String value) {
    final normalized = sanitizeTextOnly(value);
    return normalized.isNotEmpty && _textOnlyPattern.hasMatch(normalized);
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

  static bool isValidTenDigitPhone(String value) {
    return digitsOnly(value).length == 10;
  }

  static String emailErrorMessage({String fieldLabel = 'correo'}) {
    return 'Ingresa un $fieldLabel valido con al menos 4 caracteres antes de @.';
  }

  static String phoneTenDigitsErrorMessage({String fieldLabel = 'telefono'}) {
    return 'Ingresa un $fieldLabel valido de 10 digitos.';
  }

  static String phoneRequiredMessage({String fieldLabel = 'telefono'}) {
    return 'Ingresa el $fieldLabel.';
  }

  static String mexicoPhoneExactErrorMessage() {
    return 'Para Mexico (+52) el telefono debe tener exactamente 10 digitos.';
  }

  static String phoneMaxDigitsErrorMessage({required String countryName, required int maxDigits}) {
    return 'El telefono para $countryName permite maximo $maxDigits digitos.';
  }

  static String textOnlyErrorMessage({required String fieldLabel}) {
    return 'El $fieldLabel solo admite letras.';
  }
}
