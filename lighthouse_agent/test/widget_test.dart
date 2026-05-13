import 'package:flutter_test/flutter_test.dart';

import 'package:lighthouse_agent/main.dart';

void main() {
  testWidgets('Lighthouse status window smoke test', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LighthouseApp());

    expect(find.text('Lighthouse Agent'), findsOneWidget);
    expect(
      find.text('Active sessions will appear here in Day 6.'),
      findsOneWidget,
    );
  });
}
