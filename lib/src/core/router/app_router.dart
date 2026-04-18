import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/akten/auftraege/auftraege_screen.dart';
import '../../features/akten/eingangsrechnungen/eingangsrechnungen_screen.dart';
import '../../features/akten/erlaeuterungen/erlaeuterungen_screen.dart';
import '../../features/akten/gutachten/gutachten_screen.dart';
import '../../features/akten/kunden/kunden_screen.dart';
import '../../features/akten/lieferanten/lieferanten_screen.dart';
import '../../features/akten/rechnungen/rechnungen_screen.dart';
import '../../features/angebote/angebote/angebote_screen.dart';
import '../../features/angebote/anschreiben/anschreiben_screen.dart';
import '../../features/auswertung/fortbildungen/fortbildungen_screen.dart';
import '../../features/auswertung/jahresbericht/jahresbericht_screen.dart';
import '../../features/auswertung/opos/opos_screen.dart';
import '../../features/auswertung/steuer/steuer_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/kalkulation/artikel/artikel_screen.dart';
import '../../features/kalkulation/auslagen/auslagen_screen.dart';
import '../../features/kalkulation/kalkulation/kalkulation_screen.dart';
import '../../features/kalkulation/stunden/stunden_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/system/benutzer/benutzer_screen.dart';
import '../../features/system/einstellungen/einstellungen_screen.dart';
import '../../features/werkzeuge/fotos/fotos_screen.dart';
import '../../features/werkzeuge/geraete/geraete_screen.dart';
import '../../features/werkzeuge/jveg_rechner/jveg_rechner_screen.dart';
import '../../features/werkzeuge/normen/normen_screen.dart';
import '../../features/werkzeuge/ortstermin/ortstermin_screen.dart';
import '../../features/werkzeuge/termine/termine_screen.dart';
import '../../features/werkzeuge/textbausteine/textbausteine_screen.dart';
import '../../features/werkzeuge/wiedervorlagen/wiedervorlagen_screen.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
          GoRoute(path: '/kunden', builder: (_, _) => const KundenScreen()),
          GoRoute(
              path: '/auftraege',
              builder: (_, _) => const AuftraegeScreen()),
          GoRoute(
              path: '/gutachten',
              builder: (_, _) => const GutachtenScreen()),
          GoRoute(
              path: '/erlaeuterungen',
              builder: (_, _) => const ErlaeuterungenScreen()),
          GoRoute(
              path: '/rechnungen',
              builder: (_, _) => const RechnungenScreen()),
          GoRoute(
              path: '/eingangsrechnungen',
              builder: (_, _) => const EingangsrechnungenScreen()),
          GoRoute(
              path: '/lieferanten',
              builder: (_, _) => const LieferantenScreen()),
          GoRoute(
              path: '/angebote', builder: (_, _) => const AngeboteScreen()),
          GoRoute(
              path: '/anschreiben',
              builder: (_, _) => const AnschreibenScreen()),
          GoRoute(path: '/artikel', builder: (_, _) => const ArtikelScreen()),
          GoRoute(path: '/stunden', builder: (_, _) => const StundenScreen()),
          GoRoute(path: '/auslagen', builder: (_, _) => const AuslagenScreen()),
          GoRoute(
              path: '/kalkulation',
              builder: (_, _) => const KalkulationScreen()),
          GoRoute(path: '/geraete', builder: (_, _) => const GeraeteScreen()),
          GoRoute(path: '/normen', builder: (_, _) => const NormenScreen()),
          GoRoute(
              path: '/textbausteine',
              builder: (_, _) => const TextbausteineScreen()),
          GoRoute(path: '/fotos', builder: (_, _) => const FotosScreen()),
          GoRoute(path: '/termine', builder: (_, _) => const TermineScreen()),
          GoRoute(
              path: '/wiedervorlagen',
              builder: (_, _) => const WiedervorlagenScreen()),
          GoRoute(path: '/jveg', builder: (_, _) => const JvegRechnerScreen()),
          GoRoute(
              path: '/ortstermin',
              builder: (_, _) => const OrtsterminScreen()),
          GoRoute(path: '/opos', builder: (_, _) => const OposScreen()),
          GoRoute(path: '/steuer', builder: (_, _) => const SteuerScreen()),
          GoRoute(
              path: '/jahresbericht',
              builder: (_, _) => const JahresberichtScreen()),
          GoRoute(
              path: '/fortbildungen',
              builder: (_, _) => const FortbildungenScreen()),
          GoRoute(
              path: '/einstellungen',
              builder: (_, _) => const EinstellungenScreen()),
          GoRoute(
              path: '/benutzer', builder: (_, _) => const BenutzerScreen()),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Nicht gefunden')),
      body: Center(
        child: Text('Keine Route für ${state.uri.path}'),
      ),
    ),
  );
}
