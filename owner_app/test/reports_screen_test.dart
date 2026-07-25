import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import 'package:pg_manager_owner_app/src/app_state.dart';
import 'package:pg_manager_owner_app/src/reports/report_download.dart';
import 'package:pg_manager_owner_app/src/screens/reports_screen.dart';
import 'package:pg_manager_owner_app/src/widgets/app_toast.dart';

import 'support/test_harness.dart';

/// The Reports tab is filters + Download PDF, nothing else. These tests drive
/// the filters and assert the *request* each card issues; PDF rendering itself
/// is covered headlessly in rent_collection_pdf_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A download writes to disk and then opens the file. path_provider is mocked
  // to a temp dir; the open step goes through debugOpenSavedFile, because the
  // real OpenFilex launches a viewer process on desktop.
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempDir;
  final openedPaths = <String>[];

  setUp(() {
    openedPaths.clear();
    tempDir = Directory.systemTemp.createTempSync('reports_test');
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
      // Windows can still hold the handle briefly; the OS reaps %TEMP% anyway.
    }
  });

  /// Basenames of the PDFs actually written during a test.
  List<String> savedFiles() => tempDir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .toList();

  AppState ownerState(FakeApiClient fake) => AppState(apiClient: fake)
    ..initialized = true
    ..isLoggedIn = true
    ..roleTypeId = 'OWNER';

  final now = DateTime.now();
  final thisMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  String d(DateTime x) =>
      '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> emptyReport() => {
        'month': thisMonth,
        'summary': const {},
        'items': const [],
        'categories': const [],
        'months': const [],
        'expenseByCategory': const [],
      };

  /// Pumped by hand rather than through `pumpDataScreen`: the tab needs a
  /// Scaffold (its filter InkWells require a Material ancestor), and toasts go
  /// into the root overlay behind [AppToast.navigatorKey] — without that key on
  /// the MaterialApp, `AppToast` finds no overlay and silently shows nothing.
  Future<void> pumpReports(WidgetTester tester, FakeApiClient fake) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: ownerState(fake),
        child: MaterialApp(
          navigatorKey: AppToast.navigatorKey,
          home: const Scaffold(
            body: ReportsTab(propertyId: 7, propertyName: 'Sunrise PG'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Cards are in a fixed order: 0 Rent Collection, 1 Outstanding Due,
  /// 2 Expense, 3 Profit & Loss.
  ///
  /// A download does real file I/O, which pumped (fake) time does not advance —
  /// hence `runAsync` to let it actually finish. And no pumpAndSettle: the
  /// result toast removes itself after 3s and settling would run past it, so
  /// tests assert on the toast first, then settle to flush its timer.
  Future<void> tapDownload(WidgetTester tester, int card) async {
    final button =
        find.widgetWithText(FilledButton, 'Download PDF').at(card);
    await tester.scrollUntilVisible(button, 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(button);
    await tester.pump();
    // Wait on the *open* step, not the file: the PDF lands on disk a beat
    // before the download finishes. A failed download never opens anything, so
    // the loop simply runs out — hence the cap.
    for (var i = 0; i < 60 && openedPaths.isEmpty; i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('lists the four reports with their filters', (tester) async {
    await pumpReports(tester, FakeApiClient());

    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Generate and download reports with specific filters.'),
        findsOneWidget);
    expect(find.text('Rent Collection Report'), findsOneWidget);
    expect(find.text('Outstanding Due Report'), findsOneWidget);
    expect(find.text('Expense Report'), findsOneWidget);
    expect(find.text('Profit & Loss Report'), findsOneWidget);

    // Month on three cards, a Category picker on Expense, and a From/To pair
    // on P&L. Outstanding Due is month-only — no tenant filter.
    expect(find.text('Month'), findsNWidgets(3));
    expect(find.text('Tenant'), findsNothing);
    expect(find.text('All Tenants'), findsNothing);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('All Categories'), findsOneWidget);
    expect(find.text('From Date'), findsOneWidget);
    expect(find.text('To Date'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Download PDF'), findsNWidgets(4));

    // Nothing is fetched until a download is asked for.
    expect((tester.widget<ReportsTab>(find.byType(ReportsTab))).propertyId, 7);
  });

  testWidgets('Rent Collection downloads for the selected month',
      (tester) async {
    final path = '/reports/rent-collection?propertyId=7&month=$thisMonth';
    final fake = FakeApiClient()..stubGet(path, emptyReport());

    await pumpReports(tester, fake);
    await tapDownload(tester, 0);

    expect(fake.getCalls, [path]);
    // Written straight to storage and handed to a viewer — no chooser, no
    // share sheet.
    expect(savedFiles().single, startsWith('rent-collection-'));
    expect(openedPaths.single, endsWith(savedFiles().single));
    expect(find.textContaining('No invoices for'), findsOneWidget);
    expect(find.textContaining('saved to'), findsOneWidget);
  });

  testWidgets('Outstanding Due covers the whole property for the month',
      (tester) async {
    final path = '/reports/outstanding-dues?propertyId=7&month=$thisMonth';
    // No tenant stub: fetching the tenant list would fail the test, since
    // FakeApiClient errors on any unstubbed GET.
    final fake = FakeApiClient()..stubGet(path, emptyReport());

    await pumpReports(tester, fake);
    await tapDownload(tester, 1);

    // Month is the only filter — the report is the property's whole arrears list.
    expect(fake.getCalls, [path]);
    expect(savedFiles().single, startsWith('outstanding-dues-'));
  });

  testWidgets('Expense report passes the chosen category', (tester) async {
    final path =
        '/reports/expenses?propertyId=7&month=$thisMonth&category=WATER';
    final fake = FakeApiClient()..stubGet(path, emptyReport());

    await pumpReports(tester, fake);

    await tester.tap(find.text('All Categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Water'));
    await tester.pumpAndSettle();
    expect(find.text('Water'), findsOneWidget); // now the field's value

    await tapDownload(tester, 2);
    expect(fake.getCalls.last, path);
  });

  testWidgets('Profit & Loss sends the from/to range', (tester) async {
    final from = DateTime(now.year, now.month, 1);
    final path =
        '/reports/profit-loss?propertyId=7&from=${d(from)}&to=${d(now)}';
    final fake = FakeApiClient()..stubGet(path, emptyReport());

    await pumpReports(tester, fake);
    await tapDownload(tester, 3);

    expect(fake.getCalls.last, path);
    expect(savedFiles().single, startsWith('profit-loss-'));
  });

  testWidgets('the month filter picks month and year only', (tester) async {
    final prevMonth = DateTime(now.year, now.month - 1);
    final param =
        '${prevMonth.year}-${prevMonth.month.toString().padLeft(2, '0')}';
    final path = '/reports/rent-collection?propertyId=7&month=$param';
    final fake = FakeApiClient()..stubGet(path, emptyReport());

    await pumpReports(tester, fake);
    await tester.tap(find.text(DateFormat('MMM yyyy').format(now)).first);
    await tester.pumpAndSettle();

    // Month + year only: a year stepper over twelve month chips, no day grid.
    expect(find.text('Select Month'), findsOneWidget);
    expect(find.text('${now.year}'), findsOneWidget);
    for (final m in ['Jan', 'Feb', 'Nov', 'Dec']) {
      expect(find.text(m), findsOneWidget);
    }

    await tester.tap(find.text(DateFormat('MMM').format(prevMonth)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Select'));
    await tester.pumpAndSettle();

    expect(find.text(DateFormat('MMM yyyy').format(prevMonth)), findsOneWidget);

    await tapDownload(tester, 0);
    expect(fake.getCalls.last, path);
    await tester.pumpAndSettle();
  });

  testWidgets('a failed fetch surfaces the error and clears the busy state',
      (tester) async {
    final path = '/reports/rent-collection?propertyId=7&month=$thisMonth';
    final fake = FakeApiClient()
      ..stubGetError(path, Exception('Report service unavailable'));

    await pumpReports(tester, fake);
    await tapDownload(tester, 0);

    expect(find.text('Report service unavailable'), findsOneWidget);
    expect(savedFiles(), isEmpty);
    // Button is usable again, not stuck on "Preparing…".
    expect(find.text('Preparing…'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Download PDF'), findsNWidgets(4));
  });
}
