import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aktenwerk/src/app.dart';

void main() {
  testWidgets('App startet mit Dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: AktenwerkApp()));
    await tester.pumpAndSettle();
    expect(find.text('Aktenwerk'), findsWidgets);
  });
}
