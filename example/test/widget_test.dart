import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_admob_ads_manager_example/main.dart';

void main() {
  testWidgets('renders the demo page without initializing ads', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Ads Manager Demo'), findsOneWidget);
    expect(find.text('Show Interstitial'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
