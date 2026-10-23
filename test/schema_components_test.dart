import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/schema_components.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:magicai_mobile/theme/design.dart';

Future<void> _pump(WidgetTester tester, List<Map> items) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ListView(
            children: buildStyledComponents(
              context,
              items,
              (_) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('Marketing Bot overview labels become tiles', (tester) async {
    await _pump(tester, [
      {'type': 'heading', 'text': 'Broadcast messages to your audience instantly.'},
      {'type': 'heading', 'text': 'Overview'},
      {'type': 'text', 'text': 'All Campaigns'},
      {'type': 'text', 'text': 'Scheduled Campaigns'},
      {'type': 'text', 'text': 'Published Campaigns'},
      {'type': 'text', 'text': 'Total Contacts'},
    ]);
    expect(find.byType(SchemaIntro), findsOneWidget);
    expect(find.byType(SchemaSectionHeader), findsOneWidget);
    expect(find.byType(SchemaTile), findsNWidgets(4));
  });

  testWidgets('Tasks statuses become tabs', (tester) async {
    await _pump(tester, [
      {'type': 'heading', 'text': 'Pending'},
      {'type': 'text', 'text': 'ramu Srivastava'},
      {'type': 'text', 'text': 'Oct 13, 2027 00:00'},
      {'type': 'heading', 'text': 'Completed'},
      {'type': 'heading', 'text': 'Cancelled'},
    ]);
    expect(find.byType(SchemaStatusTabs), findsOneWidget);
    expect(find.byType(SchemaInfoCard), findsOneWidget);
    expect(find.text('ramu Srivastava'), findsOneWidget);
    await tester.tap(find.text('Completed'));
    await tester.pump();
    expect(find.byType(SchemaInfoCard), findsNothing);
    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  test('compactNumber shortens large credit values', () {
    expect(compactNumber(142005000), '142.0M');
    expect(compactNumber('45000000'), '45.0M');
    expect(compactNumber(87), '87');
    expect(compactNumber('Unlimited'), 'Unlimited');
  });
}
