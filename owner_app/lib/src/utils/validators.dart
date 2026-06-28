/// Centralized form-field validators for use with [TextFormField.validator].
///
/// These mirror the backend Jakarta Bean Validation constraints so client and
/// server agree on what is acceptable. Each method returns `null` when the value
/// is valid, or an error message string otherwise.
///
/// Usage:
/// ```dart
/// TextFormField(validator: Validators.mobile)
/// TextFormField(validator: (v) => Validators.minLength(v, 2, label: 'Name'))
/// ```
abstract final class Validators {
  static final RegExp _mobile = RegExp(r'^[0-9]{10}$');
  static final RegExp _username = RegExp(r'^[a-zA-Z0-9_]+$');
  static final RegExp _aadhaar = RegExp(r'^[0-9]{12}$');
  static final RegExp _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  /// Non-empty after trimming.
  static String? required(String? value, {String label = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  /// Required + minimum trimmed length.
  static String? minLength(String? value, int min, {String label = 'This field'}) {
    final req = required(value, label: label);
    if (req != null) return req;
    if (value!.trim().length < min) return '$label must be at least $min characters';
    return null;
  }

  /// 10-digit Indian mobile number (matches backend `^[0-9]{10}$`).
  static String? mobile(String? value) {
    final req = required(value, label: 'Mobile number');
    if (req != null) return req;
    if (!_mobile.hasMatch(value!.trim())) {
      return 'Enter a valid 10-digit mobile number';
    }
    return null;
  }

  /// Optional mobile — only validated when a value is present.
  static String? optionalMobile(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return mobile(value);
  }

  /// Username: 4+ chars, letters/digits/underscore (matches backend pattern).
  static String? username(String? value) {
    final req = minLength(value, 4, label: 'Username');
    if (req != null) return req;
    if (!_username.hasMatch(value!.trim())) {
      return 'Only letters, digits, and underscores';
    }
    return null;
  }

  /// Password: 8+ chars (matches backend `@Size(min = 8)`).
  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < 8) return 'Must be at least 8 characters';
    return null;
  }

  /// Confirm-password matcher. Pass the original password value.
  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != original) return 'Passwords do not match';
    return null;
  }

  /// Optional email — only validated when a value is present.
  static String? optionalEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (!_email.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  /// Required email.
  static String? email(String? value) {
    final req = required(value, label: 'Email');
    if (req != null) return req;
    return optionalEmail(value);
  }

  /// 12-digit Aadhaar number.
  static String? aadhaar(String? value) {
    if (value == null || value.trim().isEmpty) return null; // Aadhaar is optional
    if (!_aadhaar.hasMatch(value.trim())) return 'Enter a valid 12-digit Aadhaar number';
    return null;
  }

  /// Positive amount (> 0). Used for payments.
  static String? positiveAmount(String? value, {String label = 'Amount'}) {
    final req = required(value, label: label);
    if (req != null) return req;
    final parsed = num.tryParse(value!.trim());
    if (parsed == null) return 'Enter a valid number';
    if (parsed <= 0) return '$label must be greater than zero';
    return null;
  }

  /// Non-negative amount (>= 0). Used for deposit/advance/discount/penalty.
  static String? nonNegativeAmount(String? value, {String label = 'Amount'}) {
    if (value == null || value.trim().isEmpty) return null; // optional money field
    final parsed = num.tryParse(value.trim());
    if (parsed == null) return 'Enter a valid number';
    if (parsed < 0) return '$label cannot be negative';
    return null;
  }

  /// Positive integer (>= 1). Used for capacity / counts.
  static String? positiveInt(String? value, {String label = 'Value'}) {
    final req = required(value, label: label);
    if (req != null) return req;
    final parsed = int.tryParse(value!.trim());
    if (parsed == null) return 'Enter a whole number';
    if (parsed < 1) return '$label must be at least 1';
    return null;
  }
}
