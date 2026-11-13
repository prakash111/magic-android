import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:magicai_mobile/widgets/tool_render_boundary.dart';

void main() {
  setUp(() {
    final previous = ErrorWidget.builder;
    ErrorWidget.builder = ToolRenderBoundary.errorBuilder(previous);
    addTearDown(() => ErrorWidget.builder = previous);
  });

  for (final dark in [true, false]) {
    testWidgets('descendant build errors recover with themed Retry ($dark)', (
      tester,
    ) async {
      var shouldFail = true;
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          home: Scaffold(
            bottomNavigationBar: const Text('Bottom navigation'),
            body: ToolRenderBoundary(
              message: 'Video settings could not be displayed. Please retry.',
              onRetry: () async {
                retries++;
                shouldFail = false;
              },
              builder: (_) => Column(
                children: [
                  Builder(
                    builder: (_) {
                      if (shouldFail) {
                        throw StateError('Sensitive malformed configuration');
                      }
                      return const Text('Video Configuration');
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isA<StateError>());
      await tester.pumpAndSettle();
      expect(
        find.text('Video settings could not be displayed. Please retry.'),
        findsOneWidget,
      );
      expect(find.text('Bottom navigation'), findsOneWidget);
      expect(find.textContaining('Sensitive'), findsNothing);
      expect(find.byType(ErrorWidget), findsNothing);
      final recovery = tester.widget<ColoredBox>(
        find
            .ancestor(of: find.text('Retry'), matching: find.byType(ColoredBox))
            .first,
      );
      expect(
        recovery.color,
        (dark ? AppTheme.darkTheme : AppTheme.lightTheme)
            .scaffoldBackgroundColor,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(retries, 1);
      expect(find.text('Video Configuration'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'synchronous builders fail safely and failed refresh keeps Retry',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ToolRenderBoundary(
              message: 'Refresh video settings',
              onRetry: () async => throw StateError('Refresh failed'),
              builder: (_) => throw const FormatException('Malformed schema'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Refresh video settings'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('errors outside the boundary retain the original error handler', (
    tester,
  ) async {
    final original = ErrorWidget.builder;
    var delegated = 0;
    ErrorWidget.builder = ToolRenderBoundary.errorBuilder((details) {
      delegated++;
      return const Text('Host error handler');
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: (_) => throw StateError('Unrelated screen')),
        ),
      ),
    );
    expect(tester.takeException(), isA<StateError>());
    await tester.pumpAndSettle();
    expect(delegated, 1);
    expect(find.text('Host error handler'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    ErrorWidget.builder = original;
  });
}
