import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pg_manager_owner_app/src/utils/app_exception.dart';
import 'package:pg_manager_owner_app/src/widgets/error_retry_view.dart';

/// A small FutureBuilder-backed screen that mirrors the data-loading pattern
/// used across the real screens (loading -> data, loading -> error) but feeds
/// off an injected [Future] so no network is involved.
class _DataLoader extends StatelessWidget {
  const _DataLoader({required this.future, required this.onRetry});
  final Future<List<String>> future;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: FutureBuilder<List<String>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ErrorRetryView(error: snapshot.error!, onRetry: onRetry);
            }
            final items = snapshot.data ?? const [];
            return ListView(children: [for (final i in items) Text(i)]);
          },
        ),
      ),
    );
  }
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ErrorRetryView state rendering', () {
    testWidgets('network error shows the offline message', (tester) async {
      await tester.pumpWidget(
        _wrap(ErrorRetryView(error: const NetworkException(), onRetry: () {})),
      );
      expect(find.text('No Internet Connection'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('server error shows the unavailable message', (tester) async {
      await tester.pumpWidget(
        _wrap(ErrorRetryView(error: const ServerException(), onRetry: () {})),
      );
      expect(find.text('Server Unavailable'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });

    testWidgets('generic error shows its stripped message', (tester) async {
      await tester.pumpWidget(
        _wrap(ErrorRetryView(error: Exception('Boom failed'), onRetry: () {})),
      );
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Boom failed'), findsOneWidget); // 'Exception: ' stripped
    });

    testWidgets('tapping Try Again invokes the retry callback', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        _wrap(ErrorRetryView(error: const NetworkException(), onRetry: () => retried++)),
      );
      await tester.tap(find.text('Try Again'));
      await tester.pump();
      expect(retried, 1);
    });
  });

  group('FutureBuilder data-loading flow', () {
    testWidgets('loading spinner -> data list', (tester) async {
      await tester.pumpWidget(
        _DataLoader(future: Future.value(const ['Room A', 'Room B']), onRetry: () {}),
      );
      // Frame 1: still waiting -> spinner.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Room A'), findsOneWidget);
      expect(find.text('Room B'), findsOneWidget);
    });

    testWidgets('loading spinner -> ErrorRetryView on failure', (tester) async {
      // Delay so the FutureBuilder subscribes before the future errors,
      // ensuring the error is delivered to the builder (not flagged as
      // an unhandled async error).
      final failing = Future<List<String>>.delayed(
        const Duration(milliseconds: 10),
        () => throw const NetworkException(),
      );
      await tester.pumpWidget(_DataLoader(future: failing, onRetry: () {}));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.byType(ErrorRetryView), findsOneWidget);
      expect(find.text('No Internet Connection'), findsOneWidget);
    });
  });
}
