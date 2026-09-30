class Validators {
  Validators._();

  static final RegExp _emailRegExp = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  static final RegExp _specialCharRegExp = RegExp(r'[\*\^\$%\#@\.]');
  static final RegExp _uppercaseRegExp = RegExp(r'[A-Z]');
  static final RegExp _digitRegExp = RegExp(r'[0-9]');

  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }
    final email = value.trim();
    if (!_emailRegExp.hasMatch(email)) {
      return "Invalid format: must contain '@' and a valid domain";
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Min 8 chars required';
    }
    if (!_uppercaseRegExp.hasMatch(value)) {
      return 'Must contain at least 1 uppercase letter';
    }
    if (!_digitRegExp.hasMatch(value)) {
      return 'Must contain at least 1 digit';
    }
    if (!_specialCharRegExp.hasMatch(value)) {
      return r'Min 8 chars, 1 uppercase, 1 digit, 1 special (* ^ $ % # @ .)';
    }
    return null;
  }

  static String? validateConfirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) {
      return 'Confirm password is required';
    }
    if (value != password) {
      return 'Passwords do not match';
    }
    return null;
  }

  static String? validatePasskey(String? value) {
    if (value == null || value.isEmpty) {
      return 'Passkey is required';
    }
    return validatePassword(value);
  }
}
