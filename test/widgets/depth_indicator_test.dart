import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:career_path/widgets/depth_indicator.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows "Level N of M" with dots', (tester) async {
    await tester.pumpWidget(wrap(
      const DepthIndicator(currentDepth: 2, maxDepth: 5),
    ));
    expect(find.text('Level 2 of 5'), findsOneWidget);
    // 5 dots total (Container widgets with circle)
    final dots = find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).shape == BoxShape.circle);
    expect(dots, findsNWidgets(5));
  });

  testWidgets('shows "Level N" without dots when maxDepth is null',
      (tester) async {
    await tester.pumpWidget(wrap(
      const DepthIndicator(currentDepth: 3),
    ));
    expect(find.text('Level 3'), findsOneWidget);
    final dots = find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).shape == BoxShape.circle);
    expect(dots, findsNothing);
  });

  testWidgets('compact mode when maxDepth > 8 (no dots)', (tester) async {
    await tester.pumpWidget(wrap(
      const DepthIndicator(currentDepth: 3, maxDepth: 10),
    ));
    expect(find.text('Level 3 of 10'), findsOneWidget);
    final dots = find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).shape == BoxShape.circle);
    expect(dots, findsNothing);
  });

  testWidgets('all dots filled at leaf (currentDepth == maxDepth)',
      (tester) async {
    await tester.pumpWidget(wrap(
      const DepthIndicator(currentDepth: 4, maxDepth: 4),
    ));
    expect(find.text('Level 4 of 4'), findsOneWidget);
    final dots = find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).shape == BoxShape.circle);
    expect(dots, findsNWidgets(4));
  });
}
