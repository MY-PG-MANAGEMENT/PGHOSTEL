import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pg_manager_owner_app/src/screens/auth/login_screen.dart';

import 'support/test_harness.dart';

void main() {
  group('LoginScreen', () {
    testWidgets('renders username + password fields and Sign in button',
        (tester) async {
      await pumpScreen(tester, const LoginScreen(), state: FakeAppState());

      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Username'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('submitting an empty form shows validation errors and does not call login',
        (tester) async {
      final state = FakeAppState();
      await pumpScreen(tester, const LoginScreen(), state: state);

      await tester.tap(find.text('Sign in'));
      await tester.pump();

      // Both required fields report an error.
      expect(find.text('Required'), findsNWidgets(2));
      // login() must not have been attempted.
      expect(state.loginCalls, isEmpty);
    });

    testWidgets('valid credentials call AppState.login and navigate to dashboard',
        (tester) async {
      final state = FakeAppState();
      await pumpScreen(tester, const LoginScreen(), state: state);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username'), 'owner_01');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'secret12');

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(state.loginCalls, hasLength(1));
      expect(state.loginCalls.single.username, 'owner_01');
      expect(state.loginCalls.single.password, 'secret12');
      // Navigated to the dashboard placeholder route.
      expect(find.text('route:dashboard'), findsOneWidget);
    });

    testWidgets('login failure surfaces a SnackBar with the error message',
        (tester) async {
      final state = FakeAppState()..loginError = Exception('Invalid credentials');
      await pumpScreen(tester, const LoginScreen(), state: state);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Username'), 'owner_01');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'wrongpass');

      await tester.tap(find.text('Sign in'));
      await tester.pump(); // run the async action
      await tester.pump(); // let the SnackBar appear

      expect(state.loginCalls, hasLength(1));
      expect(find.text('Invalid credentials'), findsOneWidget);
      // Stayed on the login screen (no navigation).
      expect(find.text('route:dashboard'), findsNothing);
    });
  });
}
