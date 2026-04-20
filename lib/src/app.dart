import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/seed/demo_auto_reseed.dart';
import 'features/auth/auth_gate.dart';
import 'features/system/einstellungen/einstellungen_repository.dart';

class AktenwerkApp extends ConsumerStatefulWidget {
  const AktenwerkApp({super.key});

  @override
  ConsumerState<AktenwerkApp> createState() => _AktenwerkAppState();
}

class _AktenwerkAppState extends ConsumerState<AktenwerkApp> {
  late final _router = buildRouter();

  ThemeMode _mode(String? v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(einstellungenProvider);
    final mode = _mode(settings.valueOrNull?[SettingsKeys.theme]);

    // Auto-Re-Seed-Wächter aktivieren (siehe demo_auto_reseed.dart).
    ref.watch(demoAutoReseedProvider);

    return MaterialApp.router(
      title: 'Aktenwerk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('de'), Locale('en')],
      locale: const Locale('de'),
      routerConfig: _router,
      // AuthGate umhüllt den gesamten Router-Inhalt: solange niemand
      // angemeldet ist, sieht der Besucher ausschließlich den Login-Screen,
      // nie die Sidebar oder ein Modul.
      builder: (context, child) =>
          AuthGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
