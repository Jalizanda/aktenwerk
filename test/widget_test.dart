import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aktenwerk/src/app.dart';

/// Smoke-Test: Die App baut ohne Firebase (Offline-Modus) auf und zeigt die
/// Shell. `pumpAndSettle` ist hier ungeeignet, weil Ladeindikatoren und
/// Hintergrund-Streams die App nie vollständig „zur Ruhe" kommen lassen –
/// deshalb werden gezielt einzelne Frames gepumpt.
void main() {
  testWidgets('App startet ohne Firebase und zeigt die Shell',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ProviderScope(child: AktenwerkApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);

    // App wieder abbauen, damit offene Timer/Streams sauber beendet werden.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
