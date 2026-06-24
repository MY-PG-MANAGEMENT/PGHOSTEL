import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'services/api_client.dart';
import 'services/auth_repository.dart';

class AppState extends ChangeNotifier {
  final storage = const FlutterSecureStorage();
  late final ApiClient apiClient = ApiClient(storage: storage);
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

  Future<bool> biometricLogin() async {
    if (await storage.read(key: 'accessToken') == null) return false;
    try {
      final authenticated = await localAuthentication.authenticate(
        localizedReason: 'Unlock PG Manager securely',
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
      if (!supported) throw Exception('Device authentication is not available');
      final ok = await localAuthentication.authenticate(localizedReason: 'Enable secure app unlock');
      if (!ok) return;
    }
    await storage.write(key: 'biometricEnabled', value: '$enabled');
    notifyListeners();
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
