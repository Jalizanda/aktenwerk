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
      version: '0.18.1',
      datum: '2026-05-02',
      titel:
          'LV-Polish: KI-Langtext-Generator, echtes Drag-and-drop, Demo-Bietervergleich, Demo MwSt-Mix',
      changes: [
        _Change(_ChangeType.feature,
            'Position-Editor: Neuer „KI-Langtext"-Button neben dem '
            'Langtext-Feld. Generiert aus Kurztext + Gewerk + Einheit '
            'einen fachlich präzisen Standardleistungstext (3–6 Sätze, '
            'mit Norm-Bezug zu WTA/DIN/GAEB). Vorschau-Dialog vor der '
            'Übernahme — kein automatisches Überschreiben des '
            'bestehenden Textes.'),
        _Change(_ChangeType.feature,
            'Echtes Drag-and-drop in der Positions-Liste. Drag-Handle '
            'links neben jeder Zeile (Punkt-Raster-Symbol). Beim Drop '
            'wird der neue parent automatisch aus dem Vorgänger '
            'abgeleitet (Position rutscht unter den Titel des '
            'Vorgängers). Up/Down-Pfeile bleiben für die schnelle '
            'Reihenfolge-Korrektur.'),
        _Change(_ChangeType.design,
            'Demo-Mandant erweitert: zwei Bieter-Antworten zu AW-0001-'
            'Sanierung („Bauunternehmen Müller GmbH" und „Hilger Bau '
            'e. K.") mit unterschiedlichen Preisen — Bietergegenüberstellung '
            'sofort live testbar. Plus ein neues LV mit gemischten '
            'USt-Sätzen (Standardarbeiten 19 %, künstlerische Leistungen '
            'gem. § 12 Abs. 2 UStG mit 7 %) — Mischsumme im PDF.'),
      ],
    ),
    _Release(
      version: '0.18.0',
      datum: '2026-05-02',
      titel:
          'LV-Welle 3: GAEB-Import, Indizierung, Bietervergleich, CSV, Mischsummen, OZ-Auto, Reorder, 200er Standard-Katalog',
      changes: [
        _Change(_ChangeType.feature,
            'GAEB DA XML Import (Phasen X81 / X83 / X84). Architekt liefert '
            'XML, Aktenwerk parst Titel und Positionen mit Hierarchie und '
            'fügt sie ans LV an. Kompatibel mit ORCA AVA, California, '
            'BKI Kostenplaner, nextbau.'),
        _Change(_ChangeType.feature,
            'Indizierungs-Dialog: alle EP eines LV per Destatis-'
            'Baupreisindex auf einen neuen Stichtag hochrechnen — Ziel-'
            'Quartal aus Dropdown wählen, Faktor wird live angezeigt, '
            'mit einem Klick auf alle Positionen angewandt.'),
        _Change(_ChangeType.feature,
            'OZ-Auto-Numerierung: Button „OZ neu nummerieren" baut die '
            'Hierarchie korrekt durch (1, 1.1, 1.2, 2, 2.1 …).'),
        _Change(_ChangeType.feature,
            'Up/Down-Pfeile pro Position zum Sortieren innerhalb '
            'desselben Titels — schnelles Umsortieren ohne den '
            'Position-Editor zu öffnen.'),
        _Change(_ChangeType.feature,
            'Bietergegenüberstellung: aus dem Original-LV per Klick '
            'eine Bieter-Antwort klonen, der Bieter trägt eigene Preise '
            'ein. Vergleichs-Tabelle zeigt alle Bieter nebeneinander '
            'mit grüner/roter Markierung des günstigsten/teuersten.'),
        _Change(_ChangeType.feature,
            'CSV-Import/Export — UTF-8 mit BOM, Semikolon-getrennt '
            '(Excel-DE-kompatibel). Auto-Mapping der Spalten (OZ, Art, '
            'Kurztext, Langtext, Einheit, Menge, EP, DIN276, Gewerk).'),
        _Change(_ChangeType.feature,
            'Mehrwertsteuer pro Position: Dropdown im Position-Editor '
            '(LV-Standard, 19 %, 7 %, 0 %). Im PDF werden bei mehreren '
            'Sätzen Mischsummen separat ausgewiesen, sonst kompakt wie '
            'bisher.'),
        _Change(_ChangeType.feature,
            'Standard-Katalog mit 200 Sanierungs-Positionen aus 17 '
            'Gewerken (Erdarbeiten bis Baunebenkosten) mit '
            'Marktpreis-Indikatoren Stand 2024/2025. Per „Standard-'
            'Katalog importieren"-Button im Katalog-Screen einlesbar.'),
        _Change(_ChangeType.feature,
            'Destatis-API per Cloud-Function-Proxy: CORS-Workaround, '
            'damit der Browser-Client die GENESIS-Online-API erreichen '
            'kann. Credentials werden nicht mehr in der URL übertragen.'),
      ],
    ),
    _Release(
      version: '0.17.1',
      datum: '2026-05-02',
      titel:
          'LV-Welle 2: Aufmaß-Mengenermittlung, Gutachten-Integration, Destatis-Anbindung',
      changes: [
        _Change(_ChangeType.feature,
            'LV-Position-Dialog: Aufmaß-Panel mit Formelzeilen — '
            'Bezeichnung + Formel (`L*B*H`, Klammern, Komma als '
            'Dezimaltrenner). Live-Berechnung jeder Zeile, Summe oben, '
            'Button „In Menge übernehmen" setzt die Position-Menge '
            'automatisch auf die Aufmaß-Summe.'),
        _Change(_ChangeType.feature,
            'Gutachten-Editor: Neuer Button „LV-Positionen" pro '
            'Abschnitt. Öffnet den LV-Picker (Akten-LVs links, '
            'Positionen rechts mit Häkchen), Format wählbar '
            '(Tabellarisch / Aufzählung / Fließtext) mit oder ohne '
            'Preise. Fügt den fertigen Block ans Abschnitts-Feld an '
            '— inkl. Summe und „BP"-Markierung für Bedarfspositionen.'),
        _Change(_ChangeType.feature,
            'Einstellungen → „Baupreisindex (Destatis)": GENESIS-'
            'Online API-Anbindung. Username + Passwort eintragen, '
            '„Verbindung testen" zeigt den jüngsten Indexwert für '
            'Wohngebäude. Account ist bei www-genesis.destatis.de '
            'kostenfrei.'),
        _Change(_ChangeType.design,
            'Demo-Mandant: 9 Aufmaß-Zeilen für drei Beispiel-'
            'Positionen (KMB-Abdichtung mit Wand-Aufmaß und '
            'Lichtschacht-Abzug, Sanierputz mit Raumumfang, '
            'Schimmelpilzsanierung mit Tür-Abzügen).'),
      ],
    ),
    _Release(
      version: '0.17.0',
      datum: '2026-05-02',
      titel:
          'Leistungsverzeichnis-Modul: Kostenschätzung, Ausschreibung, GAEB-Export, eigener Katalog',
      changes: [
        _Change(_ChangeType.feature,
            'Neues Modul „LV / Ausschreibung" (Sidebar + Akten-Tab '
            '„LV / Kalkulation"). Vollwertiger Leistungsverzeichnis-'
            'Editor mit hierarchischer Gliederung (Titel → Hauptposition → '
            'Unterposition), 6 Positions-Arten (Normal, Bedarf, '
            'Eventual, Stundenlohn, Grundtext ohne Preis, Strukturtitel) '
            'und Live-Brutto-Summe in der Toolbar.'),
        _Change(_ChangeType.feature,
            'PDF-Druck in zwei Varianten: „Preis-LV" mit '
            'Einzelpreisen, Gesamtpreis und Summenblock '
            '(Kostenschätzung) und „Blanko-LV / Ausschreibung" '
            'ohne Preise — geht direkt an Handwerker zur '
            'Angebotsabgabe. Beide werden mit „Drucken & in Akte '
            'ablegen" automatisch unter Kategorie '
            '„Kostenschätzung (LV)" bzw. „Ausschreibung (Blanko-LV)" '
            'archiviert.'),
        _Change(_ChangeType.feature,
            'GAEB DA XML 3.2-Export (Phase X81 LV-Übergabe und X83 '
            'Ausschreibung) — Aktenwerk-LVs sind damit anschlussfähig '
            'an ORCA AVA, California, nextbau und alle gängigen '
            'Handwerker-Programme. Selbst implementiert mit dem '
            'package:xml — keine Lizenzkosten.'),
        _Change(_ChangeType.feature,
            'DIN-276:2018 Kostengruppen 1./2./3. Ebene als Asset-JSON '
            '(Wikipedia-Referenz, eigene Beschreibungen). Pro Position '
            'als Dropdown auswählbar — Auswertungen nach KG 300 '
            '(Baukonstruktionen) / KG 400 (TGA) etc. werden so möglich.'),
        _Change(_ChangeType.feature,
            'Eigener Positions-Katalog: Beim Anlegen einer Position '
            'mit „Position zusätzlich in den eigenen Katalog '
            'übernehmen" speichern, beim nächsten LV per Picker '
            '(Such-Dialog mit Häufigkeit-Sortierung) wieder einfügen. '
            'Lieferung mit 10 Seed-Positionen (Sanierputz, KMB-Abdichtung, '
            'XPS-Dämmung, Schimmelpilzsanierung, Lüftung mit WRG …).'),
        _Change(_ChangeType.feature,
            'Destatis Genesis-Online API-Anbindung für Baupreisindex '
            '(Tabelle 61261-0001 Wohngebäude). Kostenfreier Account '
            'in Einstellungen hinterlegen — historische LVs lassen '
            'sich auf aktuelles Preisniveau hochrechnen.'),
        _Change(_ChangeType.design,
            'Demo-Mandant: Zwei vollständige LVs (Sanierung Lindenweg '
            'mit 14 Positionen, Schimmel/Wärmeschutz mit '
            'Bedarfspositionen für den Ergänzungsbeschluss) sowie '
            '10 Katalog-Einträge mit fachlich korrekten WTA-/UBA-'
            'konformen Leistungstexten.'),
      ],
    ),
    _Release(
      version: '0.16.0',
      datum: '2026-05-02',
      titel:
          'Gmail-Integration (Phase 1) + Datenschutzerklärung',
      changes: [
        _Change(_ChangeType.feature,
            'Anschreiben-Editor: Neuer Button „Mit Gmail senden". '
            'Verbindet beim ersten Klick mit dem Google-Konto (Scope '
            '`gmail.send`), versendet das PDF mit angehängtem Brief direkt '
            'aus dem Browser. Die Mail erscheint in deinem Gmail-'
            '„Gesendet"-Ordner und wird parallel als Akten-Dokument '
            'archiviert. Auf Wunsch erweiterbar um den Lese-Scope für '
            'künftigen Auto-Import.'),
        _Change(_ChangeType.feature,
            'Einstellungen → Cloud → „Gmail": Gmail-Verbindung verwalten, '
            'Trennen, Berechtigungs-Status prüfen, optional Lese-Scope '
            'für Phase 2 hinzufügen.'),
        _Change(_ChangeType.feature,
            'Datenschutzerklärung gem. Art. 13/14 DSGVO unter '
            '/datenschutz. Erreichbar über Avatar-Menü → „Datenschutz". '
            'Beschreibt verarbeitete Daten, Speicherort (Frankfurt), '
            'eingesetzte Auftragsverarbeiter (Firebase, Vertex AI, '
            'Google APIs), Aufbewahrungsfristen und Betroffenenrechte. '
            'Vor Live-Verkauf rechtlich prüfen lassen!'),
        _Change(_ChangeType.design,
            'Hinweis: Die Gmail-Scopes sind bei Google als „sensitive" '
            'eingestuft. Solange Aktenwerk noch nicht durch den OAuth-'
            'Verifizierungsprozess gegangen ist, sehen externe Benutzer '
            'beim Verbinden einen „nicht verifiziert"-Hinweis. Das ist '
            'Standardverhalten und kein Sicherheitsproblem. Du als '
            'Domain-Inhaber kannst die App sofort nutzen.'),
      ],
    ),
    _Release(
      version: '0.15.0',
      datum: '2026-05-02',
      titel:
          'Anschreiben-Workflow: D-Belegnummer, Druck & Archivierung, Mailto-Versand, E-Mail-Ablage in der Akte',
      changes: [
        _Change(_ChangeType.feature,
            'Anschreiben-Editor: Neuer Button „Drucken & in Akte ablegen". '
            'Vergibt eine fortlaufende interne D-Nummer (Format '
            'D{YYYY}-{NNNN}) aus dem neuen Dokument-Nummernkreis, friert '
            'das Anschreiben ein (Status „versendet" + `gedrucktAm`), '
            'erzeugt das PDF und legt es als Akten-Dokument unter '
            'Kategorie „Anschreiben (Ausgang)" ab.'),
        _Change(_ChangeType.feature,
            'Anschreiben-Editor: Neuer „Mailen"-Button öffnet das '
            'Standard-Mailprogramm vorbefüllt mit Empfänger-Adresse, '
            'Betreff und Begleittext (inkl. Aktenzeichen, Anrede, '
            'Grußformel). Das PDF wird parallel in den Download-Ordner '
            'geladen und muss als Anhang manuell angefügt werden — '
            'browserseitig kann mailto: keine Anhänge übergeben.'),
        _Change(_ChangeType.feature,
            'Akten-Tab „Dokumente": Direkt-Upload mit vorausgewählter '
            'Akte. Im Upload-Dialog jetzt Schnell-Chips für gängige '
            'Kategorien („Eingangsmail", „Ausgangsmail", „Beweisbeschluss", '
            '„Schriftsatz", „Anschreiben (Eingang/Ausgang)" …). '
            '`.eml`/`.msg`-Dateien werden automatisch als „Eingangsmail" '
            'vorbelegt — du kannst Mails einfach aus dem Mailprogramm '
            'rausziehen und in den Upload-Dialog ziehen.'),
        _Change(_ChangeType.design,
            'Neuer Nummernkreis „Dokument" (Default `D{YYYY}-{NNNN}`) — '
            'unter Einstellungen → Nummernkreise konfigurierbar. '
            'Synchronisiert sich mit der höchsten vergebenen D-Nummer.'),
      ],
    ),
    _Release(
      version: '0.14.1',
      datum: '2026-05-01',
      titel:
          'Compliance-Cockpit + Beweisfragen-Bezug in Stellungnahme- und Kostenvorschuss-PDF',
      changes: [
        _Change(_ChangeType.feature,
            'Akten-Liste: Vier Compliance-Tiles über der Tabelle '
            '(„Befangenheit fehlt", „Kostenvorschuss offen", '
            '„Beweisfragen fehlen", „Frist überfällig"). Klick filtert '
            'die Liste auf Akten mit dem entsprechenden Mangel; '
            'nochmaliger Klick hebt den Filter auf. Tiles mit Mängeln '
            'sind orange hervorgehoben, „0 offen" bleibt grau.'),
        _Change(_ChangeType.feature,
            'Stellungnahme-PDF zeigt jetzt automatisch die Beweisfragen '
            'aus dem Beweisbeschluss als nummerierten Bezugsblock — '
            'hilft Richtern und Anwälten, die Antworten den ursprünglichen '
            'Beweisfragen zuzuordnen.'),
        _Change(_ChangeType.feature,
            'Kostenvorschuss-Antrag-PDF blendet die Beweisfragen '
            'ebenfalls als Bezugsblock ein. Das PDF läuft jetzt '
            'mehrseitig, falls nötig (mit Seitenzahl im Footer).'),
      ],
    ),
    _Release(
      version: '0.14.0',
      datum: '2026-05-01',
      titel:
          'Gerichts-Welle: Versand-Tracking, Befangenheits-Erklärung, Mehrkostenanzeige § 8a JVEG, strukturierte Beweisfragen',
      changes: [
        _Change(_ChangeType.feature,
            'Neuer Akten-Tab „Versand": Wer hat wann was bekommen — Post '
            '/ Einschreiben / EGVP / E-Mail / Kurier mit Tracking-Nr., '
            'Anzahl Ausfertigungen und Verknüpfung zum Akten-Dokument. '
            'Status: versendet / zugestellt / unzustellbar.'),
        _Change(_ChangeType.feature,
            'Neuer Akten-Tab „Gerichtssache" mit drei Blöcken: '
            'Befangenheits-Prüfung gem. §§ 406/407 ZPO, Mehrkostenanzeige '
            'gem. § 8a Abs. 4 JVEG und strukturierte Beweisfragen aus '
            'dem Beweisbeschluss.'),
        _Change(_ChangeType.feature,
            'Befangenheits-Erklärung: Datum + Ergebnis (unbefangen / '
            'befangen) + Erläuterung. „Drucken & in Akte ablegen" '
            'erzeugt das passende PDF (Erklärung zur Unbefangenheit '
            'oder Anzeige der Befangenheit) und legt es als Akten-'
            'Dokument unter Kategorie „Befangenheits-Erklärung" ab.'),
        _Change(_ChangeType.feature,
            'Mehrkostenanzeige § 8a Abs. 4 JVEG: Bisheriger und neuer '
            'Kostenrahmen, Mehrbedarf wird live berechnet, Begründung '
            'frei formulierbar. PDF mit Tabelle und Begründungs-Block; '
            'Archivierung in der Akte.'),
        _Change(_ChangeType.feature,
            'Beweisfragen: Strukturierte nummerierte Liste statt '
            'Freitext. Wird automatisch in Stellungnahmen und '
            'künftig in Gutachten als Bezugs-Block übernommen.'),
        _Change(_ChangeType.design,
            'Demo-Mandant: Beide Gerichtsakten haben jetzt komplette '
            'Befangenheits-Prüfung, AW-0004 zusätzlich eine '
            'Mehrkostenanzeige + 5 Versand-Einträge mit Tracking-Nrn.'),
      ],
    ),
    _Release(
      version: '0.13.0',
      datum: '2026-05-01',
      titel:
          'Akten-Welle: Nachfragen + Stellungnahme-PDF, Massen-Termin-Einladung, Kostenvorschuss-Antrag (§ 17 JVEG), Honorargruppen-Tabelle',
      changes: [
        _Change(_ChangeType.feature,
            'Neuer Akten-Tab „Nachfragen": Schriftsätze von Gericht / '
            'Anwalt / Versicherung mit beliebig vielen nummerierten Fragen '
            'erfassen, je Frage eine Stellungnahme verfassen. Bezug auf '
            'das Ursprungs-Gutachten (Datum + Nummer) bleibt erhalten.'),
        _Change(_ChangeType.feature,
            'Stellungnahme-PDF: Druckfertige „Ergänzende gutachterliche '
            'Stellungnahme" im Q&A-Layout (Frage hervorgehoben, '
            'Stellungnahme darunter), inkl. Bezugsblock zum Gutachten '
            'und Schriftsatz. Button „Drucken & in Akte ablegen" '
            'speichert das PDF unter Kategorie „Ergänzende Stellungnahme".'),
        _Change(_ChangeType.feature,
            'Beteiligte-Tab → „Termin-Einladung an alle": Massen-'
            'Anschreiben für Ortstermine. Termin, Ort und Hinweise einmal '
            'eingeben — pro Beteiligten wird ein Anschreiben mit '
            'passender Briefanrede angelegt.'),
        _Change(_ChangeType.feature,
            'Kostenvorschuss-Antrag (§ 17 JVEG): Dialog aus der '
            'Gerichts-Akte heraus. Honorar (auto. aus Honorargruppe), '
            'Auslagen (Fahrt, Schreibauslagen, Kopien, Lichtbilder, '
            'Porto, Sonstiges) und USt. Druck mit Vorschau oder direkt '
            '„Drucken & in Akte ablegen" — PDF wird unter Kategorie '
            '„Kostenvorschuss-Antrag" archiviert, Brutto-Betrag im '
            'Akten-Feld vermerkt.'),
        _Change(_ChangeType.feature,
            'Einstellungen → „JVEG-Honorargruppen (§ 9 JVEG)": M1, M2, '
            'M3 und Sonstige individuell konfigurierbar. Stunden-Editor '
            'und Kostenvorschuss-Dialog ziehen den Satz automatisch '
            'aus der Honorargruppe der Akte.'),
        _Change(_ChangeType.feature,
            'Auslagen-KPI-Kacheln pro Art (Fahrt, Schreibauslagen, '
            'Kopie s/w, Kopie farbig, Lichtbilder, Porto, '
            'Fremdleistung, Sonstiges) — Klick filtert die Liste auf '
            'die jeweilige Art, nochmaliger Klick hebt den Filter auf.'),
        _Change(_ChangeType.feature,
            'Sortierbare Spaltenköpfe in allen Listen (Auslagen, '
            'Stunden, Messgeräte, Textbausteine, Normen, Recherche).'),
        _Change(_ChangeType.feature,
            'Editor-Prefill aus der Akte: Aus jedem Akten-Tab '
            '(Rechnung, Angebot, AB, Anschreiben, Gutachten, Stunden, '
            'Auslagen, Erläuterung) öffnen die jeweiligen Editor-'
            'Dialoge bereits mit gesetztem Auftrag und Kontakt.'),
        _Change(_ChangeType.feature,
            'Auto-Akte: Beim Umwandeln eines eingefrorenen Dokuments '
            '(Angebot → AB → Rechnung) wird die zugehörige Akte '
            'automatisch übernommen oder neu angelegt.'),
        _Change(_ChangeType.design,
            'Aktenzeichen (AW-XXXX) ist jetzt sauber von den '
            'Belegnummern (RE/AB/AN/AZ-Akonto) getrennt — die Akte '
            'führt nur noch das AW-Az., die Belege ihre eigenen '
            'Nummernkreise.'),
        _Change(_ChangeType.feature,
            'Multi-Tenant Subscription-Modell: 14-Tage-Trial, danach '
            '7,90 €/Benutzer/Monat. Master-Mandant „Bauelemente-'
            'Experte" verwaltet alle Mandanten und sieht Trial-'
            'Restlaufzeiten je Benutzer.'),
      ],
    ),
    _Release(
      version: '0.12.0',
      datum: '2026-04-21',
      titel:
          'Rechnungs-Workflow: Akontoanforderung, Teil-/Schlussrechnung; Serienbrief-Historie; Abmelde-Button',
      changes: [
        _Change(_ChangeType.feature,
            'Neue Rechnungs-Typen „Akontoanforderung", '
            '„Teil-/Abschlagsrechnung" und „Schlussrechnung" mit den '
            'korrekten USt-Regeln: Akonto wird erst mit Zahlung USt-pflichtig '
            '(§13 Abs. 1 Nr. 1 b UStG), Teilrechnung sofort mit '
            'Rechnungsdatum. Info-Kachel im Editor erklärt die Regel.'),
        _Change(_ChangeType.feature,
            'Eigener Nummernkreis für Akontoanforderungen (Default: '
            'AZ{YYYY}-{NNN}) — unter Einstellungen → „Nummernkreise" '
            'individuell konfigurierbar.'),
        _Change(_ChangeType.feature,
            'Schlussrechnung-Editor: Übersicht der bezahlten Akonto- und '
            'aller Teilrechnungen dieser Akte. Button „Abzüge übernehmen" '
            'fügt sie als negative Positionen mit Rechnungsnummer, '
            'Rechnungsdatum und Zahlungsdatum ein (§14 Abs. 5 UStG).'),
        _Change(_ChangeType.feature,
            'Serienbrief-Historie: jeder versendete Serienbrief wird '
            'als Batch abgelegt (Datum, Betreff, Anzahl, '
            'Empfänger-IDs). Über „Historie" im Serienbrief-Modul lässt '
            'sich ein früherer Serienbrief kopieren und erneut versenden.'),
        _Change(_ChangeType.feature,
            'Top-Bar: Avatar-Menü mit Name/E-Mail und Abmelden-Button '
            '(zuvor nur in Einstellungen → Cloud).'),
        _Change(_ChangeType.feature,
            'Foto-Editor: Drehen 90° links/rechts, Zuschneiden-Modus '
            'mit Live-Rahmen, Monochrom-Filter.'),
        _Change(_ChangeType.fix,
            'CO₂-Tracker: Format-Bug behoben, Empty-State ergänzt.'),
        _Change(_ChangeType.design,
            'Nummernkreise setzen standardmäßig NICHT mehr automatisch '
            'zum Jahreswechsel auf 1 zurück — Aktenwerk behält den '
            'Zähler, bis du ihn bewusst manuell änderst. Das verhindert '
            'Nummern-Kollisionen bei Jahresübergang und bleibt GoBD-konform.'),
      ],
    ),
    _Release(
      version: '0.11.0',
      datum: '2026-04-21',
      titel:
          'Per-Mandant-Datenbanken, Backup/Restore, Auto-Mahnung, Cache-Fix',
      changes: [
        _Change(_ChangeType.feature,
            'Pro Mandant eine eigene lokale Datenbank (IndexedDB). '
            'Demo- und Produktiv-Daten sind physisch getrennt, Wechsel '
            'zwischen den Mandanten zeigt die richtigen Daten. '
            'Legacy-DB wird einmalig in den aktiven Mandanten migriert.'),
        _Change(_ChangeType.feature,
            'Einstellungen → „Backup & Wiederherstellung": JSON-Export '
            'aller 35 Tabellen der lokalen DB + JSON-Import mit '
            'vollständigem Überschreiben in einer Transaktion. '
            'Sicherheitsnetz vor Releases und Browser-Umzügen.'),
        _Change(_ChangeType.feature,
            'Auto-Trigger: beim Anlegen/Ändern einer Rechnung mit '
            'Fälligkeit entsteht automatisch eine Wiedervorlage '
            '„Mahnung prüfen" 14 Tage nach Fälligkeit.'),
        _Change(_ChangeType.feature,
            'Wiedervorlagen können wiederholt werden (täglich/wöchentlich/'
            'monatlich) und haben optional eine Checkliste. Der '
            'Terminkalender expandiert wiederkehrende Einträge.'),
        _Change(_ChangeType.feature,
            'Browser-Benachrichtigungen: für heute fällige und überfällige '
            'Wiedervorlagen erscheinen Browser-Pushes, solange Aktenwerk '
            'in einem Tab geöffnet ist.'),
        _Change(_ChangeType.fix,
            'PDF-Fußzeile: Kontoinhaber-Zeile entfernt. Bank/IBAN/BIC '
            'bleiben in der vierten Spalte am unteren Seitenrand.'),
        _Change(_ChangeType.fix,
            'Demo-Auto-Reseed: läuft nur noch einmal pro Browser/Mandant '
            'und nie im Produktiv-Mandanten. Das schützt echte Kunden-Daten '
            'vor versehentlichem Überschreiben.'),
        _Change(_ChangeType.fix,
            'Graue Seite nach Deploy: selfHeal lädt die Seite jetzt einmal '
            'per Session automatisch neu, sobald alte Service-Worker '
            'entfernt wurden. Manuelles Cache-Löschen nicht mehr nötig.'),
      ],
    ),
    _Release(
      version: '0.10.0',
      datum: '2026-04-21',
      titel:
          'Sachverständigen-Features: ImmoWertV, Messwerte, Bauteilöffnungen, Mängel',
      changes: [
        _Change(_ChangeType.feature,
            'Akten-Tab „Wertermittlung": ImmoWertV-Rechner mit Bodenwert, '
            'Sachwert, Alterswertminderung, Marktanpassung, Vergleichswert '
            'und Verkehrswert. Ergebnisse werden live berechnet.'),
        _Change(_ChangeType.feature,
            'Akten-Tab „Messwerte": Logger für Temperatur, Feuchte, Schall, '
            'BlowerDoor — mit Zeitverlaufs-Chart (fl_chart) und CSV-Export.'),
        _Change(_ChangeType.feature,
            'Akten-Tab „Bauteilöffnung": Dokumentation mit Lage, Methode, '
            'Befund und Foto vor/nach der Öffnung.'),
        _Change(_ChangeType.feature,
            'Akten-Tab „Mängel": Mängel-Register nach DIN 4426 mit '
            'Priorität A/B/C, Bauteil, Ursache, Folge, geschätztem Aufwand '
            'und Kennzahl-Summen je Priorität.'),
        _Change(_ChangeType.feature,
            'Akten-Tab „Journal": chronologisches Projekt-Tagebuch für '
            'Telefonate, Mails, Ortstermine, Rückfragen.'),
        _Change(_ChangeType.feature,
            'Akten-Tab „Übergabe": Aktenübergabe-Protokoll an Kollegen '
            'mit Datum, Umfang und Unterlagenliste.'),
        _Change(_ChangeType.feature,
            'Akten-Übersicht: neue Benchmark-Kachel — vergleicht Stunden, '
            'Netto-Honorar und Bearbeitungsdauer mit anderen Akten im '
            'gleichen Sachgebiet.'),
        _Change(_ChangeType.feature,
            'Werkzeug-Modul „Qualifikationen": zentrale Ablage von Diplomen '
            'und Zertifikaten mit Ablaufdatum-Ampel, PDF-Upload und '
            'Standard-Anhang-Flag fürs Gutachten.'),
        _Change(_ChangeType.feature,
            'Auswertung „CO₂-Tracker": Klimabilanz aus Fahrt-Kilometern und '
            'Druckkopien, KPI-Kacheln und Jahres-Auswertung.'),
      ],
    ),
    _Release(
      version: '0.9.0',
      datum: '2026-04-20',
      titel: 'Google-Kalender-Sync, Layout-Feinschliff, Tab-Navigation',
      changes: [
        _Change(_ChangeType.feature,
            'Google-Kalender-Sync: Ortstermine, Fristen, Erläuterungs-'
            'Termine und Wiedervorlagen werden in einen ausgewählten '
            'Kalender gespiegelt. Auto-Sync bei Änderungen und App-Start.'),
        _Change(_ChangeType.feature,
            'Akten-Übersicht: 3-Spalten-Layout — Stammdaten · Objekt/Lage · '
            'Finanzen. Objekt-Luftbild kompakter zwischen den beiden '
            'Kacheln.'),
        _Change(_ChangeType.feature,
            'Akten-Tabs: Klick auf Stunden/Auslagen/Rechnungen/Angebote/'
            'Gutachten/Dokumente/Erläuterungen-Einträge öffnet direkt '
            'den Editor-Dialog (statt Navigation zum Modul).'),
        _Change(_ChangeType.feature,
            'Fotos-Modul gruppiert nach Akte, je Gruppe Kopfzeile mit '
            'Aktenzeichen und Link zur Akte.'),
        _Change(_ChangeType.feature,
            'Anschreiben: Vorlagen-Picker mit Platzhalter-Ersetzung '
            '({{aktenzeichen}}, {{gericht}}, {{heute}} etc.) und '
            'neuer Vorlage „Mitteilung – Fristüberschreitung Gutachten".'),
        _Change(_ChangeType.fix,
            'Anschreiben-Editor: als Modal-Overlay statt Vollbildwechsel.'),
        _Change(_ChangeType.fix,
            'Serienbrief-Layout: Felder schmaler (max 820px), grau '
            'umrandete Card für besseren Kontrast.'),
      ],
    ),
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
