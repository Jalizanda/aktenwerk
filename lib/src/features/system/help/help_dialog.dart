import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/aw_tokens.dart';

/// Modaler Hilfe-Dialog mit Arbeitsablauf, Shortcuts, Modul-Übersicht
/// und Tipps — 1:1 aus der SV-Software (an Aktenwerk angepasst).
Future<void> showHelpDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => const _HelpDialog(),
  );
}

class _HelpDialog extends StatelessWidget {
  const _HelpDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 820),
        child: Column(
          children: [
            _header(context),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _WelcomeCard(),
                  const SizedBox(height: 16),
                  _twoColumns(_WorkflowCard(), _ShortcutsCard()),
                  const SizedBox(height: 16),
                  const _ModulesCard(),
                  const SizedBox(height: 16),
                  const _TippsCard(),
                  const SizedBox(height: 16),
                  const _FaqCard(),
                  const SizedBox(height: 16),
                  const _MobileCard(),
                ],
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
            child: const Icon(Icons.help_outline,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hilfe & Anleitung',
                    style: Theme.of(context).textTheme.titleLarge),
                Text(
                  'Funktionsübersicht, typische Arbeitsabläufe und Tipps',
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

  Widget _twoColumns(Widget a, Widget b) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 900) {
        return Column(children: [a, const SizedBox(height: 16), b]);
      }
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: a),
            const SizedBox(width: 16),
            Expanded(child: b),
          ],
        ),
      );
    });
  }
}

class _WelcomeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.waving_hand_outlined,
                size: 20, color: AppTheme.accent600),
            SizedBox(width: 8),
            Text('Willkommen bei Aktenwerk',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          const Text(
            'Aktenwerk ist die komplette Akten-, Gutachten- und Abrechnungs-'
            'Software für Bausachverständige. Unten findest du die wichtigsten '
            'Funktionen und Arbeitsabläufe.',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _WorkflowCard extends StatelessWidget {
  static const _items = [
    ['Anfrage erfassen',
        'Sidebar → Angebote → „+ Neues Angebot". Bei Zusage öffnet „→ in Auftrag umwandeln" automatisch einen Auftrag.'],
    ['Auftrag bearbeiten',
        'Sidebar → Aufträge → Klick auf Zeile öffnet den Auftrags-Dialog mit Tabs Allgemein / Objekt / Gericht / Termine & Honorar / Aufgaben & Geräte.'],
    ['Ortstermin vor Ort',
        'Ortstermin-Modus auf Tablet/Handy: Fotos + GPS, Notizen, Stunden-Timer.'],
    ['Stunden / Auslagen',
        'Werkzeuge → Stunden / Auslagen. Timer mit Pause/Stopp, JVEG-Defaults bei Auslagen.'],
    ['Gutachten schreiben',
        'Akten → Gutachten → „+ Neues Gutachten". Rich-Text-Editor pro Abschnitt, Vorlagen für Bauschaden/Beweissicherung/Mängel.'],
    ['Rechnung stellen',
        'Akten → Rechnungen → „+ Neue Rechnung" → „Honorar aus Stunden" + „Auslagen übernehmen". SEPA-QR (GiroCode) ist automatisch auf der Rechnung.'],
    ['Erläuterungstermin',
        'Akten → Erläuterungstermine: Ladung erfassen, JVEG-Vergütung live berechnen (Termin + Wartezeit + Fahrt), Status nachhalten.'],
    ['Eingangsrechnungen',
        'Akten → Eingangsrechnungen: Lieferant aus Stamm, Skonto, Zahlungsweise, DATEV-SKR03/04-Kategorie, Beleg-Upload.'],
    ['Auswerten',
        'Auswertung → Steuer & Statistik (USt-Voranmeldung, BWA-Monatstabelle, Charts), Jahresbericht (IHK).'],
    ['Nachhalten',
        'Wiedervorlagen, OPOS / Mahnwesen, Termine & Fristen mit Eskalations-Farben.'],
  ];

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.rocket_launch_outlined,
                size: 18, color: AppTheme.accent600),
            SizedBox(width: 8),
            Text('Typischer Arbeitsablauf',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppTheme.accent50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accent700)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 12.5,
                            height: 1.5),
                        children: [
                          TextSpan(
                            text: '${_items[i][0]} — ',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: _items[i][1]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ShortcutsCard extends StatelessWidget {
  static const _items = [
    ['Sortierbare Tabellen',
        'Klick auf Spaltenkopf sortiert auf-/absteigend (Pfeil zeigt Richtung).'],
    ['Globale Suche',
        'Oben in der Top-Bar — Akten, Gutachten, Rechnungen, Angebote, Bausteine in einem Feld.'],
    ['Formeln in Mengen/Preisen',
        'Eingabe mit = startet: =2*3 → 6, =(50+75)/2 → 62,5.'],
    ['Timer',
        'Werkzeuge → Stunden → „▶ Start". Timer läuft weiter, Buchen per Klick.'],
    ['Artikel einfügen',
        'In Angeboten/Rechnungen „Artikel einfügen" öffnet den Katalog-Picker.'],
    ['Honorar aus Stunden',
        'In der Rechnungs-Maske ein Klick — aggregiert alle offenen Stunden des Auftrags.'],
    ['JVEG-Auslagen-Vorlage',
        'Bei Typ „JVEG-Rechnung" gibt es eine Vorlage mit Fahrt/Kopien/Lichtbilder.'],
    ['Eskalations-Farben',
        'Termine & Fristen werden nach Tagen rot/orange/gelb/grün markiert.'],
    ['GiroCode',
        'Rechnungen bekommen automatisch einen SEPA-QR unten rechts.'],
    ['Kleinunternehmer-§19',
        'Checkbox in der Rechnungs-Summenkarte blendet USt komplett aus.'],
    ['Org-Switcher',
        'Rechts oben in der Top-Bar — wechselt zwischen Demo- und Produktiv-Mandant.'],
    ['Hot-Reload ',
        'Nach jedem neuen Release: Browser mit ⌘⇧R / Strg+F5 neu laden.'],
  ];

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.bolt_outlined,
                size: 18, color: AppTheme.accent600),
            SizedBox(width: 8),
            Text('Wichtige Shortcuts & Kniffe',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          for (final item in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                      color: Colors.black87, fontSize: 12.5, height: 1.5),
                  children: [
                    const TextSpan(text: '• '),
                    TextSpan(
                      text: '${item[0]} ',
                      style:
                          const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: '— ${item[1]}'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModulesCard extends StatelessWidget {
  const _ModulesCard();
  static const _items = [
    ['Dashboard',
        'KPIs, Finanzen, Pipeline, Stunden, Heute, Fristen, Kalibrierung, Fortbildungsfortschritt, Umsatz-Chart.'],
    ['Auftraggeber',
        'Kunden mit Typen Privat/Firma/Anwalt/Gericht/Versicherung/Behörde. Gerichts-Datenbank mit 158 Einträgen.'],
    ['Angebote',
        '7-stufiger Status mit Farb-Badges, Pipeline-KPIs (Pipeline/Gewonnen/Conversion). „→ in Auftrag umwandeln" + Auftragsbestätigung als PDF.'],
    ['Aufträge',
        'Alle Akten mit 4 Auftragsarten (Privat/Gericht/Schiedsgutachten/Beweissicherung). Tabs für Objekt, Gericht, Termine & Honorar, Aufgaben & Geräte.'],
    ['Gutachten',
        'Zöller-Struktur mit Rich-Text-Editor, Vorlagen (Bauschaden/Beweissicherung/Mängel).'],
    ['Erläuterungstermine',
        'Ladung erfassen, JVEG-Vergütung live berechnen, Status (geplant/geladen/vorbereitet/durchgeführt/vergütet).'],
    ['Rechnungen',
        'Privat, JVEG, Gutschrift, Korrektur in einem Modul. Honorar aus Stunden, Auslagen übernehmen, §19-UStG, SEPA-QR automatisch.'],
    ['Eingangsrechnungen',
        'Belege mit SKR-Kategorie, Lieferanten-Auto-Fill, Skonto, Zahlungsweise, Mehrfach-Beleg.'],
    ['Lieferanten',
        'Stammdaten mit Bank/IBAN/BIC, USt-IdNr, Gläubiger-ID, Mandat, Zahlungsziel.'],
    ['Artikel / Leistungen',
        'Kalkulierte Artikel, in Angeboten/Rechnungen per „Artikel einfügen" picken.'],
    ['Messgeräte',
        'Inventar, Eichung/Kalibrierung (rot wenn überfällig, orange bei ≤60 Tagen), Pro Akte zuordenbar.'],
    ['Normen',
        'Bibliothek + Akten-Normen mit PDF-Upload. Bibliothek wird im Gutachten als Anlage referenziert.'],
    ['Textbausteine',
        'Kategorien (auftrag/objekt/feststellungen/…), Favoriten, Suche, Sachgebiete.'],
    ['Stunden',
        'Timer mit Start/Stopp, Summary pro Auftrag (Stunden + Betrag), JVEG-Rechner.'],
    ['Auslagen',
        'Fahrtkosten, Schreibauslagen, Lichtbilder, Kopien mit JVEG-Defaults.'],
    ['Kalkulation',
        'Kostenschätzung mit Gewerke-Gruppierung + Ist/Soll-Übersicht (Stunden + Auslagen + Rechnungen).'],
    ['Fotos',
        'Multi-Upload mit Raum- und GPS-Feld, Grid-Ansicht, automatische Einbindung in Lichtbildanlage.'],
    ['Termine',
        'Ortstermine und Abgabefristen zusammengeführt, 4-Stufen-Eskalations-Farben.'],
    ['Wiedervorlagen',
        'Akten mit Stichtag auf Wiedervorlage legen, Scope-Filter (Alle/Heute/Woche/Überfällig/Offen/Erledigt). Wiederholung (täglich/wöchentlich/monatlich), Checkliste, Auto-Trigger „Mahnung prüfen" 14 Tage nach Rechnungs-Fälligkeit. Browser-Benachrichtigungen für fällige Punkte.'],
    ['Journal (in der Akte)',
        'Chronologisches Projekt-Tagebuch: Telefonate, Mails, Ortstermine, Rückfragen mit Datum + Uhrzeit + Kontakt.'],
    ['Mängel-Register (in der Akte)',
        'Nummerierte Mängel mit Priorität A/B/C nach DIN 4426, Bauteil, Ursache, Folge, geschätzter Aufwand. Summen je Priorität.'],
    ['Bauteilöffnungen (in der Akte)',
        'Dokumentierte Bauteil-Öffnungen mit Lage, Methode, anwesenden Personen, Befund und Foto vor/nach.'],
    ['Messwerte (in der Akte)',
        'Logger für Temperatur, Feuchte, Schall, BlowerDoor — Zeitverlaufs-Chart, CSV-Export. Für Langzeit-Messungen.'],
    ['Wertermittlung (in der Akte)',
        'ImmoWertV-Rechner: Bodenwert, Sachwert mit Alterswertminderung, Marktanpassung, Vergleichswert, Verkehrswert.'],
    ['Übergabe (in der Akte)',
        'Aktenübergabe-Protokoll an Kollegen: Datum, Umfang, mitgegebene Unterlagen.'],
    ['Qualifikationen',
        'Diplome, Zertifikate, Prüfungen mit Ablauf-Ampel (rot/orange/grün) und PDF-Upload. Als Standard-Anhang zum Gutachten markierbar.'],
    ['CO₂-Tracker',
        'Klimabilanz aus Fahrt-km und Druckkopien (UBA-Faktoren). KPI-Kacheln und Jahres-Summen.'],
    ['Google-Kalender-Sync',
        'Einstellungen → Google Kalender: Ortstermine/Fristen/Erläuterungen/Wiedervorlagen in einen Google-Kalender spiegeln. Auto-Sync bei Änderungen.'],
    ['Backup & Wiederherstellung',
        'Einstellungen → Backup: JSON-Export aller Tabellen der lokalen DB, Import überschreibt alle lokalen Daten.'],
    ['Ortstermin-Modus',
        'Fokussierte Mobile-Ansicht: Akte wählen, Fotos hochladen, Notizen anhängen, Timer laufen lassen, Notizen an Akte pushen.'],
    ['JVEG-Rechner',
        '§ 9 Honorar (M1/M2/M3), § 5 Fahrt, § 7 Schreibauslagen / Lichtbilder / Kopien. Aufstellung in Zwischenablage.'],
    ['OPOS / Mahnwesen',
        'Offene Rechnungen mit Mahnstufen (im Ziel / Erinnerung / 1. Mahnung / 2. Mahnung) und Zeilenfarben.'],
    ['Steuer & Statistik',
        'USt-Voranmeldung pro Quartal, BWA-Monatstabelle, Umsatz-Chart.'],
    ['Jahresbericht',
        'KPI-Leiste, Aufträge nach Art + Sachgebiet, Umsatz- und Sachgebiete-Charts.'],
    ['Fortbildungen & Befangenheit',
        'UE-Nachweise pro Jahr, separates Tab „Befangenheits-Register" mit Live-Suche.'],
    ['Administration',
        'Nur Super-Admin: Benutzer-Freischaltung, Mandanten-Approval, Demo-Seeding.'],
  ];

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.folder_special_outlined,
                size: 18, color: AppTheme.accent600),
            SizedBox(width: 8),
            Text('Module im Überblick',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          for (var i = 0; i < _items.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 200,
                    child: Text(_items[i][0],
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: Text(_items[i][1],
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ),
            if (i < _items.length - 1)
              const Divider(
                  height: 1, color: AppTheme.slate200, thickness: 0.5),
          ],
        ],
      ),
    );
  }
}

class _TippsCard extends StatelessWidget {
  const _TippsCard();
  @override
  Widget build(BuildContext context) {
    return _Card(
      color: AwTokens.amberSoft,
      borderColor: AwTokens.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.lightbulb_outline, size: 18, color: AwTokens.amber),
            SizedBox(width: 8),
            Text('Tipps für neue Nutzer',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AwTokens.amber)),
          ]),
          const SizedBox(height: 10),
          const Text(
            '• Erster Start — Demo-Mandant in der Top-Bar auswählen und dort '
            'durch die Module klicken. Alle Beispieldaten (Kunden, Aufträge, '
            'Rechnungen, Fotos) sind hinterlegt.\n'
            '• Eigene Stammdaten — System → Benutzer: Name, Titel, Logo, IBAN/BIC, '
            'Bestellungstexte hinterlegen (erscheinen in PDF-Ausdrucken).\n'
            '• Nummernkreise — System → Einstellungen: Muster '
            '(z. B. "A{YYYY}-###") und Startzähler anpassen.\n'
            '• Mandant wechseln — Org-Switcher rechts oben in der Top-Bar.\n'
            '• Produktiv stellen — Für eigene Daten in den Produktiv-Mandanten '
            '"Bauelemente-Experte" wechseln.',
            style: TextStyle(fontSize: 12.5, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _FaqCard extends StatelessWidget {
  const _FaqCard();

  static const _qas = <List<String>>[
    [
      'Wo landen meine Daten?',
      'Alle Einträge werden lokal in deinem Browser gespeichert (IndexedDB). '
          'Pro Mandant eine eigene lokale Datenbank — Demo- und Produktiv-Daten '
          'sind physisch getrennt. Zusätzlich wird pro Mandant in Firestore '
          'synchronisiert, wenn du angemeldet bist.',
    ],
    [
      'Wie mache ich ein Backup meiner Daten?',
      'Einstellungen → „Backup & Wiederherstellung" → „Backup herunterladen". '
          'Du bekommst eine JSON-Datei mit allen 35 Tabellen. Leg die '
          'regelmäßig (z. B. vor jedem größeren Arbeitsschritt) auf deinem '
          'Rechner oder in der Cloud ab.',
    ],
    [
      'Wie spiele ich ein Backup zurück?',
      'Einstellungen → „Backup & Wiederherstellung" → „Backup einspielen …". '
          'Die JSON-Datei auswählen und bestätigen. ACHTUNG: Die komplette '
          'aktuelle lokale DB wird dabei ersetzt.',
    ],
    [
      'Ich wechsle zwischen Demo und Produktiv — sehe ich dann die richtigen Daten?',
      'Ja. Ab Version 0.11 hat jeder Mandant eine eigene lokale Datenbank. '
          'Der Wechsel im Org-Switcher schließt die alte DB und öffnet die '
          'neue. Änderungen an einem Mandanten beeinflussen die anderen nicht.',
    ],
    [
      'Nach einem Deploy erscheint die Seite grau.',
      'Das bedeutet, dass ein alter Service-Worker noch Daten aus dem Cache '
          'liefert. Aktenwerk räumt das automatisch auf und lädt die Seite '
          'einmal frisch. Beim nächsten Mal sollte der Start normal sein. '
          'Falls es einmal nicht geht: https://aktenwerk-app.web.app/fresh.html '
          'öffnen.',
    ],
    [
      'Wie funktioniert die Google-Kalender-Synchronisation?',
      'Einstellungen → „Google Kalender" → „Verbinden". Popup bestätigen '
          '(erlaubt Aktenwerk Zugriff auf deinen Kalender). Danach Kalender '
          'auswählen und einmal „Jetzt synchronisieren" klicken. Ab dann läuft '
          'der Sync automatisch bei jeder Termin-Änderung und beim App-Start.',
    ],
    [
      'Wie lege ich Vorlagen für Anschreiben an?',
      'Werkzeuge → Textbausteine → Kategorie „anschreiben". Du kannst '
          'Platzhalter wie {{aktenzeichen}}, {{gericht}}, {{betreff}}, '
          '{{heute}} verwenden. Beim Einfügen im Anschreiben werden die '
          'Platzhalter automatisch durch die Werte aus der gewählten Akte '
          'ersetzt.',
    ],
    [
      'Wo wird das Gutachten geschrieben?',
      'Akte → Tab „Gutachten". Im Gutachten-Editor Rich-Text bearbeiten, '
          'Textbausteine picken, PDF exportieren. Qualifikationen mit '
          'Flag „Standard-Anhang" werden dem Gutachten automatisch '
          'beigelegt.',
    ],
    [
      'Mein Produktiv-Mandant soll auch nach neuen Releases erhalten bleiben — wie?',
      '1) Schema-Migrationen sind strikt additiv (keine Drop-All-Schritte). '
          '2) Pro Mandant eigene DB — kein Überschreiben durch Demo. '
          '3) Trotzdem: regelmäßig per Einstellungen → Backup ein JSON '
          'herunterladen und ablegen. Das ist die letzte Sicherheit.',
    ],
    [
      'Wie lege ich eine Akontoanforderung, Teilrechnung oder Schlussrechnung an?',
      'Im Rechnungs-Editor den Typ wählen. Akontoanforderungen bekommen '
          'einen eigenen Nummernkreis (Default AZ{YYYY}-{NNN}) und sind '
          'USt-technisch erst mit Zahlungseingang relevant — Aktenwerk '
          'weist im Editor darauf hin. Teilrechnungen sind sofort '
          'USt-pflichtig. Eine Schlussrechnung mit verknüpftem Auftrag '
          'zeigt eine grüne Übersichts-Kachel aller bezahlten Akonto- und '
          'aller Teilrechnungen; „Abzüge übernehmen" fügt sie mit '
          'Rechnungsnummer, Datum und Zahldatum als negative Positionen in '
          'den Beleg ein.',
    ],
    [
      'Wie wird der Nummernkreis zum Jahreswechsel behandelt?',
      'Aktenwerk setzt den Zähler standardmäßig NICHT automatisch zurück '
          '(GoBD-konforme, lückenlose Nummerierung). Wenn du zum 01.01. '
          'eines Jahres neu bei 1 starten willst, trage das unter '
          'Einstellungen → Nummernkreise beim jeweiligen Kreis manuell '
          'ein und setze die „Nächste Nummer" auf 1. Oder stelle den '
          'Reset auf „jahr", wenn die Software das automatisch tun soll.',
    ],
    [
      'Kann ich einen bereits versendeten Serienbrief nochmal verwenden?',
      'Ja. Unter Werkzeuge → Serienbriefe gibt es oben den Button '
          '„Historie". Klick auf einen alten Eintrag lädt Betreff, Anrede, '
          'Grußformel, Brieftext, Versandart und die Empfängerliste '
          'zurück ins Formular — du kannst anpassen und erneut versenden.',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.question_answer_outlined,
                size: 18, color: AppTheme.accent600),
            SizedBox(width: 8),
            Text('Häufige Fragen',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          for (var i = 0; i < _qas.length; i++) ...[
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Text(_qas[i][0],
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10, right: 8),
                    child: Text(_qas[i][1],
                        style: const TextStyle(
                            fontSize: 12.5, height: 1.5)),
                  ),
                ),
              ],
            ),
            if (i < _qas.length - 1)
              const Divider(
                  height: 1, color: AppTheme.slate200, thickness: 0.5),
          ],
        ],
      ),
    );
  }
}

class _MobileCard extends StatelessWidget {
  const _MobileCard();
  @override
  Widget build(BuildContext context) {
    return _Card(
      color: BadgeColorsConst.blueBg,
      borderColor: BadgeColorsConst.blueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.phone_iphone, size: 18, color: AwTokens.blue),
            SizedBox(width: 8),
            Text('Mobile Arbeit',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AwTokens.blue)),
          ]),
          const SizedBox(height: 10),
          const Text(
            '• PWA installieren — Im Browser-Menü „Zum Startbildschirm hinzufügen". '
            'Aktenwerk öffnet sich ohne Browserleiste, alle Daten bleiben auf dem Gerät.\n'
            '• Ortstermin-Modus — Am Tablet öffnen, Akte wählen, Fotos & Notizen sammeln. '
            'Beim Speichern werden Notizen an den Auftrag gehängt.\n'
            '• Responsive Layout — Sidebar wird bei schmaler Breite automatisch '
            'zu einem Drawer (Hamburger-Icon).',
            style: TextStyle(fontSize: 12.5, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class BadgeColorsConst {
  static const blueBg = AwTokens.blueSoft;
  static const blueBorder = AwTokens.line;
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.color, this.borderColor});
  final Widget child;
  final Color? color;
  final Color? borderColor;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor ?? AppTheme.slate200),
      ),
      child: child,
    );
  }
}
