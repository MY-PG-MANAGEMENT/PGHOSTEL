import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pg_manager_owner_app/src/screens/auth/register_screen.dart';

import 'support/test_harness.dart';

void main() {
  // Helper: fill every field on the register form.
  Future<void> fillForm(
    WidgetTester tester, {
    required String fullName,
    required String mobile,
    required String username,
    required String password,
    required String confirm,
    required String org,
  }) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Full Name'), fullName);
    await tester.enterText(find.widgetWithText(TextFormField, 'Mobile Number'), mobile);
    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), username);
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), password);
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm Password'), confirm);
    await tester.enterText(find.widgetWithText(TextFormField, 'Organization Name'), org);
  }

  group('RegisterScreen', () {
    testWidgets('renders all fields and the Create Account button', (tester) async {
      await pumpScreen(tester, const RegisterScreen(), state: FakeAppState());

      expect(find.text('Create account'), findsOneWidget);
      for (final label in const [
        'Full Name',
        'Mobile Number',
        'Username',
        'Password',
        'Confirm Password',
        'Organization Name',
      ]) {
        expect(find.widgetWithText(TextFormField, label), findsOneWidget,
            reason: 'missing field: $label');
      }
      expect(find.text('Create Account'), findsOneWidget);
    });

    testWidgets('blank form shows required errors and does not call registerOwner',
        (tester) async {
      final state = FakeAppState();
      await pumpScreen(tester, const RegisterScreen(), state: state);

      await tester.tap(find.text('Create Account'));
      await tester.pump();

      // Six fields, all required.
      expect(find.text('Required'), findsNWidgets(6));
      expect(state.registerCalls, isEmpty);
    });

    testWidgets('short name / username / password and bad mobile are flagged',
        (tester) async {
      final state = FakeAppState();
      await pumpScreen(tester, const RegisterScreen(), state: state);

      await fillForm(
        tester,
        fullName: 'A', // too short (< 2)
        mobile: '123', // not 10 digits
        username: 'ab', // too short (< 4)
        password: 'short', // too short (< 8)
        confirm: 'short',
        org: 'Acme PG',
      );

      await tester.tap(find.text('Create Account'));
      await tester.pump();

      expect(find.text('Must be at least 2 characters'), findsOneWidget);
      expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
      expect(find.text('Must be at least 4 characters'), findsOneWidget);
      expect(find.text('Must be at least 8 characters'), findsOneWidget);
      expect(state.registerCalls, isEmpty);
    });

    testWidgets('mismatched passwords block submission', (tester) async {
      final state = FakeAppState();
      await pumpScreen(tester, const RegisterScreen(), state: state);

      await fillForm(
        tester,
        fullName: 'Jane Owner',
        mobile: '9876543210',
        username: 'jane_owner',
        password: 'secret12',
        confirm: 'different9',
        org: 'Acme PG',
      );

      await tester.tap(find.text('Create Account'));
      await tester.pump();

      expect(find.text('Passwords do not match'), findsOneWidget);
      expect(state.registerCalls, isEmpty);
    });

    testWidgets('valid form passes validation, calls registerOwner, navigates to onboarding',
        (tester) async {
      final state = FakeAppState();
      await pumpScreen(tester, const RegisterScreen(), state: state);

      await fillForm(
        tester,
        fullName: 'Jane Owner',
        mobile: '9876543210',
        username: 'jane_owner',
        password: 'secret12',
        confirm: 'secret12',
        org: 'Acme PG',
      );

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(state.registerCalls, hasLength(1));
      final call = state.registerCalls.single;
      expect(call['fullName'], 'Jane Owner');
      expect(call['mobileNumber'], '9876543210');
      expect(call['username'], 'jane_owner');
      expect(call['organizationName'], 'Acme PG');
      expect(find.text('route:onboarding'), findsOneWidget);
    });
  });
}
