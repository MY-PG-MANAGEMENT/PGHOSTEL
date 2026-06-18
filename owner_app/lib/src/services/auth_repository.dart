import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

class AuthRepository {
  AuthRepository({required this.apiClient, required this.storage});

  final ApiClient apiClient;
  final FlutterSecureStorage storage;

  Future<void> login(String username, String password) async {
    final data = await apiClient.post('/auth/login', {'username': username, 'password': password});
    await _saveTokens(data);
  }

  Future<void> registerOwner({
    required String fullName,
    required String mobileNumber,
    required String username,
    required String password,
    required String organizationName,
  }) async {
    final data = await apiClient.post('/auth/register-owner', {
      'fullName': fullName,
      'mobileNumber': mobileNumber,
      'username': username,
      'password': password,
      'organizationName': organizationName,
    });
    await _saveTokens(data);
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    await storage.write(key: 'accessToken', value: data['accessToken'] as String?);
    await storage.write(key: 'refreshToken', value: data['refreshToken'] as String?);
    await storage.write(key: 'organizationId', value: '${data['organizationId']}');
  }
}
