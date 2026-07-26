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

/// A 403 from the API: authenticated (or authenticatable) but not allowed — most
/// visibly a login into an organization a super admin has deactivated or suspended.
/// Typed so callers can tell "you are blocked, and here is why" apart from a plain
/// wrong-credentials failure without matching on the message text.
class AccessDeniedException implements Exception {
  const AccessDeniedException([this.message = 'Access denied']);
  final String message;
  @override
  String toString() => message;
}

bool isNetworkError(Object e) =>
    e is NetworkException ||
    e is SocketException ||
    e is HandshakeException;
