import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/badges.dart';

Future<void> showReleaseNotesDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => const _ReleaseNotesDialog(),
  );
}

/// Release-Notes-Dialog für Aktenwerk.
/// Die Einträge sind chronologisch absteigend (neueste oben).
class _ReleaseNotesDialog extends StatelessWidget {
  const _ReleaseNotesDialog();

  static const _releases = <_Release>[
    _Release(
      version: '0.8.0',
      datum: '2026-04-19',
      titel: 'Dashboard-Umbau, Admin-Bereich, Release-Notes & Hilfe',
      changes: [
        _Change(_ChangeType.feature,
            'Dashboard komplett neu: KPI-Kacheln, Quick-Actions, Finanzen-Kachel '
            '(offene Forderungen, überfällig, Umsatz Monat + Vormonatsvergleich), '
            'Pipeline-Kachel (Angebote), Stunden-Kachel (heute/Woche/offen abzurechnen), '
            'Heute-Block, Fristen-Liste, Kalibrierungs-Warnung, Fortbildungsstunden-Progress, '
            'Umsatz-Chart letzte 6 Monate — alles als responsives Wrap-Grid.'),
        _Change(_ChangeType.feature,
            'Super-Admin-Bereich: Nutzer freischalten, Mandanten prüfen, Demo-Seeding. '
            'Automatischer Bootstrap: erste Anmeldung mit der Admin-E-Mail erzeugt '
            'Demo-Mandant + Produktiv-Mandant "Bauelemente-Experte".'),
        _Change(_ChangeType.feature,
            'Registrierungs-Workflow mit Approval: Jeder neue User wird vom '
            'Super-Admin freigeschaltet und bekommt automatisch Lesezugriff auf den '
            'Demo-Mandanten.'),
        _Change(_ChangeType.feature,
            'Hilfe- und Release-Notes-Dialog in der Top-Bar.'),
        _Change(_ChangeType.design,
            'Modul-Titel aus der Top-Bar entfernt (wird ausschließlich im '
            'Modul-Header angezeigt).'),
        _Change(_ChangeType.design,
            'Einheitliches Farb-Setup: Sidebar + Modul-Bereich in Slate-50, '
            'Kacheln in Weiß, Tabellen-Zeilen mit Hover/Select analog zur '
            'Sidebar-Navigation.'),
        _Change(_ChangeType.design,
            'Logo in Sidebar und Login-Dialog deutlich größer.'),
      ],
    ),
    _Release(
      version: '0.7.0',
      datum: '2026-04-18',
      titel: 'Multi-Tenancy, Auth & Firebase-Deployment',
      changes: [
        _Change(_ChangeType.feature,
            'Mehrmandanten-Fähigkeit: Jeder Auftrag liegt in einer Organisation '
            'unter `organizations/{orgId}/...`. Mitgliedschaften mit Rollen '
            '(owner/admin/member/readonly).'),
        _Change(_ChangeType.feature,
            'Org-Switcher in der Top-Bar, Onboarding-Dialog (Organisation anlegen '
            'oder Einladung einlösen), Mitglieder-Verwaltung mit Einladungs-Codes.'),
        _Change(_ChangeType.feature,
            'Firebase-Auth mit Google + E-Mail, AuthGate blockt App-Zugriff ohne Login.'),
        _Change(_ChangeType.feature,
            'Firestore-Security-Rules: Org-Membership + User-Approval + '
            'SuperAdmin-Bypass.'),
        _Change(_ChangeType.feature,
            'Firebase Hosting auf aktenwerk.app und aktenwerk-app.web.app.'),
      ],
    ),
    _Release(
      version: '0.6.0',
      datum: '2026-04-18',
      titel: 'Volle Feld-Parität (Wave 2) — DB-Schema v4',
      changes: [
        _Change(_ChangeType.feature,
            'Lieferanten: Bank/Kontoinhaber/IBAN/BIC, Zahlungsweise '
            '(Überweisung/Lastschrift/Kreditkarte/PayPal), Zahlungsziel, '
            'Gläubiger-ID & Mandatsreferenz bei SEPA.'),
        _Change(_ChangeType.feature,
            'Eingangsrechnungen mit Lieferanten-Auto-Fill, Skonto (% + Frist), '
            'Zahlungsweise, DATEV-Konto + Kostenstelle, Leistungsdatum, Multi-Beleg-Feld.'),
        _Change(_ChangeType.feature,
            'Erläuterungstermine mit JVEG-Vergütung (dauer, wartezeit, fahrtKm, '
            'kmSatz, honorargruppe, stundensatz) und Live-Berechnungs-Karte.'),
        _Change(_ChangeType.feature,
            'Gutachten mit Nummer, Datum, Bezeichnung und Vorlagen '
            '(Bauschaden/Beweissicherung/Mängel).'),
        _Change(_ChangeType.feature,
            'Normen: PDF-Upload-Felder (Pfad/Storage-URL/Dateiname/Größe), '
            'Unterscheidung Bibliothek vs. Akten-Norm.'),
        _Change(_ChangeType.feature,
            'Aufträge: 4 Auftragsarten (Privat/Gericht/Schiedsgutachten/Beweissicherung), '
            'Aufgaben-Editor, Geräte-Zuordnung als Junction-Table, '
            'Zonen-Daten (Schnee/Wind).'),
        _Change(_ChangeType.feature,
            'Fotos: Raum-Feld.'),
      ],
    ),
    _Release(
      version: '0.5.0',
      datum: '2026-04-18',
      titel: 'Modul-Qualität (Wave 1)',
      changes: [
        _Change(_ChangeType.feature,
            'Termine mit 4-Stufen-Farb-Eskalation (rot/orange/gelb/grün nach Tagen).'),
        _Change(_ChangeType.feature,
            'OPOS-Mahnstufen nach SV-Original (im Ziel / Erinnerung / 1. Mahnung / '
            '2. Mahnung), Zeilen-Hintergrund farbig.'),
        _Change(_ChangeType.feature,
            'JVEG-Rechner komplett: § 7 Schreibauslagen (mit 1000er-Blöcken), '
            'Lichtbilder, Kopien s/w + farbig mit Staffel, Clipboard-Export.'),
        _Change(_ChangeType.feature,
            'Kalkulation: neuer Tab "Kostenschätzung" mit Gewerke-Gruppierung.'),
        _Change(_ChangeType.feature,
            'Fortbildungen: Tab "Befangenheits-Register" mit Live-Suche.'),
        _Change(_ChangeType.feature,
            'Jahresbericht + Steuer: KPI-Leiste, Bar-/Pie-Charts, '
            'USt-Voranmeldung pro Quartal, BWA-Monatstabelle.'),
        _Change(_ChangeType.feature,
            'Auslagen: KPI-Kacheln (Gesamt / offen / Top-Art).'),
        _Change(_ChangeType.feature,
            'Stunden: Summary-Tabelle pro Auftrag.'),
      ],
    ),
    _Release(
      version: '0.4.0',
      datum: '2026-04-17',
      titel: 'Angebote & Rechnungen — SV-Parität',
      changes: [
        _Change(_ChangeType.feature,
            'Angebote: 7-stufiger Status mit Farb-Badges, Pipeline-KPIs, '
            '"→ In Auftrag umwandeln"-Button, Auftragsbestätigung als PDF.'),
        _Change(_ChangeType.feature,
            'Rechnungen: 4 Typen (Privat/JVEG/Gutschrift/Korrektur), '
            '"Honorar aus Stunden" / "JVEG-Auslagen" / "Auslagen übernehmen"-Buttons, '
            '§19-UStG-Kleinunternehmer-Modus.'),
        _Change(_ChangeType.feature,
            'PDF-Ausdruck SV-Original: Logo oben rechts, Absender-Mini-Zeile, '
            'Positionen-Tabelle mit Langtext, Summen-Block.'),
        _Change(_ChangeType.feature,
            'SEPA-QR (GiroCode) auf Rechnungen nach EPC-069-12.'),
      ],
    ),
    _Release(
      version: '0.3.0',
      datum: '2026-04-15',
      titel: 'Alle Module aus SV-Software portiert',
      changes: [
        _Change(_ChangeType.feature,
            'Komplette Port der Original-SV-Software: Kunden mit Gerichts-Datenbank '
            '(158 Einträge), Aufträge, Gutachten mit Rich-Text, Rechnungen, '
            'Angebote, Eingangsrechnungen, Dokumente, Lieferanten.'),
        _Change(_ChangeType.feature,
            'Werkzeuge: Artikel, Messgeräte, Normen, Textbausteine, Stunden, '
            'Auslagen, Fotos, Termine, Wiedervorlagen, Ortstermin-Modus, JVEG-Rechner.'),
        _Change(_ChangeType.feature,
            'Auswertungen: OPOS, Steuer & Statistik, Jahresbericht, Fortbildungen.'),
        _Change(_ChangeType.feature,
            '285+ Demo-Datensätze aus SV-Software seedDemo portiert.'),
      ],
    ),
    _Release(
      version: '0.2.0',
      datum: '2026-04-10',
      titel: 'Flutter-Grundgerüst',
      changes: [
        _Change(_ChangeType.feature,
            'Flutter 3.11 Cross-Platform-App (Web/Desktop/Mobile) mit Drift (SQLite), '
            'Riverpod, go_router, Material 3.'),
        _Change(_ChangeType.design,
            'SV-Software-Look: Slate + Orange, Inter-Schrift, Heroicons, Sidebar-Layout.'),
      ],
    ),
    _Release(
      version: '0.1.0',
      datum: '2026-04-08',
      titel: 'Erstveröffentlichung Aktenwerk',
      changes: [
        _Change(_ChangeType.feature,
            'Aktenwerk als Cloud-native Flutter-Anwendung — Portierung der '
            'Original-SV-Software (HTML/JS/IndexedDB) auf moderne Tech-Stack.'),
      ],
    ),
  ];

  static String get currentVersion => _releases.first.version;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 820),
        child: Column(
          children: [
            _header(context),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: _releases.length,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (_, i) => _ReleaseCard(r: _releases[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.accent600,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.campaign_outlined,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Release-Notes',
                    style: Theme.of(context).textTheme.titleLarge),
                Text(
                  'Aktuelle Version: $currentVersion',
                  style: TextStyle(fontSize: 12, color: AppTheme.slate500),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: 'Schließen',
          ),
        ],
      ),
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.r});
  final _Release r;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppTheme.slate200),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'v${r.version}',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.accent700),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  r.titel,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              Text(r.datum,
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.slate500)),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          for (final c in r.changes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _typeBadge(c.type),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      c.text,
                      style: const TextStyle(fontSize: 12.5, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _typeBadge(_ChangeType t) {
    final (label, bg, fg) = switch (t) {
      _ChangeType.feature =>
        ('NEU', BadgeColors.greenBg, BadgeColors.greenFg),
      _ChangeType.fix => ('FIX', BadgeColors.redBg, BadgeColors.redFg),
      _ChangeType.design =>
        ('DESIGN', BadgeColors.indigoBg, BadgeColors.indigoFg),
    };
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 2),
      alignment: Alignment.center,
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: fg,
              letterSpacing: 0.5)),
    );
  }
}

enum _ChangeType { feature, fix, design }

class _Change {
  final _ChangeType type;
  final String text;
  const _Change(this.type, this.text);
}

class _Release {
  final String version;
  final String datum;
  final String titel;
  final List<_Change> changes;
  const _Release({
    required this.version,
    required this.datum,
    required this.titel,
    required this.changes,
  });
}
