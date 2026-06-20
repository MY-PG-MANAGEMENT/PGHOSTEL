import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({required this.storage});

  final FlutterSecureStorage storage;
  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.34:8080/api',
  );
  final String baseUrl = _configuredBaseUrl;

  Future<Map<String, dynamic>> get(String path) async {
    return _send('GET', path);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    return _send('POST', path, body: body);
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    return _send('PUT', path, body: body);
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) => _send('PATCH', path, body: body);
  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  Future<Map<String, dynamic>> _send(
      String method,
      String path, {
        Map<String, dynamic>? body,
        bool retry = true,
      }) async {

    final url = '$baseUrl$path';

    try {
      print('');
      print('══════════════════════════════');
      print('REQUEST');
      print('$method $url');

      if (body != null) {
        print('BODY: ${jsonEncode(body)}');
      }

      final request = http.Request(method, Uri.parse(url))
        ..headers.addAll(await _headers());

      if (body != null) {
        request.body = jsonEncode(body);
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      print('STATUS: ${response.statusCode}');
      print('RESPONSE: ${response.body}');
      print('══════════════════════════════');

      if (response.statusCode == 401 &&
          retry &&
          !path.startsWith('/auth/')) {

        print('Token expired. Refreshing...');

        final refreshed = await _refresh();

        if (refreshed) {
          return _send(
            method,
            path,
            body: body,
            retry: false,
          );
        }
      }

      return _decode(response);
    } catch (e, s) {

      print('');
      print('══════════════════════════════');
      print('API ERROR');
      print('$method $url');
      print(e);
      print(s);
      print('══════════════════════════════');

      rethrow;
    }
  }

  Future<bool> _refresh() async {
    final refreshToken = await storage.read(key: 'refreshToken');
    if (refreshToken == null) return false;
    final response = await http.post(
      Uri.parse('$baseUrl/auth/refresh'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    if (response.statusCode >= 400) {
      await storage.deleteAll();
      return false;
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final data = payload['data'] as Map<String, dynamic>;
    await storage.write(key: 'accessToken', value: data['accessToken'] as String?);
    await storage.write(key: 'refreshToken', value: data['refreshToken'] as String?);
    return true;
  }

  Future<Map<String, String>> _headers() async {
    final token = await storage.read(key: 'accessToken');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _decode(http.Response response) {

    if (response.body.isEmpty) {
      return {};
    }

    final body = jsonDecode(response.body);

    if (response.statusCode >= 400) {

      print('SERVER ERROR');
      print(response.body);

      throw Exception(
        body is Map
            ? body['message'] ?? 'Request failed'
            : 'Request failed',
      );
    }

    if (body is Map<String, dynamic>) {

      if (body['success'] == false) {
        throw Exception(
          body['message'] ?? 'Request failed',
        );
      }

      return body['data'] is Map<String, dynamic>
          ? body['data']
          : {'items': body['data']};
    }

    return {};
  }
}
