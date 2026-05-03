import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/akten/akte/akte_screen.dart';
import '../../features/akten/akte/akten_screen.dart';
import '../../features/angebote/auftragsbestaetigungen/auftragsbestaetigungen_screen.dart';
import '../../features/akten/dokumente/dokumente_screen.dart';
import '../../features/akten/eingangsrechnungen/eingangsrechnungen_screen.dart';
import '../../features/akten/erlaeuterungen/erlaeuterungen_screen.dart';
import '../../features/akten/gutachten/gutachten_screen.dart';
import '../../features/akten/kontakte/kontakte_screen.dart';
import '../../features/akten/lieferanten/lieferanten_screen.dart';
import '../../features/akten/rechnungen/rechnungen_screen.dart';
import '../../features/angebote/angebote/angebote_screen.dart';
import '../../features/angebote/anschreiben/anschreiben_screen.dart';
import '../../features/auswertung/banking/banking_screen.dart';
import '../../features/auswertung/befangenheit/befangenheit_screen.dart';
import '../../features/auswertung/co2/co2_screen.dart';
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
import '../../features/akten/gutachten/gutachten_abschnitt_editor.dart';
import '../../features/akten/lv/lv_editor_screen.dart';
import '../../features/akten/lv/lv_katalog_screen.dart';
import '../../features/akten/lv/lv_screen.dart';
import '../../features/system/admin/admin_screen.dart';
import '../../features/system/einstellungen/einstellungen_screen.dart';
import '../../features/system/legal/datenschutz_screen.dart';
import '../../features/system/org/organisation_screen.dart';
import '../../features/werkzeuge/fotos/fotos_screen.dart';
import '../../features/werkzeuge/geraete/geraete_screen.dart';
import '../../features/werkzeuge/jveg_rechner/jveg_rechner_screen.dart';
import '../../features/werkzeuge/normen/normen_screen.dart';
import '../../features/werkzeuge/qualifikationen/qualifikationen_screen.dart';
import '../../features/akten/partner/partner_screen.dart';
import '../../features/werkzeuge/ortstermin/ortstermin_screen.dart';
import '../../features/werkzeuge/serienbrief/serienbrief_screen.dart';
import '../../features/werkzeuge/termine/termine_screen.dart';
import '../../features/werkzeuge/normen/normen_chat_screen.dart';
import '../../features/werkzeuge/recherche_ablage/recherche_ablage_screen.dart';
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
          GoRoute(path: '/kunden', builder: (_, _) => const KontakteScreen()),
          GoRoute(path: '/akten', builder: (_, _) => const AktenScreen()),
          GoRoute(
              path: '/akte/:id',
              builder: (_, state) => AkteScreen(
                    auftragId:
                        int.parse(state.pathParameters['id'] ?? '0'),
                  )),
          GoRoute(
              path: '/auftraege',
              builder: (_, _) => const AuftragsbestaetigungenScreen()),
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
              path: '/dokumente',
              builder: (_, _) => const DokumenteScreen()),
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
          GoRoute(
              path: '/recherche',
              builder: (_, _) => const RechercheAblageScreen()),
          GoRoute(path: '/fotos', builder: (_, _) => const FotosScreen()),
          GoRoute(path: '/termine', builder: (_, _) => const TermineScreen()),
          GoRoute(
              path: '/wiedervorlagen',
              builder: (_, _) => const WiedervorlagenScreen()),
          GoRoute(path: '/jveg', builder: (_, _) => const JvegRechnerScreen()),
          GoRoute(
              path: '/ortstermin',
              builder: (_, _) => const OrtsterminScreen()),
          GoRoute(
              path: '/serienbrief',
              builder: (_, _) => const SerienbriefScreen()),
          GoRoute(path: '/partner', builder: (_, _) => const PartnerScreen()),
          GoRoute(path: '/opos', builder: (_, _) => const OposScreen()),
          GoRoute(path: '/steuer', builder: (_, _) => const SteuerScreen()),
          GoRoute(
              path: '/jahresbericht',
              builder: (_, _) => const JahresberichtScreen()),
          GoRoute(
              path: '/fortbildungen',
              builder: (_, _) => const FortbildungenScreen()),
          GoRoute(
              path: '/befangenheit',
              builder: (_, _) => const BefangenheitScreen()),
          GoRoute(
              path: '/banking',
              builder: (_, _) => const BankingScreen()),
          GoRoute(
              path: '/qualifikationen',
              builder: (_, _) => const QualifikationenScreen()),
          GoRoute(path: '/co2', builder: (_, _) => const Co2Screen()),
          GoRoute(path: '/lv', builder: (_, _) => const LvScreen()),
          GoRoute(
              path: '/lv/katalog',
              builder: (_, _) => const LvKatalogScreen()),
          GoRoute(
              path: '/lv/:id',
              builder: (_, state) => LvEditorScreen(
                  lvId: int.parse(state.pathParameters['id']!))),
          GoRoute(
              path: '/einstellungen',
              builder: (_, _) => const EinstellungenScreen()),
          GoRoute(
              path: '/benutzer', builder: (_, _) => const BenutzerScreen()),
          GoRoute(
              path: '/organisation',
              builder: (_, _) => const OrganisationScreen()),
          GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
          GoRoute(
              path: '/datenschutz',
              builder: (_, _) => const DatenschutzScreen()),
        ],
      ),
      // Standalone-Route außerhalb der Shell: wird als eigenes Browser-
      // Fenster verwendet, damit der Nutzer parallel weiterarbeiten kann.
      GoRoute(
          path: '/normen/chat',
          builder: (_, _) => const NormenChatScreen()),
      GoRoute(
        path: '/gutachten-abschnitt/:gid/:key',
        builder: (_, state) => GutachtenAbschnittEditorScreen(
          gutachtenId: int.parse(state.pathParameters['gid']!),
          abschnittKey: state.pathParameters['key']!,
        ),
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
