/// SKR03/04-Kategorien-Katalog für Eingangsrechnungen.
///
/// Portiert aus der SV-Software — 24 typische Kategorien mit zugehörigen
/// Konten in SKR03 und SKR04 sowie dem regulären USt-Satz.
class SkrKategorie {
  final String key;
  final String label;
  final String skr03;
  final String skr04;
  final double ustSatz;
  const SkrKategorie({
    required this.key,
    required this.label,
    required this.skr03,
    required this.skr04,
    required this.ustSatz,
  });
}

const skrKategorien = <SkrKategorie>[
  SkrKategorie(
      key: 'kfz',
      label: 'Kfz-Kosten (Sprit, Reparatur, Leasing)',
      skr03: '4530',
      skr04: '6500',
      ustSatz: 19),
  SkrKategorie(
      key: 'kfz_versich',
      label: 'Kfz-Versicherung/Steuer',
      skr03: '4520',
      skr04: '6520',
      ustSatz: 0),
  SkrKategorie(
      key: 'reise',
      label: 'Reisekosten (Hotel, Bahn, Flug)',
      skr03: '4670',
      skr04: '6673',
      ustSatz: 7),
  SkrKategorie(
      key: 'bewirtung',
      label: 'Bewirtungskosten (geschäftlich, 70 %)',
      skr03: '4650',
      skr04: '6640',
      ustSatz: 19),
  SkrKategorie(
      key: 'buero',
      label: 'Bürobedarf / Verbrauchsmaterial',
      skr03: '4930',
      skr04: '6815',
      ustSatz: 19),
  SkrKategorie(
      key: 'porto',
      label: 'Porto / Versandkosten',
      skr03: '4910',
      skr04: '6800',
      ustSatz: 0),
  SkrKategorie(
      key: 'tel',
      label: 'Telefon / Internet / Mobilfunk',
      skr03: '4920',
      skr04: '6805',
      ustSatz: 19),
  SkrKategorie(
      key: 'edv',
      label: 'EDV / Software / Cloud-Dienste',
      skr03: '4940',
      skr04: '6810',
      ustSatz: 19),
  SkrKategorie(
      key: 'fortbildung',
      label: 'Fortbildung / Seminare / Literatur',
      skr03: '4948',
      skr04: '6840',
      ustSatz: 7),
  SkrKategorie(
      key: 'versicherung',
      label: 'Betriebsversicherung',
      skr03: '4360',
      skr04: '6400',
      ustSatz: 0),
  SkrKategorie(
      key: 'beitraege',
      label: 'Beiträge (Kammer, Verband, BVS, ift)',
      skr03: '4380',
      skr04: '6420',
      ustSatz: 0),
  SkrKategorie(
      key: 'rechtberatung',
      label: 'Rechts- und Beratungskosten',
      skr03: '4950',
      skr04: '6825',
      ustSatz: 19),
  SkrKategorie(
      key: 'steuerberatung',
      label: 'Steuerberatung / Buchführung',
      skr03: '4957',
      skr04: '6827',
      ustSatz: 19),
  SkrKategorie(
      key: 'werkzeug',
      label: 'Werkzeuge / Messgeräte (Verbrauch)',
      skr03: '4985',
      skr04: '6850',
      ustSatz: 19),
  SkrKategorie(
      key: 'gwg',
      label: 'GWG (Geringwertige Wirtschaftsgüter)',
      skr03: '0480',
      skr04: '0670',
      ustSatz: 19),
  SkrKategorie(
      key: 'afa',
      label: 'Abschreibung (AfA)',
      skr03: '4830',
      skr04: '6220',
      ustSatz: 0),
  SkrKategorie(
      key: 'miete',
      label: 'Miete Geschäftsraum / Nebenkosten',
      skr03: '4210',
      skr04: '6310',
      ustSatz: 0),
  SkrKategorie(
      key: 'energie',
      label: 'Strom / Heizung / Wasser',
      skr03: '4240',
      skr04: '6325',
      ustSatz: 19),
  SkrKategorie(
      key: 'fremdleistung',
      label: 'Fremdleistung / Subunternehmer',
      skr03: '3100',
      skr04: '5900',
      ustSatz: 19),
  SkrKategorie(
      key: 'werbung',
      label: 'Werbung / Marketing',
      skr03: '4600',
      skr04: '6600',
      ustSatz: 19),
  SkrKategorie(
      key: 'webhosting',
      label: 'Webhosting / Domain',
      skr03: '4920',
      skr04: '6805',
      ustSatz: 19),
  SkrKategorie(
      key: 'bankgebuehr',
      label: 'Bankgebühren / Kontoführung',
      skr03: '4970',
      skr04: '6855',
      ustSatz: 0),
  SkrKategorie(
      key: 'zinsen',
      label: 'Zinsaufwendungen',
      skr03: '2100',
      skr04: '7300',
      ustSatz: 0),
  SkrKategorie(
      key: 'sonstiges',
      label: 'Sonstige betriebliche Aufwendungen',
      skr03: '4980',
      skr04: '6855',
      ustSatz: 19),
];

SkrKategorie skrByKey(String? key) {
  return skrKategorien.firstWhere(
    (k) => k.key == key,
    orElse: () => skrKategorien.last,
  );
}

/// Liefert das passende Konto (SKR03 oder SKR04) anhand des globalen
/// Kontenrahmens aus den Einstellungen.
String kontoFor(String kategorieKey, String skr) {
  final k = skrByKey(kategorieKey);
  return skr == 'SKR04' ? k.skr04 : k.skr03;
}
