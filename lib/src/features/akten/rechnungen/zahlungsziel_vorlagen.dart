import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../system/einstellungen/einstellungen_repository.dart';

/// Eine Zahlungsziel-Vorlage, die in der Rechnungs-Einstellung
/// „Zahlungsbedingung" ausgewählt werden kann. Die Vorlage beschreibt
/// ein Zahlungsziel, ein optionales Skonto (Prozentsatz + kürzere
/// Frist) und einen Freitext, der als Schlusstext auf der Rechnung
/// erscheinen kann.
class ZahlungszielVorlage {
  final String key; // stabiler Identifier
  final String label; // Anzeige in Dropdown
  final int tage; // 0 = „sofort"; sonst: Zahlungsziel in Tagen
  final bool bar; // Barzahlung → auf PDF „in bar erhalten ..."
  final double? skontoProzent; // null = kein Skonto
  final int? skontoTage; // Frist für Skonto in Tagen
  final String text; // Freitext-Baustein für den Schlusstext

  const ZahlungszielVorlage({
    required this.key,
    required this.label,
    required this.tage,
    required this.text,
    this.bar = false,
    this.skontoProzent,
    this.skontoTage,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'tage': tage,
        'bar': bar,
        if (skontoProzent != null) 'skontoProzent': skontoProzent,
        if (skontoTage != null) 'skontoTage': skontoTage,
        'text': text,
      };

  factory ZahlungszielVorlage.fromJson(Map<String, dynamic> j) =>
      ZahlungszielVorlage(
        key: j['key']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        tage: (j['tage'] as num?)?.toInt() ?? 14,
        bar: j['bar'] == true,
        skontoProzent: (j['skontoProzent'] as num?)?.toDouble(),
        skontoTage: (j['skontoTage'] as num?)?.toInt(),
        text: j['text']?.toString() ?? '',
      );
}

const List<ZahlungszielVorlage> zahlungszielVorlagenDefaults = [
  ZahlungszielVorlage(
    key: 'netto14',
    label: '14 Tage netto',
    tage: 14,
    text:
        'Bitte überweisen Sie den Rechnungsbetrag innerhalb von 14 Tagen ohne Abzug auf das unten genannte Konto.',
  ),
  ZahlungszielVorlage(
    key: 'netto30',
    label: '30 Tage netto',
    tage: 30,
    text:
        'Bitte überweisen Sie den Rechnungsbetrag innerhalb von 30 Tagen ohne Abzug auf das unten genannte Konto.',
  ),
  ZahlungszielVorlage(
    key: 'sofort',
    label: 'sofort ohne Abzug',
    tage: 0,
    text:
        'Bitte überweisen Sie den Rechnungsbetrag umgehend und ohne Abzug auf das unten genannte Konto.',
  ),
  ZahlungszielVorlage(
    key: 'bar',
    label: 'in bar bei Leistung',
    tage: 0,
    bar: true,
    text:
        'Betrag in bar erhalten am _____________ (Datum) · Unterschrift _____________',
  ),
  ZahlungszielVorlage(
    key: 'skonto2_7_netto30',
    label: '30 Tage netto / 2 % Skonto bei 7 Tagen',
    tage: 30,
    skontoProzent: 2.0,
    skontoTage: 7,
    text:
        'Zahlungsziel: 30 Tage netto. Bei Zahlung innerhalb von 7 Tagen '
            'gewähren wir 2 % Skonto.',
  ),
  ZahlungszielVorlage(
    key: 'skonto3_10_netto30',
    label: '30 Tage netto / 3 % Skonto bei 10 Tagen',
    tage: 30,
    skontoProzent: 3.0,
    skontoTage: 10,
    text:
        'Zahlungsziel: 30 Tage netto. Bei Zahlung innerhalb von 10 Tagen '
            'gewähren wir 3 % Skonto.',
  ),
];

/// Liest Vorlagen aus Einstellungen (Key = `rechnung.zahlungsziele`) —
/// wenn nichts gesetzt ist, werden die [zahlungszielVorlagenDefaults]
/// zurückgegeben.
Future<List<ZahlungszielVorlage>> ladeZahlungszielVorlagen(
    EinstellungenRepository repo) async {
  final raw = await repo.get('rechnung.zahlungsziele');
  if (raw == null || raw.trim().isEmpty) {
    return zahlungszielVorlagenDefaults;
  }
  try {
    final list = jsonDecode(raw);
    if (list is! List) return zahlungszielVorlagenDefaults;
    return list
        .whereType<Map>()
        .map((m) => ZahlungszielVorlage.fromJson(m.cast<String, dynamic>()))
        .toList();
  } catch (_) {
    return zahlungszielVorlagenDefaults;
  }
}

Future<void> speichereZahlungszielVorlagen(
  EinstellungenRepository repo,
  List<ZahlungszielVorlage> list,
) async {
  final json = jsonEncode(list.map((v) => v.toJson()).toList());
  await repo.set('rechnung.zahlungsziele', json);
}

final zahlungszielVorlagenProvider =
    FutureProvider<List<ZahlungszielVorlage>>((ref) async {
  return ladeZahlungszielVorlagen(
      ref.watch(einstellungenRepositoryProvider));
});

/// Rechnet den Skonto-Betrag und das verkürzte Zahlungsziel aus.
class SkontoErgebnis {
  final double bruttoOrig;
  final double skontoBetrag;
  final double zuZahlenMitSkonto;
  final int tageMitSkonto;
  const SkontoErgebnis({
    required this.bruttoOrig,
    required this.skontoBetrag,
    required this.zuZahlenMitSkonto,
    required this.tageMitSkonto,
  });
}

SkontoErgebnis? berechneSkonto(
  ZahlungszielVorlage v, {
  required double brutto,
}) {
  final prozent = v.skontoProzent;
  final tage = v.skontoTage;
  if (prozent == null || tage == null) return null;
  final abzug = brutto * (prozent / 100);
  return SkontoErgebnis(
    bruttoOrig: brutto,
    skontoBetrag: abzug,
    zuZahlenMitSkonto: brutto - abzug,
    tageMitSkonto: tage,
  );
}
