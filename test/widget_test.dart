// Widget test for FlexPOS application.

import 'package:flutter_test/flutter_test.dart';

import 'package:flex_pos/main.dart';

void main() {
  testWidgets('FlexPOS app loads splash screen test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FlexPOSApp());

    // Verify that progress percentage indicator exists on splash screen.
    expect(find.text('0%'), findsOneWidget);
  });
}

