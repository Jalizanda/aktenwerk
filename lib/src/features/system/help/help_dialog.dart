import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

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
        'Akten mit Stichtag auf Wiedervorlage legen, Scope-Filter (Alle/Heute/Woche/Überfällig/Offen/Erledigt).'],
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
      color: const Color(0xFFFFFBEB),
      borderColor: const Color(0xFFFDE68A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.lightbulb_outline,
                size: 18, color: Color(0xFFB45309)),
            SizedBox(width: 8),
            Text('Tipps für neue Nutzer',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E))),
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
            Icon(Icons.phone_iphone,
                size: 18, color: Color(0xFF1D4ED8)),
            SizedBox(width: 8),
            Text('Mobile Arbeit',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E3A8A))),
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
  static const blueBg = Color(0xFFEFF6FF);
  static const blueBorder = Color(0xFFBFDBFE);
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
