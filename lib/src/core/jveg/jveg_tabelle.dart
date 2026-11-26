// JVEG – Honorare der Sachverständigen (§ 9 JVEG, Anlage 1)
// Stand: Kosten- und Betreuervergütungsrechtsänderungsgesetz 2025 (KostBRÄG 2025),
// gültig für Aufträge ab 01.06.2025.
//
// Teil 1: Sachgebiete mit festem Stundensatz (z. B. 4.3 Bauwesen – Schadens-
// feststellung, -ursachenermittlung und -bewertung: 114 €/h).
// Teil 2: Honorargruppen M1–M3 nur für medizinische/psychologische Gutachten.
//
// Die Tabelle ist Gesetzesinhalt und kann bei Gesetzesänderungen hier
// zentral angepasst werden. Einzelne Sätze können in den Einstellungen
// überschrieben werden (siehe honorargruppe_service.dart).

/// Ein Sachgebiet aus Anlage 1 Teil 1 JVEG.
class JvegSachgebiet {
  const JvegSachgebiet(this.nr, this.bezeichnung, this.satz);
  final String nr;
  final String bezeichnung;
  final double satz;

  /// Code, wie er im Feld `honorargruppe` der Akte gespeichert wird.
  String get code => 'SG $nr';
  String get label => '$nr $bezeichnung';
}

/// Anlage 1 Teil 1 JVEG – Sachgebiete (Stand 01.06.2025).
const List<JvegSachgebiet> jvegSachgebiete = [
  JvegSachgebiet('1', 'Abfallstoffe einschließlich Altfahrzeuge und -geräte', 125.0),
  JvegSachgebiet('2', 'Akustik, Lärmschutz', 104.0),
  JvegSachgebiet('3', 'Altlasten und Bodenschutz', 93.0),
  JvegSachgebiet('4.1', 'Bauwesen – Planung', 114.0),
  JvegSachgebiet('4.2', 'Bauwesen – handwerklich-technische Ausführung', 104.0),
  JvegSachgebiet('4.3', 'Bauwesen - Schadensfeststellung, -Ursachenermittlung und -bewertung', 114.0),
  JvegSachgebiet('4.4', 'Bauwesen - Bauprodukte', 114.0),
  JvegSachgebiet('4.5', 'Bauwesen - Bauvertragswesen, Baubetrieb und Abrechnung von Bauleistungen', 114.0),
  JvegSachgebiet('4.6', 'Bauwesen - Geotechnik, Erd- und Grundbau', 109.0),
  JvegSachgebiet('5', 'Berufskunde und Tätigkeitsanalyse und Expositionsermittlung', 114.0),
  JvegSachgebiet('6.1', 'Betriebswirtschaft - Unternehmensbewertung, Betriebsunterbrechungs- und -verlagerungsschäden', 147.0),
  JvegSachgebiet('6.2', 'Betriebswirtschaft - Besteuerung', 120.0),
  JvegSachgebiet('6.3', 'Betriebswirtschaft - Rechnungswesen', 114.0),
  JvegSachgebiet('6.4', 'Betriebswirtschaft - Honorarabrechnungen von Steuerberatern', 114.0),
  JvegSachgebiet('7', 'Bewertung von Immobilien und Rechten an Immobilien', 125.0),
  JvegSachgebiet('8', 'Brandursachenermittlung', 120.0),
  JvegSachgebiet('9', 'Briefmarken, Medaillen und Münzen', 104.0),
  JvegSachgebiet('10', 'Einbauküchen', 98.0),
  JvegSachgebiet('11.1', 'Elektronik (insbesondere Mess-,Steuerungs- und Regelungselektronik)', 131.0),
  JvegSachgebiet('11.2', 'Elektrotechnische Anlagen und Geräte', 125.0),
  JvegSachgebiet('11.3', 'Kommunikations- und Informationstechnik', 125.0),
  JvegSachgebiet('11.4', 'Informatik', 136.0),
  JvegSachgebiet('11.5', 'Datenermittlung und -aufbereitung', 136.0),
  JvegSachgebiet('12', 'Emissionen und Immissionen', 104.0),
  JvegSachgebiet('13', 'Fahrzeugbau', 109.0),
  JvegSachgebiet('14', 'Garten- und Landschaftsbau einschließlich Sportanlagenbau', 98.0),
  JvegSachgebiet('15', 'Gesundheitshandwerk', 93.0),
  JvegSachgebiet('16', 'Grafische Gewerbe', 125.0),
  JvegSachgebiet('17', 'Handschriften- und Dokumentenuntersuchung', 114.0),
  JvegSachgebiet('18', 'Hausrat', 120.0),
  JvegSachgebiet('19', 'Honorarabrechnungen von Architekten und Ingenieuren und Stadtplanern', 158.0),
  JvegSachgebiet('20', 'Kältetechnik', 131.0),
  JvegSachgebiet('21.1', 'Kraftfahrzeugschäden und -bewertung', 131.0),
  JvegSachgebiet('21.2', 'Kfz-Elektronik', 104.0),
  JvegSachgebiet('22', 'Kunst und Antiquitäten', 93.0),
  JvegSachgebiet('23', 'Lebensmittelchemie und –technologie', 147.0),
  JvegSachgebiet('24.1', 'Photovoltaikanlagen', 120.0),
  JvegSachgebiet('24.2', 'Windkraftanlagen', 131.0),
  JvegSachgebiet('24.3', 'Solarthermieanlagen', 120.0),
  JvegSachgebiet('24.4', 'Maschinen und Anlagen im Übrigen', 142.0),
  JvegSachgebiet('25', 'Medizintechnik und Medizinprodukte', 114.0),
  JvegSachgebiet('26', 'Mieten und Pachten', 125.0),
  JvegSachgebiet('27', 'Möbel und Inneneinrichtung', 98.0),
  JvegSachgebiet('28', 'Musikinstrumente', 88.0),
  JvegSachgebiet('29', 'Schiffe, Wassersportfahrzeuge', 104.0),
  JvegSachgebiet('30', 'Schmuck, Juwelen, Perlen, Gold und Silberwaren', 93.0),
  JvegSachgebiet('31', 'Schweiß- und Fügetechnik', 104.0),
  JvegSachgebiet('32', 'Spedition, Transport, Lagerwirtschaft und Ladungssicherung', 98.0),
  JvegSachgebiet('33', 'Sprengtechnik', 98.0),
  JvegSachgebiet('34', 'Textilien, Leder und Pelze', 76.0),
  JvegSachgebiet('35', 'Tiere -Bewertung, Haltung, Tierschutz und Zucht', 93.0),
  JvegSachgebiet('36.1', 'Ursachenermittlung und Rekonstruktion von Unfällen im Freizeit- und Sportbereich', 104.0),
  JvegSachgebiet('36.2', 'Ursachenermittlung und Rekonstruktion von Unfällen bei Fahrzeugen, außer Luftfahrzeugen', 169.0),
  JvegSachgebiet('36.3', 'Ursachenermittlung und Rekonstruktion von Unfällen bei Arbeitsunfällen', 136.0),
  JvegSachgebiet('37', 'Verkehrsregelungs- und Überwachungstechnik', 147.0),
  JvegSachgebiet('38.1', 'Vermessungs- und Katasterwesen Vermessungstechnik', 87.0),
  JvegSachgebiet('38.2', 'Vermessungs- und Katasterwesen im Übrigen', 109.0),
  JvegSachgebiet('39', 'Waffen und Munition', 93.0),
  JvegSachgebiet('1000', 'Gutachter nach Mühewaltung', 50.0),
  JvegSachgebiet('', 'frei,kann überschrieben werden', 0.0),
  JvegSachgebiet('', 'frei,kann überschrieben werden', 0.0),
  JvegSachgebiet('', 'frei,kann überschrieben werden', 0.0),
  JvegSachgebiet('', 'frei,kann überschrieben werden', 0.0),
  JvegSachgebiet('', 'frei,kann überschrieben werden', 0.0),
  JvegSachgebiet('', 'frei,kann überschrieben werden', 0.0),
  JvegSachgebiet('', 'frei,kann überschrieben werden', 0.0),
  JvegSachgebiet('', 'frei,kann überschrieben werden', 0.0),
  JvegSachgebiet('', 'frei,kann überschrieben werden', 0.0),
];

/// Anlage 1 Teil 2 JVEG – Honorargruppen medizinischer/psychologischer
/// Gutachten (Stand 01.06.2025).
const Map<String, double> jvegMedizinischeGruppen = {
  'M1': 87.0,
  'M2': 98.0,
  'M3': 131.0,
};

/// Sucht ein Sachgebiet anhand seines Codes („SG 4.3“) oder der Nummer („4.3“).
JvegSachgebiet? jvegSachgebietFuer(String? codeOderNr) {
  final s = (codeOderNr ?? '').trim();
  if (s.isEmpty) return null;
  final nr = s.toUpperCase().startsWith('SG ') ? s.substring(3).trim() : s;
  for (final sg in jvegSachgebiete) {
    if (sg.nr == nr) return sg;
  }
  return null;
}

/// Gesetzlicher Stundensatz zu einem Honorargruppen-Code
/// („SG 4.3“, „M1“ …). `null`, wenn unbekannt (z. B. „Sonstige“).
double? jvegGesetzlicherSatz(String? code) {
  final c = (code ?? '').trim().toUpperCase();
  if (c.isEmpty) return null;
  if (jvegMedizinischeGruppen.containsKey(c)) return jvegMedizinischeGruppen[c];
  return jvegSachgebietFuer(code)?.satz;
}

/// Lesbare Bezeichnung eines Honorargruppen-Codes für Listen und PDFs.
String jvegCodeLabel(String? code) {
  final c = (code ?? '').trim();
  if (c.isEmpty) return '';
  final sg = jvegSachgebietFuer(c);
  if (sg != null) return 'Sachgebiet ${sg.label}';
  if (jvegMedizinischeGruppen.containsKey(c.toUpperCase())) {
    return 'Honorargruppe ${c.toUpperCase()}';
  }
  return c;
}

/// Abrechenbare Stunden nach § 8 Abs. 2 Satz 2 JVEG:
/// Die letzte bereits begonnene Stunde wird voll gerechnet, wenn sie zu mehr
/// als 30 Minuten erforderlich war, andernfalls zur Hälfte.
/// Die Rundung bezieht sich auf den GESAMTEN erforderlichen Zeitaufwand,
/// nicht auf einzelne Tätigkeiten.
double jvegAbrechenbareStunden(int minutenGesamt) {
  if (minutenGesamt <= 0) return 0;
  final h = minutenGesamt ~/ 60;
  final rest = minutenGesamt % 60;
  if (rest == 0) return h.toDouble();
  return rest > 30 ? (h + 1).toDouble() : h + 0.5;
}
