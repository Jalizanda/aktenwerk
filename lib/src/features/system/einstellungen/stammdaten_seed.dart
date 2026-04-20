import 'einstellungen_repository.dart';

/// Vordefinierte Stammdaten-Profile. Werden über den Admin-Button
/// „Stammdaten laden" in die Einstellungen geschrieben.
class StammdatenProfil {
  final String key;
  final String label;
  final Map<String, String> values;
  const StammdatenProfil({
    required this.key,
    required this.label,
    required this.values,
  });
}

/// Produktiv-Mandant „Bauelemente-Experte" (Alexander Höpken).
final stammdatenBauelementeExperte = StammdatenProfil(
  key: 'bauelemente-experte',
  label: 'Bauelemente-Experte (Alexander Höpken)',
  values: {
    SettingsKeys.firmaName: 'Alexander Höpken',
    SettingsKeys.firmaTitel: 'Dipl.-Ing. (FH), M. Eng.',
    SettingsKeys.firmaAnschrift:
        'Auf dem Stemmingholt 21\n46499 Hamminkeln\nDeutschland',
    SettingsKeys.firmaTelefon: '+49 152 519 75 042',
    SettingsKeys.firmaEmail: 'hello@aktenwerk.app',
    SettingsKeys.firmaWebsite: 'bauelemente-experte.de',
    SettingsKeys.firmaBestellung1:
        'Diplom-Ingenieur (FH) Bauingenieurwesen\n'
            'Master of Engineering – Fenster & Fassade (TH Rosenheim)\n'
            'ift-Fachingenieur für Fenster & Fassade',
    SettingsKeys.firmaBestellung2:
        'Energieberater (BAFA) / Energieeffizienz-Experte (BEG)\n'
            'Beraternummer EB463265\n'
            'Sachverständiger für Fenster, Türen, Fassade und Sonnenschutz',
    SettingsKeys.steuerUstId: 'DE240376766',
    SettingsKeys.steuerKleinunternehmer: 'nein',
    SettingsKeys.bankInhaber: 'Alexander Höpken',
    SettingsKeys.bankName: 'Volksbank Rhein-Lippe',
    SettingsKeys.bankIban: 'DE54 3566 0599 1201 3270 20',
    SettingsKeys.bankBic: 'GENODED1RLW',
    SettingsKeys.standardStundensatz: '140',
    SettingsKeys.stundensatzJveg: '130',
    SettingsKeys.standardUstSatz: '19',
    SettingsKeys.standardZahlungszielTage: '14',
    SettingsKeys.jvegKmSatz: '0.42',
    SettingsKeys.jvegSchreibsatz: '1.80',
    SettingsKeys.jvegKopieSw: '0.50',
    SettingsKeys.jvegKopieFarbe: '1.00',
    SettingsKeys.jvegLichtbildErstes: '2.00',
    SettingsKeys.jvegLichtbildWeitere: '1.00',
    SettingsKeys.nummernkreisAktenzeichen: '{YYYY}-{NNN}',
    SettingsKeys.nummernkreisAktenzeichenReset: 'jahr',
    SettingsKeys.nummernkreisAngebot: 'A{YYYY}-{NNN}',
    SettingsKeys.nummernkreisAngebotReset: 'jahr',
    SettingsKeys.nummernkreisRechnung: 'R{YYYY}-{NNN}',
    SettingsKeys.nummernkreisRechnungReset: 'jahr',
    SettingsKeys.nummernkreisGutachten: '{aktenzeichen}-G{N}',
    SettingsKeys.nummernkreisGutachtenReset: 'nie',
    SettingsKeys.nummernkreisFortbildung: 'FB{YYYY}-{NN}',
    SettingsKeys.nummernkreisFortbildungReset: 'jahr',
    SettingsKeys.rechnungSchlusstext:
        'Bitte überweisen Sie den Rechnungsbetrag innerhalb des Zahlungsziels '
            'auf das unten genannte Konto. Vielen Dank für Ihren Auftrag.',
    SettingsKeys.rechnungFusstext:
        'Alexander Höpken · Auf dem Stemmingholt 21 · 46499 Hamminkeln · '
            'USt-IdNr.: DE240376766',
    SettingsKeys.angebotFusstext:
        'Freibleibendes Angebot – gültig 30 Tage ab Angebotsdatum.',
  },
);

/// Demo-Mandant (fiktives Sachverständigenbüro zum Testen).
final stammdatenDemo = StammdatenProfil(
  key: 'demo',
  label: 'Demo-Sachverständigenbüro',
  values: {
    SettingsKeys.firmaName: 'Musterbüro Schmitz',
    SettingsKeys.firmaTitel: 'Dipl.-Ing. (FH)',
    SettingsKeys.firmaAnschrift:
        'Musterweg 12\n40212 Düsseldorf\nDeutschland',
    SettingsKeys.firmaTelefon: '+49 211 12345678',
    SettingsKeys.firmaEmail: 'demo@aktenwerk.app',
    SettingsKeys.firmaWebsite: 'aktenwerk.app',
    SettingsKeys.firmaLogoBase64:
        'PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA0MDAgMTAwIj4KICA8ZGVmcz4KICAgIDxsaW5lYXJHcmFkaWVudCBpZD0iZyIgeDE9IjAiIHkxPSIwIiB4Mj0iMSIgeTI9IjEiPgogICAgICA8c3RvcCBvZmZzZXQ9IjAiIHN0b3AtY29sb3I9IiMyNTYzZWIiLz4KICAgICAgPHN0b3Agb2Zmc2V0PSIxIiBzdG9wLWNvbG9yPSIjMWU0MGFmIi8+CiAgICA8L2xpbmVhckdyYWRpZW50PgogIDwvZGVmcz4KICA8cmVjdCB4PSIwIiB5PSIwIiB3aWR0aD0iODAiIGhlaWdodD0iODAiIHJ4PSIxMCIgZmlsbD0idXJsKCNnKSIvPgogIDx0ZXh0IHg9IjQwIiB5PSI1NiIgdGV4dC1hbmNob3I9Im1pZGRsZSIgZmlsbD0id2hpdGUiIGZvbnQtZmFtaWx5PSJBcmlhbCIgZm9udC1zaXplPSI0MiIgZm9udC13ZWlnaHQ9ImJvbGQiPk1TPC90ZXh0PgogIDx0ZXh0IHg9Ijk1IiB5PSI0MiIgZmlsbD0iIzFlNDBhZiIgZm9udC1mYW1pbHk9IkFyaWFsIiBmb250LXNpemU9IjI0IiBmb250LXdlaWdodD0iYm9sZCI+TXVzdGVyYsO8cm88L3RleHQ+CiAgPHRleHQgeD0iOTUiIHk9IjcwIiBmaWxsPSIjNjQ3NDhiIiBmb250LWZhbWlseT0iQXJpYWwiIGZvbnQtc2l6ZT0iMTYiPlNjaG1pdHogwrcgU2FjaHZlcnN0w6RuZGlnZTwvdGV4dD4KPC9zdmc+',
    SettingsKeys.firmaLogoMime: 'image/svg+xml',
    SettingsKeys.firmaBestellung1:
        'Dipl.-Ing. (FH) Bauingenieurwesen\n'
            'Öffentlich bestellter und vereidigter Sachverständiger\n'
            'für Schäden an Gebäuden (IHK Düsseldorf)',
    SettingsKeys.firmaBestellung2:
        'Mitglied im BVS (Bundesverband öffentlich bestellter\n'
            'und vereidigter sowie qualifizierter Sachverständiger)',
    SettingsKeys.steuerUstId: 'DE123456789',
    SettingsKeys.steuerNr: '133/5100/0012',
    SettingsKeys.steuerKleinunternehmer: 'nein',
    SettingsKeys.bankInhaber: 'Musterbüro Schmitz',
    SettingsKeys.bankName: 'Sparkasse Düsseldorf',
    SettingsKeys.bankIban: 'DE12 3005 0110 0012 3456 78',
    SettingsKeys.bankBic: 'DUSSDEDDXXX',
    SettingsKeys.standardStundensatz: '120',
    SettingsKeys.stundensatzJveg: '130',
    SettingsKeys.standardUstSatz: '19',
    SettingsKeys.standardZahlungszielTage: '14',
    SettingsKeys.jvegKmSatz: '0.42',
    SettingsKeys.jvegSchreibsatz: '1.80',
    SettingsKeys.jvegKopieSw: '0.50',
    SettingsKeys.jvegKopieFarbe: '1.00',
    SettingsKeys.jvegLichtbildErstes: '2.00',
    SettingsKeys.jvegLichtbildWeitere: '1.00',
    SettingsKeys.nummernkreisAktenzeichen: '{YYYY}-{NNN}',
    SettingsKeys.nummernkreisAktenzeichenReset: 'jahr',
    SettingsKeys.nummernkreisAngebot: 'A{YYYY}-{NNN}',
    SettingsKeys.nummernkreisAngebotReset: 'jahr',
    SettingsKeys.nummernkreisRechnung: 'R{YYYY}-{NNN}',
    SettingsKeys.nummernkreisRechnungReset: 'jahr',
    SettingsKeys.nummernkreisGutachten: '{aktenzeichen}-G{N}',
    SettingsKeys.nummernkreisGutachtenReset: 'nie',
    SettingsKeys.nummernkreisFortbildung: 'FB{YYYY}-{NN}',
    SettingsKeys.nummernkreisFortbildungReset: 'jahr',
    SettingsKeys.rechnungSchlusstext:
        'Bitte überweisen Sie den Rechnungsbetrag innerhalb des Zahlungsziels '
            'auf das unten genannte Konto.',
    SettingsKeys.rechnungFusstext:
        'Musterbüro Schmitz · Musterweg 12 · 40212 Düsseldorf',
    SettingsKeys.angebotFusstext:
        'Freibleibendes Angebot – gültig 30 Tage ab Angebotsdatum.',
  },
);

Future<void> applyStammdatenProfil(
    EinstellungenRepository repo, StammdatenProfil p) async {
  for (final entry in p.values.entries) {
    await repo.set(entry.key, entry.value);
  }
}
