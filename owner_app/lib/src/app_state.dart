import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'services/api_client.dart';
import 'services/auth_repository.dart';

class AppState extends ChangeNotifier {
  final storage = const FlutterSecureStorage();
  late final ApiClient apiClient = ApiClient(storage: storage);
  late final AuthRepository authRepository = AuthRepository(apiClient: apiClient, storage: storage);

  bool initialized = false;
  bool isLoggedIn = false;

  Future<void> restoreSession() async {
    isLoggedIn = await storage.read(key: 'accessToken') != null;
    initialized = true;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    await authRepository.login(username, password);
    isLoggedIn = true;
    notifyListeners();
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
    notifyListeners();
  }

  Future<void> logout() async {
    await storage.deleteAll();
    isLoggedIn = false;
    notifyListeners();
  }
}
