import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/services/api_client.dart';

/// A test double for [ApiClient] that lets each test decide, per request path,
/// whether a `get`/`post`/`put`/`patch`/`delete` call should resolve with a value,
/// throw an error, or hang on a pending future (so a loading spinner or an
/// in-flight save can be observed).
///
/// These methods are all non-final on [ApiClient], so overriding them is safe. We
/// still call `super(...)` with a real (canonicalised) `const
/// FlutterSecureStorage()` — no network or storage I/O ever happens because the
/// overrides never call into the parent's `_send`.
class FakeApiClient extends ApiClient {
  FakeApiClient() : super(storage: const FlutterSecureStorage());

  /// Per-path GET responders. The key is the exact path passed to `get`.
  final Map<String, _Responder> _getResponders = {};

  /// Per-path POST responders. The key is the exact path passed to `post`.
  final Map<String, _Responder> _postResponders = {};

  /// Records every `get` path requested, in order.
  final List<String> getCalls = [];

  /// Per-path DELETE responders. The key is the exact path passed to `delete`.
  final Map<String, _Responder> _deleteResponders = {};

  /// Records every `post` path requested, in order.
  final List<String> postCalls = [];

  /// Records the body of every `post`, in order (parallel to [postCalls]).
  final List<Map<String, dynamic>> postBodies = [];

  /// Records every `delete` path requested, in order.
  final List<String> deleteCalls = [];

  /// Per-path PATCH responders. The key is the exact path passed to `patch`.
  final Map<String, _Responder> _patchResponders = {};

  /// Records every `patch` path requested, in order.
  final List<String> patchCalls = [];

  /// Records the body of every `patch`, in order (parallel to [patchCalls]).
  final List<Map<String, dynamic>> patchBodies = [];

  /// Per-path PUT responders. The key is the exact path passed to `put`.
  final Map<String, _Responder> _putResponders = {};

  /// Records every `put` path requested, in order.
  final List<String> putCalls = [];

  /// Records the body of every `put`, in order (parallel to [putCalls]).
  final List<Map<String, dynamic>> putBodies = [];

  /// Make [get] on [path] resolve with [data]. Note: list payloads are wrapped
  /// by the real client as `{'items': <list>}`; replicate that here, e.g.
  /// `stubGet('/tenants', {'items': [...]})`.
  void stubGet(String path, Map<String, dynamic> data) =>
      _getResponders[path] = _Responder.value(data);

  /// Make [get] on [path] throw [error].
  void stubGetError(String path, Object error) =>
      _getResponders[path] = _Responder.error(error);

  /// Make [get] on [path] return a future that never completes (loading state).
  /// The returned [Completer] can be completed later to release the spinner.
  Completer<Map<String, dynamic>> stubGetPending(String path) {
    final completer = Completer<Map<String, dynamic>>();
    _getResponders[path] = _Responder.pending(completer);
    return completer;
  }

  /// Make [post] on [path] resolve with [data].
  void stubPost(String path, Map<String, dynamic> data) =>
      _postResponders[path] = _Responder.value(data);

  /// Make [post] on [path] throw [error].
  void stubPostError(String path, Object error) =>
      _postResponders[path] = _Responder.error(error);

  /// Make [put] on [path] resolve with [data].
  void stubPut(String path, [Map<String, dynamic> data = const {}]) =>
      _putResponders[path] = _Responder.value(data);

  /// Make [put] on [path] throw [error].
  void stubPutError(String path, Object error) =>
      _putResponders[path] = _Responder.error(error);

  /// Make [delete] on [path] resolve with [data].
  void stubDelete(String path, [Map<String, dynamic> data = const {}]) =>
      _deleteResponders[path] = _Responder.value(data);

  /// Make [delete] on [path] throw [error].
  void stubDeleteError(String path, Object error) =>
      _deleteResponders[path] = _Responder.error(error);

  /// Make [patch] on [path] resolve with [data].
  void stubPatch(String path, [Map<String, dynamic> data = const {}]) =>
      _patchResponders[path] = _Responder.value(data);

  /// Make [patch] on [path] throw [error].
  void stubPatchError(String path, Object error) =>
      _patchResponders[path] = _Responder.error(error);

  /// Make [patch] on [path] return a future that never completes, so an
  /// in-flight save (e.g. a toggle's pending spinner) can be observed.
  Completer<Map<String, dynamic>> stubPatchPending(String path) {
    final completer = Completer<Map<String, dynamic>>();
    _patchResponders[path] = _Responder.pending(completer);
    return completer;
  }

  @override
  Future<Map<String, dynamic>> get(String path) {
    getCalls.add(path);
    final responder = _getResponders[path];
    if (responder == null) {
      return Future.error(
          StateError('FakeApiClient: no GET stub registered for "$path"'));
    }
    return responder.respond();
  }

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) {
    postCalls.add(path);
    postBodies.add(body);
    final responder = _postResponders[path];
    if (responder == null) {
      return Future.error(
          StateError('FakeApiClient: no POST stub registered for "$path"'));
    }
    return responder.respond();
  }

  @override
  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) {
    putCalls.add(path);
    putBodies.add(body);
    final responder = _putResponders[path];
    if (responder == null) {
      return Future.error(
          StateError('FakeApiClient: no PUT stub registered for "$path"'));
    }
    return responder.respond();
  }

  @override
  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) {
    patchCalls.add(path);
    patchBodies.add(body);
    final responder = _patchResponders[path];
    if (responder == null) {
      return Future.error(
          StateError('FakeApiClient: no PATCH stub registered for "$path"'));
    }
    return responder.respond();
  }

  @override
  Future<Map<String, dynamic>> delete(String path) {
    deleteCalls.add(path);
    final responder = _deleteResponders[path];
    if (responder == null) {
      return Future.error(
          StateError('FakeApiClient: no DELETE stub registered for "$path"'));
    }
    return responder.respond();
  }
}

class _Responder {
  _Responder.value(Map<String, dynamic> value) : _value = value;
  _Responder.error(Object error) : _error = error;
  _Responder.pending(Completer<Map<String, dynamic>> completer)
      : _completer = completer;

  Map<String, dynamic>? _value;
  Object? _error;
  Completer<Map<String, dynamic>>? _completer;

  Future<Map<String, dynamic>> respond() {
    if (_completer != null) return _completer!.future;
    if (_error != null) return Future.error(_error!);
    return Future.value(_value!);
  }
}

/// A test double for [AppState] that records auth calls instead of performing
/// any real network / secure-storage / platform work.
///
/// The auth methods ([login], [registerOwner], [biometricLogin]) are plain
/// (non-final) instance methods on [AppState], so they can be safely overridden
/// here. We never access [AppState.apiClient] (a `late final`), so no real
/// [ApiClient] is ever constructed during these tests.
class FakeAppState extends AppState {
  FakeAppState() {
    // Screens redirect / read state assuming the app is initialised & logged out.
    initialized = true;
    isLoggedIn = false;
  }

  /// Recorded `login(username, password)` invocations.
  final List<({String username, String password})> loginCalls = [];

  /// Recorded `registerOwner(...)` invocations.
  final List<Map<String, String>> registerCalls = [];

  /// When set, the corresponding auth method throws this instead of succeeding.
  Object? loginError;
  Object? registerError;

  @override
  Future<void> login(String username, String password) async {
    loginCalls.add((username: username, password: password));
    if (loginError != null) {
      isLoggedIn = false;
      notifyListeners();
      throw loginError!;
    }
    isLoggedIn = true;
    roleTypeId = 'OWNER';
    notifyListeners();
  }

  @override
  Future<void> registerOwner({
    required String fullName,
    required String mobileNumber,
    required String username,
    required String password,
    required String organizationName,
    required String organizationEmail,
  }) async {
    registerCalls.add({
      'fullName': fullName,
      'mobileNumber': mobileNumber,
      'username': username,
      'password': password,
      'organizationName': organizationName,
      'organizationEmail': organizationEmail,
    });
    if (registerError != null) throw registerError!;
    isLoggedIn = true;
    roleTypeId = 'OWNER';
    notifyListeners();
  }

  @override
  Future<bool> biometricLogin() async => false;

  @override
  Future<bool> canUseBiometricUnlock() async => false;

  @override
  Future<void> restoreSession() async {
    initialized = true;
    notifyListeners();
  }
}

/// Pumps [screen] inside a minimal [MaterialApp.router] so that `context.go(...)`
/// works, with [state] provided as the [AppState] for `context.read<AppState>()`.
///
/// Destination routes render trivial placeholders so we can assert navigation
/// without dragging in real (network-bound) screens.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required AppState state,
  String initialLocation = '/test',
  Size surfaceSize = const Size(800, 1600),
}) async {
  // A tall surface keeps lazy ListView-based forms (e.g. RegisterScreen) fully
  // laid out so every field/button is found without scrolling.
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/test', builder: (_, __) => screen),
      GoRoute(path: '/login', builder: (_, __) => const _Placeholder('login')),
      GoRoute(path: '/register', builder: (_, __) => const _Placeholder('register')),
      GoRoute(path: '/forgot-password', builder: (_, __) => const _Placeholder('forgot')),
      GoRoute(path: '/dashboard', builder: (_, __) => const _Placeholder('dashboard')),
      GoRoute(path: '/onboarding', builder: (_, __) => const _Placeholder('onboarding')),
    ],
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

/// Pumps a self-contained data [screen] (one that builds its own [Scaffold]
/// and does not rely on the app router) inside a [MaterialApp] with [state]
/// provided. Use this for list/data screens driven by a [FakeApiClient].
Future<void> pumpDataScreen(
  WidgetTester tester,
  Widget screen, {
  required AppState state,
  Size surfaceSize = const Size(800, 1600),
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(home: screen),
    ),
  );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text('route:$name')));
  }
}
