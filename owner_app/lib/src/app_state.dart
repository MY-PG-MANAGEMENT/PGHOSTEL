import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

import 'services/api_client.dart';
import 'services/auth_repository.dart';

class AppState extends ChangeNotifier {
  /// [apiClient] can be supplied for tests; in production it defaults to a real
  /// [ApiClient] backed by secure storage (identical to the previous behavior,
  /// since `const FlutterSecureStorage()` instances are canonicalized).
  AppState({ApiClient? apiClient})
      : apiClient = apiClient ?? ApiClient(storage: const FlutterSecureStorage());

  final storage = const FlutterSecureStorage();
  final ApiClient apiClient;
  late final AuthRepository authRepository = AuthRepository(apiClient: apiClient, storage: storage);

  bool initialized = false;
  bool isLoggedIn = false;
  String? roleTypeId;
  String? ownerName;
  final LocalAuthentication localAuthentication = LocalAuthentication();

  Future<void> restoreSession() async {
    final hasToken = await storage.read(key: 'accessToken') != null;
    final biometricEnabled = await storage.read(key: 'biometricEnabled') == 'true';
    isLoggedIn = hasToken && !biometricEnabled;
    roleTypeId = await storage.read(key: 'roleTypeId');
    ownerName = await storage.read(key: 'fullName');
    if (isLoggedIn) await _fetchOwnerName();
    initialized = true;
    notifyListeners();
  }

  /// Whether the device-security unlock button should be offered on the login
  /// screen. True only when the hardware supports biometric/device auth, a
  /// session token is present, and the user previously enabled biometric unlock.
  /// On unsupported devices this returns false so the button stays hidden.
  Future<bool> canUseBiometricUnlock() async {
    try {
      if (await storage.read(key: 'accessToken') == null) return false;
      if (await storage.read(key: 'biometricEnabled') != 'true') return false;
      return await localAuthentication.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Concise prompt copy so the Android system dialog stays clean (no verbose
  /// default hints). [title] is the bold heading; the line below it comes from
  /// the `localizedReason` passed to `authenticate`.
  static List<AuthMessages> _promptMessages(String title) => [
        AndroidAuthMessages(
          signInTitle: title,
          biometricHint: '',
          cancelButton: 'Cancel',
        ),
      ];

  Future<bool> biometricLogin() async {
    if (await storage.read(key: 'accessToken') == null) return false;
    try {
      final authenticated = await localAuthentication.authenticate(
        localizedReason: 'Unlock PG Manager',
        authMessages: _promptMessages('Unlock PG Manager'),
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      if (authenticated) {
        isLoggedIn = true;
        roleTypeId = await storage.read(key: 'roleTypeId');
        await _fetchOwnerName();
        notifyListeners();
      }
      return authenticated;
    } catch (_) {
      return false;
    }
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    if (enabled) {
      final supported = await localAuthentication.isDeviceSupported();
      final canCheck = await localAuthentication.canCheckBiometrics;
      if (!supported && !canCheck) {
        throw Exception('This device has no screen lock or biometrics set up. '
            'Add a fingerprint, PIN, or pattern in system Settings first.');
      }
      final bool ok;
      try {
        ok = await localAuthentication.authenticate(
          localizedReason: "Confirm it's you to enable secure unlock",
          authMessages: _promptMessages('Enable secure unlock'),
          options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
        );
      } on PlatformException catch (e) {
        throw Exception(_biometricErrorMessage(e));
      }
      if (!ok) return; // user cancelled the prompt
    }
    await storage.write(key: 'biometricEnabled', value: '$enabled');
    notifyListeners();
  }

  /// Maps a `local_auth` [PlatformException] to a human-readable, actionable
  /// message for the UI.
  String _biometricErrorMessage(PlatformException e) {
    switch (e.code) {
      case auth_error.notEnrolled:
        return 'No fingerprint or screen lock is enrolled. Add one in system '
            'Settings, then try again.';
      case auth_error.notAvailable:
        return 'Biometric authentication is not available on this device.';
      case auth_error.passcodeNotSet:
        return 'Set up a screen lock (PIN, pattern, or password) first.';
      case auth_error.lockedOut:
        return 'Too many attempts. Try again in a moment.';
      case auth_error.permanentlyLockedOut:
        return 'Biometrics are locked. Unlock your device with your PIN/pattern, '
            'then try again.';
      case 'no_fragment_activity':
        return 'Please fully close and reopen the app, then try again.';
      default:
        return e.message ?? 'Could not enable biometric unlock (${e.code}).';
    }
  }

  Future<void> login(String username, String password) async {
    try {
      await authRepository.login(username, password);

      isLoggedIn = true;
      roleTypeId = await storage.read(key: 'roleTypeId');
      await _fetchOwnerName();
      notifyListeners();
    } catch (e) {
      isLoggedIn = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> registerOwner({
    required String fullName,
    required String mobileNumber,
    required String username,
    required String password,
    required String organizationName,
  }) async {
    await authRepository.registerOwner(
      fullName: fullName,
      mobileNumber: mobileNumber,
      username: username,
      password: password,
      organizationName: organizationName,
    );
    isLoggedIn = true;
    roleTypeId = await storage.read(key: 'roleTypeId');
    await _fetchOwnerName();
    notifyListeners();
  }

  Future<void> _fetchOwnerName() async {
    try {
      final data = await apiClient.get('/account/profile');
      ownerName = data['fullName'] as String?;
      if (ownerName != null) {
        await storage.write(key: 'fullName', value: ownerName);
      }
    } catch (_) {}
  }

  Future<void> logout() async {
    await storage.deleteAll();
    isLoggedIn = false;
    roleTypeId = null;
    ownerName = null;
    notifyListeners();
  }
}
