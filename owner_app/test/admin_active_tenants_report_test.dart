import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/reports/active_tenants_pdf.dart';
import 'package:pg_manager_owner_app/src/reports/report_download.dart';
import 'package:pg_manager_owner_app/src/screens/admin_screen.dart';
import 'package:pg_manager_owner_app/src/widgets/app_toast.dart';

import 'support/test_harness.dart';

/// Super-admin Reports (Active Tenants only, download-only) and the Per-Tenant
/// Pricing editor in System Settings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Same plumbing as reports_screen_test: a download writes to disk then opens
  // the file, so path_provider is mocked to a temp dir and the open step is
  // routed through debugOpenSavedFile (the real OpenFilex spawns a viewer).
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;
  final openedPaths = <String>[];

  setUp(() {
    openedPaths.clear();
    tempDir = Directory.systemTemp.createTempSync('admin_reports_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            pathProviderChannel, (call) async => tempDir.path);
    debugOpenSavedFile = (path) async {
      openedPaths.add(path);
      return true;
    };
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    debugOpenSavedFile = null;
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {
      // Windows can hold the handle briefly; %TEMP% is reaped by the OS anyway.
    }
  });

  List<String> savedFiles() => tempDir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .toList();

  final now = DateTime.now();
  final thisMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

  Map<String, dynamic> report() => {
        'month': thisMonth,
        'monthStart': '$thisMonth-01',
        'monthEnd': '$thisMonth-30',
        'summary': const {
          'organizationCount': 2,
          'billableOrganizations': 2,
          'totalActiveTenants': 25,
          'totalProperties': 4,
          'defaultPricePerTenant': 15.0,
          'totalAmount': 425.0,
        },
        'items': const [
          {
            'organizationId': 1,
            'organizationName': 'Sunrise PG',
            'activeTenants': 20,
            'propertyCount': 3,
            'pricePerTenant': 15.0,
            'customRate': false,
            'amount': 300.0,
          },
          {
            'organizationId': 2,
            'organizationName': 'Metro Stays',
            'activeTenants': 5,
            'propertyCount': 1,
            'pricePerTenant': 25.0,
            'customRate': true,
            'amount': 125.0,
          },
        ],
      };

  Map<String, dynamic> rates() => {
        'defaultPricePerTenant': 15.0,
        'items': const [
          {
            'organization_id': 1,
            'facility_name': 'Sunrise PG',
            'status': 'ACTIVE',
            'pricePerTenant': 15.0,
            'customRate': false,
          },
          {
            'organization_id': 2,
            'facility_name': 'Metro Stays',
            'status': 'ACTIVE',
            'pricePerTenant': 25.0,
            'customRate': true,
          },
        ],
      };

  /// The admin shell needs a wide viewport so the sidebar (>=900px) is on screen
  /// and sections can be reached by tapping their labels.
  Future<void> pumpAdmin(WidgetTester tester, FakeApiClient fake) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: AppState(apiClient: fake)
          ..initialized = true
          ..isLoggedIn = true
          ..roleTypeId = 'SUPER_ADMIN',
        child: MaterialApp(
          navigatorKey: AppToast.navigatorKey,
          home: const SuperAdminScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FakeApiClient adminFake() {
    final fake = FakeApiClient();
    // The Dashboard section loads on open, before Reports is ever tapped.
    fake.stubGet('/super-admin/dashboard', const {
      'totalOrganizations': 2,
      'activeOrganizations': 2,
      'totalProperties': 4,
      'totalTenants': 25,
      'monthlyRevenue': 0,
      'recentActivity': [],
    });
    return fake;
  }

  Future<void> openSection(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  /// A download does real file I/O, which pumped time does not advance — hence
  /// `runAsync`. Waits on the *open* step rather than the file: the PDF lands on
  /// disk a beat before the download completes. No `pumpAndSettle`, because the
  /// result toast self-removes after 3s and settling would run past it.
  Future<void> tapDownload(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Download PDF'));
    await tester.pump();
    for (var i = 0; i < 60 && openedPaths.isEmpty; i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// The System Settings page header has its own 'Save' button, so a bare
  /// `find.text('Save')` is ambiguous once the rate dialog is open.
  Finder dialogButton(String label) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(label));

  group('Super admin Reports', () {
    testWidgets('shows only the Active Tenants download card', (tester) async {
      final fake = adminFake();
      await pumpAdmin(tester, fake);
      await openSection(tester, 'Reports');

      expect(find.text('Active Tenants Report'), findsOneWidget);
      expect(find.text('Download PDF'), findsOneWidget);
      // The old read-only revenue table is gone.
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('Period'), findsNothing);
    });

    testWidgets('fetches nothing until a download is requested', (tester) async {
      final fake = adminFake();
      await pumpAdmin(tester, fake);
      await openSection(tester, 'Reports');

      // Opening the screen must not hit the report endpoint — same contract as
      // the owner-side Reports tab.
      expect(
        fake.getCalls.where((c) => c.contains('active-tenants')),
        isEmpty,
      );
    });

    testWidgets('downloads the report for the selected month', (tester) async {
      final fake = adminFake()
        ..stubGet('/super-admin/reports/active-tenants?month=$thisMonth', report());
      await pumpAdmin(tester, fake);
      await openSection(tester, 'Reports');

      await tapDownload(tester);

      expect(fake.getCalls,
          contains('/super-admin/reports/active-tenants?month=$thisMonth'));
      expect(savedFiles().single, startsWith('active-tenants-'));
      expect(savedFiles().single, endsWith('.pdf'));
      expect(openedPaths, hasLength(1));
    });

    testWidgets('surfaces a failed fetch and clears the busy state', (tester) async {
      final fake = adminFake()
        ..stubGetError('/super-admin/reports/active-tenants?month=$thisMonth',
            Exception('Server unavailable'));
      await pumpAdmin(tester, fake);
      await openSection(tester, 'Reports');

      await tapDownload(tester);

      expect(find.text('Server unavailable'), findsOneWidget);
      // The button comes back, so the admin can retry without leaving.
      expect(find.text('Download PDF'), findsOneWidget);
      expect(savedFiles(), isEmpty);
    });
  });

  group('Per-Tenant Pricing', () {
    FakeApiClient settingsFake() => adminFake()
      ..stubGet('/super-admin/system-settings', const {'items': []})
      ..stubGet('/super-admin/tenant-rates', {})
      ..stubGet('/super-admin/tenant-rates', rates());

    testWidgets('lists the default price and each org rate', (tester) async {
      final fake = settingsFake();
      await pumpAdmin(tester, fake);
      await openSection(tester, 'System Settings');

      expect(find.text('Per-Tenant Pricing'), findsOneWidget);
      expect(find.text('Default price'), findsOneWidget);
      expect(find.text('Sunrise PG'), findsOneWidget);
      expect(find.text('Metro Stays'), findsOneWidget);
      // Org 2 is on a negotiated rate; org 1 follows the default.
      expect(find.text('Custom rate'), findsOneWidget);
      expect(find.text('Default rate'), findsOneWidget);
    });

    testWidgets('saving an org rate PUTs the new price', (tester) async {
      final fake = settingsFake()..stubPut('/super-admin/tenant-rates/1');
      await pumpAdmin(tester, fake);
      await openSection(tester, 'System Settings');

      await tester.tap(find.text('Sunrise PG'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '18.50');
      await tester.tap(dialogButton('Save'));
      await tester.pumpAndSettle();

      expect(fake.putCalls, contains('/super-admin/tenant-rates/1'));
      expect(fake.putBodies.last['pricePerTenant'], 18.50);
    });

    testWidgets('the default price uses the organizationId 0 sentinel', (tester) async {
      final fake = settingsFake()..stubPut('/super-admin/tenant-rates/0');
      await pumpAdmin(tester, fake);
      await openSection(tester, 'System Settings');

      await tester.tap(find.text('Default price'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '20');
      await tester.tap(dialogButton('Save'));
      await tester.pumpAndSettle();

      expect(fake.putCalls, contains('/super-admin/tenant-rates/0'));
      expect(fake.putBodies.last['pricePerTenant'], 20);
    });

    testWidgets('resetting an override sends a null price', (tester) async {
      final fake = settingsFake()..stubPut('/super-admin/tenant-rates/2');
      await pumpAdmin(tester, fake);
      await openSection(tester, 'System Settings');

      // Metro Stays is on a custom rate, so "Use default" is offered.
      await tester.tap(find.text('Metro Stays'));
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('Use default'));
      await tester.pumpAndSettle();

      // Null is the signal that clears the override — not a missing field.
      expect(fake.putBodies.last['pricePerTenant'], isNull);
    });

    testWidgets('rejects a negative price without calling the API', (tester) async {
      final fake = settingsFake();
      await pumpAdmin(tester, fake);
      await openSection(tester, 'System Settings');

      await tester.tap(find.text('Sunrise PG'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '-5');
      await tester.tap(dialogButton('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Cannot be negative'), findsOneWidget);
      expect(fake.putCalls, isEmpty);
    });
  });

  group('Active Tenants PDF', () {
    test('renders a document with the totals row', () async {
      final bytes = await buildActiveTenantsPdf(report());

      // A real PDF, and big enough to hold the table rather than an empty page.
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('renders an empty month without throwing', () async {
      final bytes = await buildActiveTenantsPdf({
        'month': thisMonth,
        'summary': const {},
        'items': const [],
      });

      expect(bytes.length, greaterThan(500));
    });
  });
}
