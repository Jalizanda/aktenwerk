import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// 21 Vorlagen für Sachverständige Bau Deutschland — nach ZPO, JVEG, BGB,
/// DSGVO. Quelle: SV-Vorlagenset Deutschland (Stand 07/2025), angelehnt
/// an Empfehlungen Akademie Schloss Raesfeld.
///
/// Platzhalter im Aktenwerk-Format `{{name}}`. Beim Einfügen werden die
/// Stammdaten-Platzhalter (z. B. `{{aktenzeichen}}`, `{{heute}}`)
/// automatisch aus Auftrag + Kunde befüllt; die SV-spezifischen
/// Platzhalter (`{{name_sv}}`, `{{anschrift_sv}}` etc.) kann der Nutzer
/// später auf Stammdaten binden oder direkt überschreiben.
class SvVorlageEintrag {
  const SvVorlageEintrag({
    required this.id,
    required this.titel,
    required this.kategorie,
    this.sachgebiet,
    required this.inhalt,
    this.favorit = false,
  });
  final String id;
  final String titel;
  final String kategorie;
  final String? sachgebiet;
  final String inhalt;
  final bool favorit;
}

const svVorlagen = <SvVorlageEintrag>[
  // ---------------- 100er Gerichtsgutachten – Verfahren ----------------
  SvVorlageEintrag(
    id: 'GA_100',
    titel: 'GA 100 — Protokoll Gerichtsgutachten (intern)',
    kategorie: 'anschreiben',
    sachgebiet: '100 Gerichtsgutachten · Verfahren',
    inhalt: '''Protokoll Gerichtsgutachten — intern

Aktenzeichen Gericht: {{aktenzeichen}}
Gericht / Kammer: {{gericht}}
Vorsitzender Richter / Berichterstatter: {{richter}}
Beweisbeschluss vom: {{beweisbeschluss_datum}}
Eingang Beschluss / Akten bei SV: {{akteneingang}}
Frist zur Gutachtenerstattung: {{gutachten_frist}}
Gegenstandswert / Streitwert: {{streitwert}}
Auslagenvorschuss angefordert / eingezahlt: {{vorschuss}}
Beweisthema (Kurzfassung): {{beweisthema}}

Parteien und Verfahrensbeteiligte
- Kläger / Antragsteller: {{klaeger}}
- Prozessbevollmächtigter Kläger: {{pb_klaeger}}
- Beklagter / Antragsgegner: {{beklagter}}
- Prozessbevollmächtigter Beklagter: {{pb_beklagter}}
- Streitverkündeter / Nebenintervenient: {{nebenintervenient}}
- Objektanschrift / Bauvorhaben: {{objektadresse}}

Tätigkeitsprotokoll (§ 12 JVEG — Grundlage für Zeitaufwand)
| Datum | Tätigkeit | Zeit von–bis | Dauer (Std.) | Bemerkung |
|-------|-----------|--------------|--------------|-----------|
|       |           |              |              |           |

Kontaktprotokoll
| Datum | Mit / Von | Kanal | Inhalt / Ergebnis |
|-------|-----------|-------|-------------------|
|       |           |       |                   |

Fristen und Meilensteine
- Akteneingang: {{akteneingang}}
- Eingangsbestätigung an Gericht: …
- Rückmeldung 2 Wochen nach Akteneingang: …
- Ortstermin durchgeführt: …
- Gutachtenentwurf abgeschlossen: …
- Gutachten an Gericht versandt: …
- Rechnung / Vergütungsantrag eingereicht: …

Reflexion / QS:
☐ Beweisfragen vollständig beantwortet (keine rechtliche Beurteilung)?
☐ Alle Parteien am Ortstermin beteiligt bzw. ordnungsgemäß geladen?
☐ Rechtliches Gehör zu neuen Tatsachen gewahrt?
☐ Nachprüfbarkeit (Methoden, Quellen, Berechnungen) gegeben?
☐ Anerkannte Regeln der Technik / DIN-Normen korrekt zitiert?
☐ Keine Grenzüberschreitung Technik → Recht?
☐ Höchstpersönliche Gutachtenerstattung gewahrt (§ 407a Abs. 3 ZPO)?
☐ § 407a Abs. 4 ZPO — Kostenprognose im Blick / Hinweis rechtzeitig?

Internes Arbeitsdokument — nicht zur Einreichung bei Gericht.''',
  ),

  SvVorlageEintrag(
    id: 'GA_100a',
    titel: 'GA 100a — Mitteilung Fristüberschreitung (§ 411 ZPO)',
    kategorie: 'anschreiben',
    sachgebiet: '100 Gerichtsgutachten · Verfahren',
    inhalt: '''An: {{gericht}}
Aktenzeichen: {{aktenzeichen}}
In Sachen: {{parteien}}
Datum: {{heute}}

Sehr geehrte Damen und Herren,

in der oben bezeichneten Sache ist die mir gesetzte Frist zur Erstattung des Gutachtens bis {{gutachten_frist}} voraussichtlich nicht einzuhalten. Ich zeige dies gemäß § 411 Abs. 1 ZPO rechtzeitig an.

Gründe der Verzögerung
- [unvollständige Akten / nachzureichende Unterlagen durch Parteien]
- [unerwarteter Umfang der Befundaufnahme / mehrere Ortstermine erforderlich]
- [erforderliche Zusatzuntersuchungen / Laborbefunde / Bauteilöffnungen]
- [krankheitsbedingte Verhinderung / unaufschiebbare Parallelverfahren]
- [sonstige Gründe]

Aktueller Arbeitsstand
- Aktenstudium: …
- Ortstermin: …
- Nachgeforderte Unterlagen: …
- Gutachtenentwurf: Fertigstellungsgrad ca. xx %

Ich bitte das Gericht, die Frist bis zum {{neue_frist}} zu verlängern.

Mit freundlichen Grüßen

{{name_sv}}
(Allgemein beeidete(r) und gerichtlich zertifizierte(r) Sachverständige(r))''',
  ),

  SvVorlageEintrag(
    id: 'GA_100b',
    titel: 'GA 100b — Ersuchen um Fristverlängerung',
    kategorie: 'anschreiben',
    sachgebiet: '100 Gerichtsgutachten · Verfahren',
    inhalt: '''An: {{gericht}}
Aktenzeichen: {{aktenzeichen}}
In Sachen: {{parteien}}
Datum: {{heute}}

Sehr geehrte Damen und Herren,

hiermit beantrage ich die Verlängerung der Frist zur Erstattung des Gutachtens bis zum {{neue_frist}}.

Begründung
1. [Grund 1 — z. B. nachzureichende Unterlagen der Parteien]
2. [Grund 2 — z. B. zusätzliche Bauteilöffnung erforderlich]
3. [Grund 3 — z. B. Laborbefund steht aus]
4. [ggf. weiterer Grund]

Die Verzögerung beruht nicht auf einem von mir zu vertretenden Umstand. Ich werde das Gutachten unverzüglich nach Eintritt der genannten Voraussetzungen fertigstellen.

Mit freundlichen Grüßen

{{name_sv}}''',
  ),

  SvVorlageEintrag(
    id: 'GA_101',
    titel: 'GA 101 — Einladung zum Ortstermin',
    kategorie: 'anschreiben',
    sachgebiet: '100 Gerichtsgutachten · Verfahren',
    inhalt: '''An: {{empfaenger}}
Aktenzeichen: {{aktenzeichen}}
In Sachen: {{parteien}}
Datum: {{heute}}

Sehr geehrte Damen und Herren,

in der obigen Sache lade ich Sie zu einem Ortstermin zur Inaugenscheinnahme ein.

Termin und Ort
- Datum / Uhrzeit: {{ortstermin_datum}}
- Ort / Anschrift: {{objektadresse}}
- Voraussichtliche Dauer: {{dauer}}
- Alternativtermin: {{alternativtermin}}

Eingeladene Personen
- Kläger / Antragsteller persönlich
- Prozessbevollmächtigter des Klägers
- Beklagter / Antragsgegner persönlich
- Prozessbevollmächtigter des Beklagten
- Streitverkündeter / Nebenintervenient (falls vorhanden)

Mitzubringende Unterlagen
- Originale der Baubeschreibung / des Leistungsverzeichnisses
- Pläne (Grundrisse, Schnitte, Ansichten, Details)
- Bautagebuch / Schriftverkehr / Mängelanzeigen
- Abnahmeprotokoll / Verträge
- Ggf. bereits vorliegende Privatgutachten oder Kostenvoranschläge

Organisatorisches
- Der Ortstermin dient ausschließlich der Inaugenscheinnahme und Befundaufnahme — nicht der Erörterung von Rechtsfragen.
- Zutritt zu allen beweiserheblichen Räumen und Bauteilen ist sicherzustellen.
- Bauteilöffnungen nur mit Zustimmung aller Parteien oder nach ausdrücklicher gerichtlicher Anordnung.
- Fotodokumentation ist vorgesehen.
- Absagen / Terminverlegungen bitte spätestens 3 Werktage vorher schriftlich anzeigen.

Mit freundlichen Grüßen

{{name_sv}}
(Allgemein beeidete(r) und gerichtlich zertifizierte(r) Sachverständige(r))''',
  ),

  SvVorlageEintrag(
    id: 'GA_102',
    titel: 'GA 102 — Checkliste Ortstermin',
    kategorie: 'ortstermin',
    sachgebiet: '100 Gerichtsgutachten · Verfahren',
    inhalt: '''Checkliste Ortstermin

Aktenzeichen: {{aktenzeichen}}
Datum / Uhrzeit Beginn: {{ortstermin_datum}}
Ort / Objektanschrift: {{objektadresse}}
Wetter / Umgebungsbedingungen: …
Uhrzeit Ende: …
Dauer gesamt: …

Anwesende Personen
| Name | Funktion / Partei | Kontakt | Unterschrift |
|------|-------------------|---------|--------------|
|      |                   |         |              |

Auftrag / Beweisfragen zur Inaugenscheinnahme
1. …
2. …
3. …

Ablauf und Feststellungen
| Zeit | Bereich / Bauteil | Feststellung / Messung | Foto-Nr. |
|------|-------------------|-----------------------|----------|
|      |                   |                       |          |

Mess- und Prüfmittel / Methoden
☐ Zollstock / Lasermessgerät kalibriert
☐ Feuchtemessgerät (CM-Messung / elektrisch) kalibriert
☐ Thermohygrometer
☐ Endoskop / Kamera-Sonde
☐ Thermografiekamera
☐ Wasserwaage / Nivelliergerät
☐ Sonstiges: …

Wortmeldungen der Parteien (keine Rechtsausführungen protokollieren)
| Zeit | Person / Partei | Wortmeldung (sinngemäß) |
|------|-----------------|-------------------------|
|      |                 |                         |

Bauteilöffnungen / zerstörende Prüfungen
☐ Bauteilöffnung vorgenommen — Ort, Umfang, Zustimmung dokumentiert
☐ Zustimmung aller anwesenden Parteien liegt vor
☐ Anordnung des Gerichts liegt vor (falls ohne Zustimmung)
☐ Wiederherstellung nach Befundaufnahme vereinbart / durchgeführt
☐ Keine Bauteilöffnung erforderlich

Kostenüberblick
- Zeitaufwand Ortstermin inkl. An-/Abreise: …
- Fahrtkosten: …
- Hilfskräfte / Fremdleistungen: …
- Verbrauchte Stoffe / zerstörende Prüfung: …

Abschluss
☐ Protokoll vorgelesen / ausgehändigt
☐ Teilnehmer hatten Gelegenheit zu Anmerkungen
☐ Offene Punkte / Nachforderungen notiert
☐ Nächster Schritt vereinbart''',
  ),

  SvVorlageEintrag(
    id: 'GA_103',
    titel: 'GA 103 — Beilagenverzeichnis',
    kategorie: 'anschreiben',
    sachgebiet: '100 Gerichtsgutachten · Verfahren',
    inhalt: '''Beilagenverzeichnis zum Gutachten

Aktenzeichen: {{aktenzeichen}}
In Sachen: {{parteien}}
Sachverständiger: {{name_sv}}
Datum: {{heute}}

| Anlage Nr. | Art | Bezeichnung | Datum | Seiten | Herkunft |
|------------|-----|-------------|-------|--------|----------|
| A01        |     |             |       |        |          |
| A02        |     |             |       |        |          |
| A03        |     |             |       |        |          |
| A04        |     |             |       |        |          |
| A05        |     |             |       |        |          |

Legende zur Art
- A — Foto / Bildanlage
- P — Plan / Zeichnung
- B — Berechnung / Ermittlung
- S — Schriftstück / Urkunde
- M — Messprotokoll / Laborbefund
- G — Gutachten Dritter

Hinweis: Fotos fortlaufend nummerieren, mit Datum / Uhrzeit / Standort (EXIF).
Urheberrechtlich geschützte Pläne und DIN-Normen nur auszugsweise und mit Quellenangabe.''',
  ),

  SvVorlageEintrag(
    id: 'GA_104',
    titel: 'GA 104 — Eingangsbestätigung Gerichtsauftrag',
    kategorie: 'anschreiben',
    sachgebiet: '100 Gerichtsgutachten · Verfahren',
    inhalt: '''An: {{gericht}}
Aktenzeichen: {{aktenzeichen}}
In Sachen: {{parteien}}
Datum: {{heute}}

Sehr geehrte Damen und Herren,

hiermit bestätige ich den Eingang des Beweisbeschlusses vom {{beweisbeschluss_datum}} sowie der beigefügten Akten am {{akteneingang}}.

Erste Einschätzung
- Geschätzter Zeitaufwand: {{geschaetzter_aufwand}}
- Voraussichtliche Honorargruppe (JVEG Anlage 1): {{honorargruppe}}
- Voraussichtlicher Gesamtbetrag (brutto): {{gesamt_brutto}}
- Voraussichtlicher Termin Gutachtenerstattung: {{voraussichtl_abgabe}}
- Erforderliche weitere Unterlagen: {{fehlende_unterlagen}}

Ich werde unverzüglich mit dem Aktenstudium beginnen und mich innerhalb von zwei Wochen mit einer fachlichen Zwischenmitteilung melden.

Mit freundlichen Grüßen

{{name_sv}}''',
  ),

  SvVorlageEintrag(
    id: 'GA_105',
    titel: 'GA 105 — Zwischenbericht nach Aktenstudium',
    kategorie: 'anschreiben',
    sachgebiet: '100 Gerichtsgutachten · Verfahren',
    inhalt: '''An: {{gericht}}
Aktenzeichen: {{aktenzeichen}}
In Sachen: {{parteien}}
Datum: {{heute}}

Sehr geehrte Damen und Herren,

ich habe das Aktenstudium in der obigen Sache abgeschlossen und möchte gemäß § 407a ZPO zu folgenden Punkten frühzeitig Rückmeldung geben.

Verständnis der Beweisfragen
{{beweisfragen_verstaendnis}}

Nachzureichende Unterlagen
1. [Unterlage 1 — Quelle (Kläger/Beklagter/Gericht)]
2. [Unterlage 2]
3. [Unterlage 3]

Vorgesehener Ortstermin
- Voraussichtliches Datum: {{ortstermin_datum}}
- Voraussichtlicher Ort: {{objektadresse}}
- Voraussichtliche Dauer: {{dauer}}
- Voraussichtliche Teilnehmer: {{teilnehmer}}

Aktualisierte Kostenprognose
- Voraussichtlicher Zeitaufwand: {{geschaetzter_aufwand}}
- Voraussichtliche Auslagen: {{auslagen}}
- Voraussichtlicher Gesamtbetrag (brutto): {{gesamt_brutto}}
- Erhaltener Auslagenvorschuss: {{vorschuss}}

Mit freundlichen Grüßen

{{name_sv}}''',
  ),

  SvVorlageEintrag(
    id: 'GA_106',
    titel: 'GA 106 — Anzeige Besorgnis der Befangenheit (§ 406 ZPO)',
    kategorie: 'anschreiben',
    sachgebiet: '100 Gerichtsgutachten · Verfahren',
    inhalt: '''An: {{gericht}}
Aktenzeichen: {{aktenzeichen}}
In Sachen: {{parteien}}
Datum: {{heute}}

Sehr geehrte Damen und Herren,

gemäß § 407a Abs. 2 ZPO zeige ich dem Gericht unverzüglich und von mir aus einen Umstand an, der die Besorgnis der Befangenheit begründen kann.

Sachverhalt
{{sachverhalt_befangenheit}}

Konkreter Bezug
- Verwandtschaft / Schwägerschaft / persönliche Beziehung zu einer Partei oder einem Prozessbevollmächtigten: …
- Wirtschaftliche Beziehung / Geschäftsbeziehung (auch in der Vergangenheit): …
- Vorbefassung mit der Sache oder einer Partei: …
- Sonstiger Umstand: …

Eigene Einschätzung
{{einschaetzung_sv}}

Ich bitte das Gericht, über die weitere Vorgehensweise zu entscheiden.

Mit freundlichen Grüßen

{{name_sv}}''',
  ),

  SvVorlageEintrag(
    id: 'GA_107',
    titel: 'GA 107 — Gutachtenverweigerung / Ablehnung (§ 407a ZPO)',
    kategorie: 'anschreiben',
    sachgebiet: '100 Gerichtsgutachten · Verfahren',
    inhalt: '''An: {{gericht}}
Aktenzeichen: {{aktenzeichen}}
In Sachen: {{parteien}}
Datum: {{heute}}

Sehr geehrte Damen und Herren,

nach Prüfung des Beweisbeschlusses sehe ich mich außerstande, den Gutachtenauftrag zu übernehmen, und bitte das Gericht, einen anderen Sachverständigen zu bestellen.

Grund der Ablehnung
☐ Fehlende Sachkunde (§ 407a Abs. 1 ZPO) — der Auftrag liegt nicht in meinem Bestellungsgebiet bzw. erfordert Spezialkenntnisse, über die ich nicht verfüge.
☐ Zeugnisverweigerungsrecht / Gutachtenverweigerungsrecht (§ 408 ZPO, §§ 383–385 ZPO)
☐ Gravierende Arbeitsüberlastung / konkrete Terminkollision — Bearbeitung innerhalb angemessener Frist nicht möglich
☐ Mehrere Auftraggeber in gleicher Sache — Privatgutachten-Mandat für eine Partei bereits aktiv
☐ Sonstiger Grund

Konkrete Begründung
{{begruendung_ablehnung}}

Empfehlung zum weiteren Vorgehen
- Ggf. Benennung eines kompetenten Kollegen mit entsprechender Bestellung
- Ggf. Einholung eines Obergutachtens oder Zusatzgutachtens
- Die Akten sende ich mit gleicher Post / per beA an das Gericht zurück.

Mit freundlichen Grüßen

{{name_sv}}''',
  ),

  // ---------------- 110er JVEG & Hinweispflicht ----------------
  SvVorlageEintrag(
    id: 'GA_110',
    titel: 'GA 110 — Antrag auf Auslagenvorschuss (§ 3 JVEG)',
    kategorie: 'anschreiben',
    sachgebiet: '110 JVEG & Hinweispflicht',
    inhalt: '''An: {{gericht}}
Aktenzeichen: {{aktenzeichen}}
In Sachen: {{parteien}}
Datum: {{heute}}

Sehr geehrte Damen und Herren,

gemäß § 3 JVEG beantrage ich die Festsetzung und Auszahlung eines Auslagenvorschusses.

Geschätzter Zeitaufwand
| Tätigkeit | Std. | Satz (EUR) | Summe (EUR) |
|-----------|------|------------|-------------|
| Aktenstudium |    |         |           |
| Ortstermin inkl. An-/Abreise |    |         |           |
| Recherche / Berechnungen / Messauswertung |    |         |           |
| Gutachtenabfassung |    |         |           |
| **Summe Honorar (netto)** |    |         |           |

Geschätzte Auslagen (§§ 5, 6, 7, 12 JVEG)
- Fahrtkosten § 5 JVEG (km × 0,42 EUR) / Fahrscheine: …
- Tagegeld / Übernachtungsgeld § 6 JVEG: …
- Besondere Kosten § 12 JVEG (Bauteilöffnung, Labor, Fotos): …
- Sonstige Aufwendungen § 7 JVEG (Post, Kopien, Telekommunikation): …
- **Summe Auslagen (netto)**: …
- Umsatzsteuer (§ 12 Abs. 1 Nr. 4 JVEG — 19 %): …
- **Gesamtsumme brutto (beantragter Vorschuss)**: {{vorschuss}}

Bankverbindung
- Kontoinhaber: {{name_sv}}
- IBAN: {{iban}}
- BIC: {{bic}}
- Bank: {{bank}}
- Verwendungszweck: {{aktenzeichen}} — SV {{name_sv}}

Mit freundlichen Grüßen

{{name_sv}}''',
  ),

  SvVorlageEintrag(
    id: 'GA_111',
    titel: 'GA 111 — Vergütungsantrag Gerichtsgutachten (§§ 8, 12 JVEG)',
    kategorie: 'anschreiben',
    sachgebiet: '110 JVEG & Hinweispflicht',
    inhalt: '''An: {{gericht}} (Kostenbeamter / Rechtspfleger)
Aktenzeichen: {{aktenzeichen}}
In Sachen: {{parteien}}
Rechnungsnummer: {{rechnungsnummer}}
Rechnungsdatum: {{heute}}
Gutachtenerstattung am: {{gutachten_abgabe}}
Tag der letzten Leistung: {{tag_letzte_leistung}}

Sehr geehrte Damen und Herren,

für die von mir erstattete Gutachtenerstattung mache ich folgende Vergütung geltend:

A) Honorar — erforderlicher Zeitaufwand (§ 8 JVEG)
| Tätigkeit | Zeitraum | Std. | Satz (EUR) | Summe (EUR) |
|-----------|----------|------|------------|-------------|
| Aktenstudium |        |      |            |             |
| Ortstermin inkl. Reisezeit |        |      |            |             |
| Messungen / Auswertungen / Berechnungen |        |      |            |             |
| Gutachtenabfassung |        |      |            |             |
| **Zwischensumme Honorar** |        |      |            |             |

B) Fahrtkosten (§ 5 JVEG)
- Privates Kraftfahrzeug: xx km × 0,42 EUR = … EUR
- Öffentliche Verkehrsmittel / Taxi: …
- Zwischensumme Fahrtkosten: …

C) Tagegeld / Übernachtung (§ 6 JVEG)
- Tagegeld: …
- Übernachtungsgeld: …
- Zwischensumme: …

D) Besondere Kosten (§ 12 JVEG)
- Bauteilöffnung / Dritte / Labor: …
- Fotos: …
- Messmittelmiete / Verbrauchsstoffe: …
- Schreibauslagen: …
- Zwischensumme § 12 JVEG: …

E) Sonstige Aufwendungen (§ 7 JVEG)
- Post / Telekommunikation: …
- Kopien / Ausdrucke: …
- Zwischensumme § 7 JVEG: …

Gesamt
- Summe A bis E (netto): …
- Umsatzsteuer 19 %: …
- **Gesamtbetrag brutto**: …
- abzüglich bereits erhaltener Vorschuss: …
- **Restzahlungsbetrag**: …

Bankverbindung
- Kontoinhaber: {{name_sv}}
- IBAN: {{iban}}
- BIC: {{bic}}
- Verwendungszweck: {{aktenzeichen}} — {{rechnungsnummer}}

Ich versichere die Richtigkeit und Vollständigkeit der Angaben.

Mit freundlichen Grüßen

{{name_sv}}''',
    favorit: true,
  ),

  SvVorlageEintrag(
    id: 'GA_113',
    titel: 'GA 113 — Hinweis § 407a Abs. 4 ZPO (Kostenüberschreitung)',
    kategorie: 'anschreiben',
    sachgebiet: '110 JVEG & Hinweispflicht',
    favorit: true,
    inhalt: '''An: {{gericht}}
Aktenzeichen: {{aktenzeichen}}
In Sachen: {{parteien}}
Datum: {{heute}}

Sehr geehrte Damen und Herren,

ich weise das Gericht gemäß § 407a Abs. 4 S. 2 ZPO ausdrücklich und rechtzeitig darauf hin, dass die voraussichtlich entstehenden Kosten die bisherige Prognose bzw. den angeforderten Kostenvorschuss erheblich überschreiten werden.

Prognose der Gesamtkosten
- Bisher entstandener Aufwand: {{bisheriger_aufwand}}
- Bisher entstandene Auslagen: {{bisherige_auslagen}}
- Voraussichtlicher weiterer Aufwand: {{weiterer_aufwand}}
- Voraussichtliche weitere Auslagen: {{weitere_auslagen}}
- **Voraussichtliche Gesamtkosten (brutto)**: {{gesamt_prognose}}

Bezugsgrößen
- Erhaltener Auslagenvorschuss: {{vorschuss}}
- Streitwert / Gegenstandswert: {{streitwert}}
- Voraussichtliche Überschreitung des Vorschusses / der ursprünglichen Prognose: {{ueberschreitung}}

Gründe der Überschreitung
- [unerwartet großer Umfang der Befundaufnahme / weitere Ortstermine]
- [zusätzliche zerstörende Prüfung / Laborbefunde erforderlich]
- [nachträgliche Erweiterung der Beweisfragen durch Gericht]
- [nachgereichte, umfangreiche Unterlagen der Parteien]
- [sonstige Gründe]

Ich bitte das Gericht um Entscheidung, ob
- die Gutachtenerstattung im bisherigen Umfang fortgeführt werden soll,
- ein ergänzender Vorschuss durch die Parteien einzufordern ist (§ 3 JVEG),
- der Beweisbeschluss eingegrenzt werden soll oder
- eine andere Verfahrensweise gewünscht wird.

Bis zu einer Entscheidung des Gerichts stelle ich die weitere Bearbeitung vorübergehend zurück.

Rechtlicher Hinweis: § 407a Abs. 4 S. 2 ZPO verpflichtet den Sachverständigen, das Gericht unverzüglich darauf hinzuweisen, wenn die voraussichtlich entstehenden Kosten erkennbar erheblich außer Verhältnis zum Wert des Streitgegenstandes stehen oder einen angeforderten Kostenvorschuss erheblich übersteigen. Eine Unterlassung kann gemäß § 8a Abs. 3 und 4 JVEG zum (teilweisen) Wegfall des Vergütungsanspruchs führen (BGH, Beschluss vom 13.10.2021 — IV ZB 14/21).

Mit freundlichen Grüßen

{{name_sv}}''',
  ),

  SvVorlageEintrag(
    id: 'GA_120',
    titel: 'GA 120 — Fristverlängerung (allgemein)',
    kategorie: 'anschreiben',
    sachgebiet: '110 JVEG & Hinweispflicht',
    inhalt: '''An: {{gericht}}
Aktenzeichen: {{aktenzeichen}}
In Sachen: {{parteien}}
Datum: {{heute}}

Sehr geehrte Damen und Herren,

ich beantrage die Verlängerung der mir gesetzten Frist zur
☐ Erstattung des Gutachtens
☐ Erstattung eines Ergänzungsgutachtens
☐ schriftlichen Stellungnahme zu Einwendungen der Parteien
☐ Beantwortung einer Verfügung / Hinweisbeschlusses
☐ [sonstige Frist]

bis zum {{neue_frist}}.

Kurzbegründung
{{begruendung}}

Mit freundlichen Grüßen

{{name_sv}}''',
  ),

  // ---------------- 130er Privatgutachten ----------------
  SvVorlageEintrag(
    id: 'GA_130',
    titel: 'GA 130 — Privatgutachten · Auftragsbestätigung (Werkvertrag)',
    kategorie: 'anschreiben',
    sachgebiet: '130 Privatgutachten',
    inhalt: '''Privatgutachten — Auftragsbestätigung
Werkvertrag nach §§ 631 ff. BGB

Auftraggeber
- Name / Firma: {{auftraggeber_name}}
- Anschrift: {{auftraggeber_anschrift}}
- Kontakt: {{auftraggeber_kontakt}}
- Verbraucher i. S. v. § 13 BGB?: [Ja / Nein]
- Vertretungsbefugnis (bei juristischen Personen): …

Sachverständiger / Auftragnehmer
- Name: {{name_sv}}
- Bestellungsgebiet: {{bestellungsgebiet}}
- Anschrift: {{anschrift_sv}}
- Kontakt: {{email_sv}} / {{telefon_sv}} / USt-IdNr. {{ust_id}}

Gutachtenauftrag
- Gegenstand / Objektanschrift: {{objektadresse}}
- Zielsetzung des Gutachtens: {{gutachten_ziel}}
- Konkrete Fragestellung(en): {{fragestellung}}
- Form der Erstattung: [schriftlich / mündlich + Protokoll / Kurzgutachten]
- Voraussichtlicher Ortstermin: {{ortstermin_datum}}
- Voraussichtlicher Abgabetermin: {{voraussichtl_abgabe}}

Vergütungsvereinbarung
- Stundensatz netto: {{stundensatz}}
- Fahrtkosten: {{km_pauschale}}
- Mindesthonorar / Pauschale: …
- Obergrenze (Cap) — nur auf ausdrücklichen Wunsch: …
- Vorschuss bei Auftragserteilung: {{vorschuss}}

Zahlungsbedingungen
- Die Rechnung wird nach Erstattung des Gutachtens erteilt und ist innerhalb von 14 Tagen ohne Abzug zu zahlen.
- Bei Zahlungsverzug können Verzugszinsen nach § 288 BGB berechnet werden.
- Der Sachverständige ist berechtigt, Zwischenrechnungen bei Erreichen bestimmter Teilleistungen zu stellen.

Allgemeine Vertragsbedingungen
1. Werkvertrag nach §§ 631 ff. BGB — Grundlage dieses Auftrags. Der Sachverständige schuldet die sorgfältige, nachvollziehbare Gutachtenerstattung nach anerkannten Regeln der Technik.
2. Mitwirkungspflichten (§ 642 BGB): Der Auftraggeber stellt erforderliche Unterlagen rechtzeitig zur Verfügung und gewährleistet Zugang zum Objekt.
3. Nachbesserungsrecht (§ 635 BGB): Bei Mängeln des Gutachtens ist dem Sachverständigen Gelegenheit zur Nachbesserung zu geben.
4. Haftung: Vorsatz und grobe Fahrlässigkeit unbegrenzt; einfache Fahrlässigkeit auf den typischerweise vorhersehbaren Schaden, maximal auf die Deckungssumme der Vermögensschadenhaftpflicht von {{haftungssumme}} pro Schadensfall. Haftung gegenüber Dritten ist ausgeschlossen, soweit gesetzlich zulässig.
5. Schweigepflicht: Verschwiegenheit über alle im Rahmen des Auftrags bekannt gewordenen Tatsachen; das Gutachten wird ausschließlich an den Auftraggeber übergeben.
6. Urheberrecht: Das Gutachten ist urheberrechtlich geschützt; Weitergabe an Dritte oder Veröffentlichung nur mit schriftlicher Zustimmung.
7. DSGVO: Informationen zur Datenverarbeitung nach Art. 13 DSGVO siehe Anlage (GA 132).
8. Widerrufsrecht (bei Verbrauchern außerhalb Geschäftsräumen / Fernabsatz): gesonderte Belehrung nach §§ 312g, 355 BGB (GA 131).
9. Anwendbares Recht / Gerichtsstand: Es gilt deutsches Recht. Gerichtsstand — soweit gesetzlich zulässig — ist der Sitz des Sachverständigen.

Unterschriften

_________________________________
Ort, Datum — Auftraggeber

_________________________________
Ort, Datum — Sachverständiger''',
  ),

  SvVorlageEintrag(
    id: 'GA_131',
    titel: 'GA 131 — Widerrufsbelehrung + Muster-Widerrufsformular',
    kategorie: 'anschreiben',
    sachgebiet: '130 Privatgutachten',
    inhalt: '''Widerrufsbelehrung

Sie haben das Recht, binnen vierzehn Tagen ohne Angabe von Gründen diesen Vertrag zu widerrufen. Die Widerrufsfrist beträgt vierzehn Tage ab dem Tag des Vertragsabschlusses.

Um Ihr Widerrufsrecht auszuüben, müssen Sie uns ({{name_sv}}, {{anschrift_sv}}, {{email_sv}}, {{telefon_sv}}) mittels einer eindeutigen Erklärung (z. B. ein mit der Post versandter Brief oder E-Mail) über Ihren Entschluss, diesen Vertrag zu widerrufen, informieren. Sie können dafür das beigefügte Muster-Widerrufsformular verwenden, das jedoch nicht vorgeschrieben ist.

Zur Wahrung der Widerrufsfrist reicht es aus, dass Sie die Mitteilung über die Ausübung des Widerrufsrechts vor Ablauf der Widerrufsfrist absenden.

Folgen des Widerrufs

Wenn Sie diesen Vertrag widerrufen, haben wir Ihnen alle Zahlungen, die wir von Ihnen erhalten haben, einschließlich der Lieferkosten (mit Ausnahme zusätzlicher Kosten, die sich daraus ergeben, dass Sie eine andere Art der Lieferung als die von uns angebotene, günstigste Standardlieferung gewählt haben), unverzüglich und spätestens binnen vierzehn Tagen ab dem Tag zurückzuzahlen, an dem die Mitteilung über Ihren Widerruf dieses Vertrags bei uns eingegangen ist.

Haben Sie verlangt, dass die Dienstleistungen während der Widerrufsfrist beginnen soll, so haben Sie uns einen angemessenen Betrag zu zahlen, der dem Anteil der bis zu dem Zeitpunkt, zu dem Sie uns von der Ausübung des Widerrufsrechts hinsichtlich dieses Vertrags unterrichten, bereits erbrachten Dienstleistungen im Vergleich zum Gesamtumfang der im Vertrag vorgesehenen Dienstleistungen entspricht.

Besonderer Hinweis zum vorzeitigen Erlöschen

Das Widerrufsrecht erlischt bei einem Vertrag zur Erbringung von Dienstleistungen vorzeitig, wenn der Unternehmer die Dienstleistung vollständig erbracht hat und mit der Ausführung der Dienstleistung erst begonnen hatte, nachdem der Verbraucher dazu seine ausdrückliche Zustimmung gegeben hat und gleichzeitig seine Kenntnis davon bestätigt hat, dass er sein Widerrufsrecht bei vollständiger Vertragserfüllung durch den Unternehmer verliert (§ 356 Abs. 4 BGB).

Zustimmung zum vorzeitigen Beginn

Ich stimme ausdrücklich zu, dass der Sachverständige mit der Ausführung der Dienstleistung vor Ablauf der Widerrufsfrist beginnt. Mir ist bekannt, dass ich bei vollständiger Vertragserfüllung durch den Sachverständigen mein Widerrufsrecht verliere.

_________________________________
Ort, Datum — Unterschrift Auftraggeber

Muster-Widerrufsformular
(Wenn Sie den Vertrag widerrufen wollen, füllen Sie bitte dieses Formular aus und senden Sie es zurück.)

An: {{name_sv}}, {{anschrift_sv}}, {{email_sv}}

Hiermit widerrufe(n) ich/wir den von mir/uns abgeschlossenen Vertrag über die folgende Dienstleistung: Privatgutachten vom {{vertragsdatum}}

Bestellt am: {{bestelldatum}}
Name des/der Verbraucher(s): {{auftraggeber_name}}
Anschrift des/der Verbraucher(s): {{auftraggeber_anschrift}}

_________________________________
Datum — Unterschrift Verbraucher (nur bei Mitteilung auf Papier)''',
  ),

  SvVorlageEintrag(
    id: 'GA_132',
    titel: 'GA 132 — DSGVO-Informationsblatt (Art. 13 DSGVO)',
    kategorie: 'anschreiben',
    sachgebiet: '130 Privatgutachten',
    inhalt: '''DSGVO-Informationsblatt
Informationen zur Datenverarbeitung nach Art. 13 DSGVO

1. Verantwortlicher
- Name / Firma: {{name_sv}}
- Anschrift: {{anschrift_sv}}
- Telefon: {{telefon_sv}}
- E-Mail: {{email_sv}}
- Datenschutzbeauftragter (falls vorhanden): …

2. Zwecke und Rechtsgrundlagen der Datenverarbeitung
- Zweck A — Durchführung des Gutachtenauftrags: Art. 6 Abs. 1 lit. b DSGVO (Vertragserfüllung)
- Zweck B — Abrechnung und Buchhaltung: Art. 6 Abs. 1 lit. c DSGVO (rechtliche Verpflichtung) — Aufbewahrung nach § 147 AO und § 257 HGB
- Zweck C — Kommunikation mit Parteien, Gericht, Dritten: Art. 6 Abs. 1 lit. b / c DSGVO
- Zweck D — Berechtigte Interessen (z. B. Dokumentation zur Abwehr von Haftungsansprüchen): Art. 6 Abs. 1 lit. f DSGVO
- Zweck E — Gesundheitsdaten / besondere Kategorien (nur wenn zwingend erforderlich): Art. 9 Abs. 2 lit. f DSGVO i. V. m. Art. 6 Abs. 1 lit. b DSGVO

3. Kategorien personenbezogener Daten
- Kontaktdaten (Name, Anschrift, Telefon, E-Mail)
- Identifikationsdaten (soweit zur Auftragsabwicklung erforderlich)
- Objektbezogene Daten (Anschrift, Lage, Eigentumsverhältnisse, Mängelbeschreibung)
- Foto-, Video- und Messdaten aus dem Ortstermin
- Vertrags- und Zahlungsdaten

4. Empfänger / Kategorien von Empfängern
- Gerichte, Behörden und öffentliche Stellen (soweit gesetzlich erforderlich)
- Rechtsanwälte, weitere Sachverständige oder Hilfskräfte (§ 407a Abs. 3 ZPO-konform)
- Dienstleister nach Auftragsverarbeitungsvertrag gem. Art. 28 DSGVO (IT, Labore, Druckereien)
- Steuerberater und Betriebsprüfer (auf gesetzlicher Grundlage)
- Ggf. Versicherer zur Schadensregulierung
- Keine Übermittlung an Drittländer außerhalb der EU/EWR (außer bei Vorliegen der Voraussetzungen nach Kap. V DSGVO)

5. Speicherdauer
- Gutachtenunterlagen und Korrespondenz: 10 Jahre nach Abschluss (Haftungsrisiko / steuerliche Pflicht)
- Rechnungs- und Buchhaltungsdaten: 10 Jahre nach Ende des Kalenderjahres (§ 147 AO)
- Foto- und Videodaten: i. d. R. 10 Jahre parallel zu den Gutachtenunterlagen
- Anfragen ohne Auftragserteilung: gelöscht nach Abschluss, spätestens nach 12 Monaten

6. Ihre Rechte als betroffene Person
- Auskunft (Art. 15 DSGVO)
- Berichtigung (Art. 16 DSGVO)
- Löschung (Art. 17 DSGVO), soweit keine gesetzliche Aufbewahrungspflicht entgegensteht
- Einschränkung der Verarbeitung (Art. 18 DSGVO)
- Datenübertragbarkeit (Art. 20 DSGVO)
- Widerspruch (Art. 21 DSGVO)
- Widerruf einer Einwilligung (Art. 7 Abs. 3 DSGVO)
- Beschwerde bei der Aufsichtsbehörde (Art. 77 DSGVO)

7. Pflicht zur Bereitstellung
Die Bereitstellung der Daten ist für die Durchführung des Gutachtenauftrags erforderlich. Ohne diese Daten kann der Auftrag nicht oder nur eingeschränkt bearbeitet werden.

8. Automatisierte Entscheidungsfindung / Profiling
Eine automatisierte Entscheidungsfindung im Sinne von Art. 22 DSGVO findet nicht statt.

Kenntnisnahme
Dieses Informationsblatt wurde mir mit der Auftragsbestätigung ausgehändigt.

_________________________________
Ort, Datum — Unterschrift Auftraggeber (empfohlen)''',
  ),

  SvVorlageEintrag(
    id: 'GA_133',
    titel: 'GA 133 — Rechnung Privatgutachten (§ 14 UStG)',
    kategorie: 'anschreiben',
    sachgebiet: '130 Privatgutachten',
    inhalt: '''Rechnung Privatgutachten

Rechnungssteller
- Name: {{name_sv}}
- Anschrift: {{anschrift_sv}}
- Kontakt: {{email_sv}} / {{telefon_sv}}
- Steuernummer: {{steuernummer}}
- USt-IdNr.: {{ust_id}}

Rechnungsempfänger
- Name / Firma: {{auftraggeber_name}}
- Anschrift: {{auftraggeber_anschrift}}
- Kundennummer / Aktenzeichen: {{aktenzeichen}}

Rechnungsdaten
- Rechnungsnummer: {{rechnungsnummer}}
- Rechnungsdatum: {{heute}}
- Leistungsdatum / Leistungszeitraum: {{leistungszeitraum}}
- Auftragsbestätigung vom: {{auftragsdatum}}

Leistungsaufstellung
| Pos. | Leistung | Datum | Menge | Einzel (EUR) | Gesamt (EUR) |
|------|----------|-------|-------|--------------|--------------|
| 1    | Aktenstudium / Vorbereitung |       |       |              |              |
| 2    | Ortstermin am Objekt inkl. An-/Abreise |       |       |              |              |
| 3    | Recherche, Messauswertung, Berechnungen |       |       |              |              |
| 4    | Gutachtenabfassung |       |       |              |              |
| 5    | Fahrtkosten (km × Pauschale) |       |       |              |              |
| 6    | Fotos / Ausdrucke / Kopien |       |       |              |              |
| 7    | Sonstiges (Laborkosten, Hilfskräfte etc.) |       |       |              |              |

Summe
- Zwischensumme netto: …
- Umsatzsteuer 19 %: …
- Gesamtbetrag brutto: …
- abzüglich bereits geleisteter Vorschuss vom {{vorschuss_datum}}: …
- Restzahlungsbetrag: …

Zahlungsbedingungen
- Zahlung innerhalb von 14 Tagen ohne Abzug
- Kontoinhaber: {{name_sv}}
- IBAN: {{iban}}
- BIC: {{bic}}
- Verwendungszweck: {{rechnungsnummer}} — {{auftraggeber_name}}

Mit freundlichen Grüßen

{{name_sv}}''',
  ),

  // ---------------- 200er Qualitätssicherung ----------------
  SvVorlageEintrag(
    id: 'GA_200',
    titel: 'GA 200 — Checkliste Gutachtenauftrag (9 Phasen)',
    kategorie: 'gutachten',
    sachgebiet: '200 Qualitätssicherung',
    inhalt: '''Gesamtcheckliste Gutachtenauftrag — 9 Phasen

Phase 1 — Eingang des Gutachtenauftrags
☐ Beweisbeschluss vollständig erhalten (Datum, Aktenzeichen, Kammer, Beweisfragen)?
☐ Akten vollständig eingegangen?
☐ Bestellungsgebiet geprüft (§ 407a Abs. 1 ZPO)?
☐ Besorgnis der Befangenheit geprüft?
☐ Zeitkapazität geprüft — Bearbeitung innerhalb der Frist möglich?
☐ Eingangsbestätigung an Gericht versandt (GA 104)?
☐ Auslagenvorschuss beantragt, wenn Aufwand > 1.000 EUR zu erwarten (GA 110)?
☐ Auftrag ggf. abgelehnt (GA 107) oder Befangenheit angezeigt (GA 106)?

Phase 2 — Aktenstudium und Auftragsklärung
☐ Alle Schriftsätze vollständig gelesen und erfasst?
☐ Beweisfragen sprachlich und inhaltlich präzise verstanden?
☐ Widersprüche zwischen Klage, Erwiderung und Beweisfragen identifiziert?
☐ Nachzureichende Unterlagen identifiziert und gelistet?
☐ Zwischenbericht 2 Wochen nach Akteneingang erstattet (GA 105)?
☐ Klärungsfragen an das Gericht rechtzeitig gestellt — schriftlich?
☐ Einladung zum Ortstermin vorbereitet (GA 101)?

Phase 3 — Ortstermin / Inaugenscheinnahme
☐ Alle Parteien und PB ordnungsgemäß eingeladen — Ladungsfrist mind. 2 Wochen?
☐ Gericht nachrichtlich über Termin informiert?
☐ Vorbereitung: Checkliste GA 102, Messmittel, Fotoausrüstung, Pläne dabei?
☐ Anwesende Personen namentlich dokumentiert?
☐ Zutritt zu allen beweiserheblichen Räumen / Bauteilen sichergestellt?
☐ Keine Stellungnahme zur Sache gegenüber den Parteien?
☐ Bauteilöffnungen nur mit Zustimmung aller Parteien oder Anordnung?
☐ Fotodokumentation fortlaufend nummeriert mit Datum/Standort?
☐ Wortmeldungen sinngemäß protokolliert — keine Rechtsausführungen?
☐ Protokoll am Ende vorgelesen und ggf. ausgehändigt?

Phase 4 — Gutachtenerstellung
☐ Gliederung: Auftrag — Grundlagen — Ist-Situation/Feststellungen — Soll-Zustand/Beurteilung — Zusammenfassung — Anlagen?
☐ Keine Rechtsausführungen / ausschließlich technische Beurteilung?
☐ Anerkannte Regeln der Technik + DIN-Normen korrekt zitiert (mit Stand)?
☐ Methoden, Messungen, Berechnungen nachprüfbar dargestellt?
☐ Jede Beweisfrage explizit und vollständig beantwortet?
☐ Keine Vermischung von Befund und Beurteilung?
☐ Wahrscheinlichkeitsangaben präzise formuliert (siehe GA 220)?
☐ Varianten und Unsicherheiten offen kommuniziert?
☐ Höchstpersönliche Erstattung gewahrt — Hilfskräfte nach § 407a Abs. 3 ZPO offen gelegt?
☐ Anlagen durchnummeriert, im Text referenziert, im Verzeichnis geführt (GA 103)?

Phase 5 — Kostenkontrolle / Hinweispflicht
☐ Tätigkeitsprotokoll (GA 100) laufend geführt?
☐ Kostenprognose mit erhaltenem Vorschuss verglichen — Stand jede Woche?
☐ Bei erkennbarer Überschreitung um ≥ ca. 20 %: Hinweis nach § 407a Abs. 4 S. 2 ZPO (GA 113) abgegeben?
☐ Bei Fristüberschreitung: Mitteilung § 411 Abs. 1 ZPO (GA 100a / 100b)?
☐ Arbeit nach Hinweis bis zur Rückmeldung des Gerichts eingestellt?
☐ Kein Weiterarbeiten über Vorschuss hinaus ohne Zustimmung?

Phase 6 — Einreichung / mündliche Anhörung
☐ Gutachten vor Abgabe nochmals auf Vollständigkeit und Rechtschreibung geprüft?
☐ Unterschrift + Rundsiegel aufgebracht?
☐ Einreichung in erforderlicher Stückzahl (Original + Abschriften für alle Parteien)?
☐ Übermittlung bevorzugt per beA / elektronisch — Datum, Übertragungsprotokoll dokumentiert?
☐ Schriftliche Stellungnahme auf Einwendungen fristgerecht?
☐ Vorbereitung der mündlichen Anhörung (§ 411 Abs. 3 ZPO)?

Phase 7 — Vergütung
☐ Vergütungsantrag (GA 111) binnen 3 Monaten nach Beendigung der Tätigkeit (§ 2 Abs. 1 JVEG)?
☐ Alle Auslagen belegt — Fahrtnachweise, Belege, Stundenzettel?
☐ Richtigkeit und Vollständigkeit versichert?
☐ Honorargruppe M1/M2/M3 korrekt angesetzt?

Phase 8 — Archivierung
☐ Akte vollständig digital und analog abgelegt?
☐ Aufbewahrungsfristen beachtet (10 Jahre Steuerrecht / DSGVO / Haftungsrisiko)?
☐ Zugriff auf Akte nur für Berechtigte (§ 203 StGB — Schweigepflicht)?
☐ Datenschutzkonforme Vernichtung nach Ablauf der Frist geplant?
☐ Rücksendung der Originalakten an das Gericht?

Phase 9 — Reflexion und Qualitätsverbesserung
☐ Rückmeldung des Gerichts ausgewertet?
☐ Entscheidung (Urteil) beschafft — dient der fachlichen Fortbildung?
☐ Fortbildungsbedarf identifiziert (§ 18 SVO)?
☐ Beitrag zur Erfahrungssammlung / Kollegiumsaustausch geleistet?
☐ Prozessfehler dokumentiert und in Checkliste nachgetragen?''',
  ),

  SvVorlageEintrag(
    id: 'GA_210',
    titel: 'GA 210 — Textbausteine Gutachten (Einleitung, Befund, Beurteilung)',
    kategorie: 'gutachten',
    sachgebiet: '200 Qualitätssicherung',
    inhalt: '''Grundprinzipien der Gutachtensprache
- Präzise, nachprüfbar, sachlich — jeder Satz muss durch einen Juristen ohne Fachwissen verstanden werden können.
- Befund (Ist-Zustand) klar trennen von Beurteilung (Soll-Zustand-Abgleich).
- Keine Rechtsausführungen — der SV beurteilt Technik, nicht Recht.
- Wahrscheinlichkeitsangaben bewusst und differenziert (siehe GA 220).
- Fachterminologie statt Umgangssprache.
- Gliederung mit Zwischenüberschriften, Nummerierung von Feststellungen.

Baustein — Grundlagen des Gutachtens
Das vorliegende Gutachten stützt sich auf:
- die zur Verfügung gestellten Akten (Schriftsätze, Anlagen, Pläne),
- die persönliche Inaugenscheinnahme am {{ortstermin_datum}} am Ortstermin,
- die ergänzenden Messungen und Bauteilöffnungen wie im Befund beschrieben,
- die zum Zeitpunkt der Leistungserbringung anerkannten Regeln der Technik, insbesondere [DIN-Nummer : JJJJ-MM, Titel], [VOB/C-Abschnitt DIN 18xxx].

Baustein — Feststellungen (Befund)
(Neutraler, beschreibender Stil — keine Bewertung, keine Ursachensuche auf dieser Stufe.)

Beispiele:
- "Am … war festzustellen, dass die Dachentwässerung über außenliegende Regenfallrohre DN 100 aus verzinktem Stahlblech erfolgt. Das nördliche Fallrohr zeigt im unteren Drittel eine horizontale Rissbildung von ca. 120 mm Länge."
- "Die Messung der Bauteilfeuchte im Estrich der Küche ergab an drei Messstellen Werte von [x %], [x %] und [x %] nach CM-Methode. Die Messmethode ist in Anlage A04 dokumentiert."
- "Die Abweichung vom Nennmaß beträgt an der gemessenen Stelle [x mm] bei einer Referenzlänge von [x m]."

Baustein — Beurteilung
(Abgleich mit Soll-Zustand, Ursachenbewertung, Wahrscheinlichkeiten — jede Aussage begründen.)

Beispiele:
- "Nach DIN [Nummer], Abschnitt [x.x], sind bei [Bauteil] Toleranzen von maximal [x mm] über eine Referenzlänge von [x m] zulässig. Die am Ortstermin festgestellte Abweichung liegt mit [x mm] oberhalb dieser Toleranzgrenze und stellt damit eine Abweichung von den anerkannten Regeln der Technik dar."
- "Die festgestellten Schadensbilder sind mit überwiegender Wahrscheinlichkeit auf eine ungenügende Abdichtung der horizontalen Arbeitsfuge zurückzuführen; alternative Ursachen (z. B. aufsteigende Feuchte) konnten durch die Messungen unter Anlage A06 ausgeschlossen werden."

Baustein — Einschränkungen / Grenzen
- "Das Gutachten ist auf Grundlage der am Ortstermin zugänglichen Bauteile erstellt; nicht zugängliche Bereiche konnten nicht beurteilt werden."
- "Über die gestellten Beweisfragen hinausgehende Feststellungen wurden nicht bewertet und sind nicht Gegenstand dieses Gutachtens."
- "Die Beurteilung erfolgt ausschließlich in technischer Hinsicht; eine rechtliche Bewertung (z. B. Verantwortlichkeit für Mängel, Gewährleistung, Verjährung) bleibt dem Gericht vorbehalten."
- "Grundlage sind die zum Zeitpunkt der Leistungserbringung (Bauzeit [JJJJ]) anerkannten Regeln der Technik; spätere Normanpassungen wurden nur referenziert, soweit relevant."

Baustein — Zusammenfassung
"Zusammenfassend ergeben die vorliegenden Feststellungen und ihre Beurteilung:
1. [Kurzantwort Beweisfrage 1 (1–2 Sätze)]
2. [Kurzantwort Beweisfrage 2]
3. [Kurzantwort Beweisfrage 3]"

Baustein — Schlussformel
"Das vorstehende Gutachten wurde nach bestem Wissen und Gewissen, unparteiisch und nach den anerkannten Regeln der Technik erstattet. Es steht dem Gericht für etwaige Rückfragen und eine mündliche Erläuterung zur Verfügung."

Baustein — Korrespondenz / E-Mail an Parteien
Anrede: "Sehr geehrte Frau … / sehr geehrter Herr …"
Abwehrformulierung: "Ich werde mich im Rahmen des mir erteilten Beweisbeschlusses ausschließlich im angefragten Umfang äußern. Rechtsfragen oder über den Beweisbeschluss hinausgehende Punkte kann ich nicht beantworten."
Schlussformel: "Mit freundlichen Grüßen, {{name_sv}} — öffentlich bestellter und vereidigter Sachverständiger für {{bestellungsgebiet}}."''',
  ),

  SvVorlageEintrag(
    id: 'GA_220',
    titel: 'GA 220 — Wahrscheinlichkeitsangaben (7-stufige Skala)',
    kategorie: 'gutachten',
    sachgebiet: '200 Qualitätssicherung',
    inhalt: '''Wahrscheinlichkeitsangaben im Gutachten — 7-stufige Skala

Grundsätze
- Sachverständige treffen Aussagen unter Unsicherheit — Wahrscheinlichkeit ist ein fachlich fundiertes Urteil, keine Willkür.
- Juristen erwarten klar abgestufte Aussagen; pauschales "möglich" oder "denkbar" hilft nicht weiter.
- Die gewählte Wahrscheinlichkeitsstufe ist stets zu begründen (warum diese Stufe, welche alternativen Ursachen werden wie ausgeschlossen).
- Unterscheidung: Gewissheit-Skala (Kausalität/Ursache) vs. Prognose-Skala (künftige Schäden).

7-stufige Skala

| Stufe | Formulierung (Langform) | Kurzform | Anteil | Indikation |
|-------|--------------------------|----------|--------|------------|
| 1 | an Sicherheit grenzende Wahrscheinlichkeit | so gut wie sicher | > 99 % | alle Alternativen ausgeschlossen |
| 2 | mit sehr hoher Wahrscheinlichkeit | sehr wahrscheinlich | > 90 % | nahezu alle Alternativen ausgeschlossen |
| 3 | mit hoher Wahrscheinlichkeit | hochwahrscheinlich | > 75 % | gewichtige Gründe sprechen dafür |
| 4 | mit überwiegender Wahrscheinlichkeit | überwiegend wahrscheinlich | > 50 % | mehr Gründe dafür als dagegen |
| 5 | nicht auszuschließen / möglich | denkbar, aber unsicher | ~ 25–50 % | ernstzunehmende, aber nicht vorrangige Indizien |
| 6 | unwahrscheinlich | wenig wahrscheinlich | < 25 % | wenige Anhaltspunkte, viele Gegenindikatoren |
| 7 | praktisch ausgeschlossen | so gut wie auszuschließen | < 10 % | klare gegenteilige Befunde |

Formulierungsbeispiele

Stufe 1 — "Die festgestellten Rissbildungen im Estrich sind mit an Sicherheit grenzender Wahrscheinlichkeit auf das Fehlen von Dehnungsfugen nach DIN 18560-2 zurückzuführen. Alternative Ursachen (Feuchteeintrag, mangelhafte Untergrundvorbereitung, falsche Mischung) wurden durch die Messungen in Anlage A03–A05 ausgeschlossen."

Stufe 3 — "Die Durchfeuchtung des Kellermauerwerks ist mit hoher Wahrscheinlichkeit auf eine mangelhaft ausgeführte Horizontalsperre im Bereich des Gebäudesockels zurückzuführen. Eine alternative Ursache — drückendes Grundwasser — kann nicht vollständig ausgeschlossen werden, erscheint aber aufgrund der geodätischen Lage und des dokumentierten Grundwasserspiegels weniger plausibel."

Stufe 4 — "Nach Abwägung aller Feststellungen liegt mit überwiegender Wahrscheinlichkeit ein Ausführungsfehler der Dichtbahnanschlüsse vor. Andere Ursachen — mechanische Beschädigung, Baustoffalterung — sind nicht vollständig auszuschließen, treten aber gegenüber dem festgestellten Ausführungsbild zurück."

Stufe 5 — "Ein Beitrag der Nutzungsweise (unzureichendes Lüften) zur Schimmelbildung ist nicht auszuschließen, konnte anhand der vorliegenden Unterlagen jedoch nicht abschließend bewertet werden. Zur Klärung wären Feuchtemessprotokolle der Bewohner über mindestens sechs Wochen erforderlich."

Kein Gebrauch von
- "vielleicht", "eventuell", "gegebenenfalls" — zu unpräzise, juristisch nicht verwertbar
- "100 % sicher", "absolut sicher" — unangemessen; auch bei Stufe 1 wird Restunsicherheit eingeräumt
- "höchst wahrscheinlich" — uneinheitlich verstanden
- subjektive Formeln ("meiner Meinung nach", "ich glaube") — ersetzen durch sachliche Begründung

Typische Fehlerquellen
☐ Zu pauschale Aussage ohne Begründung der gewählten Stufe
☐ Vermischung von Wahrscheinlichkeit der Ursache und Wahrscheinlichkeit der Folge
☐ Springen zwischen Stufen im selben Gutachten ohne Zuordnung
☐ Verwechslung von "praktisch ausgeschlossen" (Stufe 7) und "ausgeschlossen" (Gewissheit)
☐ Prognoseaussagen in Kausalitätssprache (Vergangenheit vs. Zukunft)

Qualitätsprüfung (Selbstkontrolle)
☐ Ist die gewählte Stufe explizit benannt (nicht nur umschrieben)?
☐ Ist die Begründung transparent (welche Gründe dafür, welche dagegen)?
☐ Sind alternative Ursachen geprüft und ihr Ausschluss begründet?
☐ Werden Messdaten / Berechnungen / Regelwerke als Belege angeführt?
☐ Ist die Wortwahl konsistent zum festgelegten Vokabular?''',
  ),
];

/// Ergebnis des Imports.
class SvVorlagenImportReport {
  const SvVorlagenImportReport({required this.neu, required this.bereitsVorhanden});
  final int neu;
  final int bereitsVorhanden;
}

/// Importiert alle SV-Vorlagen als Textbausteine.
///
/// Verhalten:
/// - Alle bestehenden Textbausteine bleiben unverändert erhalten.
/// - Vorlagen, deren Titel bereits vorhanden ist (exakte Übereinstimmung),
///   werden **übersprungen** — kein Überschreiben, keine Duplikate.
/// - Alle Inserts laufen in einer einzigen Drift-Transaktion, damit die
///   DB-Isolate-Verbindung nicht durch hunderte Einzel-Round-Trips in den
///   "connection closed"-Zustand kippt.
Future<SvVorlagenImportReport> ladeSvVorlagen(WidgetRef ref) async {
  final db = ref.read(appDatabaseProvider);

  // Bestehende Titel einmal lesen, danach nur in-memory vergleichen.
  final vorhandeneTitel = <String>{};
  final rows = await (db.selectOnly(db.textbausteine)
        ..addColumns([db.textbausteine.titel]))
      .get();
  for (final r in rows) {
    final t = r.read(db.textbausteine.titel);
    if (t != null) vorhandeneTitel.add(t);
  }

  var neu = 0;
  var schon = 0;

  await db.transaction(() async {
    for (var i = 0; i < svVorlagen.length; i++) {
      final v = svVorlagen[i];
      if (vorhandeneTitel.contains(v.titel)) {
        schon++;
        continue;
      }
      await db.into(db.textbausteine).insert(
            TextbausteineCompanion.insert(
              titel: v.titel,
              kategorie: Value(v.kategorie),
              sachgebiet: Value(v.sachgebiet),
              inhalt: Value(v.inhalt),
              reihenfolge: Value(1000 + i),
              favorit: Value(v.favorit),
            ),
          );
      neu++;
    }
  });

  return SvVorlagenImportReport(neu: neu, bereitsVorhanden: schon);
}
