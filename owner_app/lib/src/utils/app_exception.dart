import 'dart:io';

class NetworkException implements Exception {
  const NetworkException();
  @override
  String toString() => 'No internet connection';
}

class ServerException implements Exception {
  const ServerException([this.message = 'Server is temporarily unavailable']);
  final String message;
  @override
  String toString() => message;
}

bool isNetworkError(Object e) =>
    e is NetworkException ||
    e is SocketException ||
    e is HandshakeException;
