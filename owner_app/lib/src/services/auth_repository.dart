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

  /// Tenant login by mobile + password. Returns the raw result:
  /// - `{needsOrgSelection: true, organizations: [...]}` when the mobile maps to
  ///   more than one org and none was chosen — tokens are NOT saved.
  /// - `{auth: {...}}` on success — tokens + tenant flags are persisted.
  Future<Map<String, dynamic>> tenantLogin(String mobile, String password, {int? organizationId}) async {
    final data = await apiClient.post('/auth/tenant/login', {
      'mobile': mobile,
      'password': password,
      if (organizationId != null) 'organizationId': organizationId,
    });
    if (data['needsOrgSelection'] == true) return data;
    final auth = (data['auth'] as Map).cast<String, dynamic>();
    await _saveTokens(auth);
    await storage.write(key: 'mustChangePassword', value: '${auth['mustChangePassword'] == true}');
    await storage.write(key: 'partyId', value: '${auth['partyId']}');
    return data;
  }

  Future<void> registerOwner({
    required String fullName,
    required String mobileNumber,
    required String username,
    required String password,
    required String organizationName,
    required String organizationEmail,
  }) async {
    final data = await apiClient.post('/auth/register-owner', {
      'fullName': fullName,
      'mobileNumber': mobileNumber,
      'username': username,
      'password': password,
      'organizationName': organizationName,
      'organizationEmail': organizationEmail,
    });
    await _saveTokens(data);
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    await storage.write(key: 'accessToken', value: data['accessToken'] as String?);
    await storage.write(key: 'refreshToken', value: data['refreshToken'] as String?);
    await storage.write(key: 'organizationId', value: '${data['organizationId']}');
    await storage.write(key: 'roleTypeId', value: data['roleTypeId'] as String?);
    await storage.write(key: 'fullName', value: data['fullName'] as String?);
  }
}
