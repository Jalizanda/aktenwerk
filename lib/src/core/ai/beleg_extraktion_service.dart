import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show WidgetRef;

import '../../data/sync/auth_service.dart';
import '../../features/system/einstellungen/einstellungen_repository.dart';
import 'ki_modelle.dart';
import 'ki_usage_service.dart';

/// Ergebnis einer Beleg-Extraktion. Alle Felder optional — Gemini
/// lässt weg, was es nicht sicher erkennt.
class BelegExtraktion {
  const BelegExtraktion({
    this.rechnungsnummer,
    this.rechnungsdatum,
    this.leistungsdatum,
    this.faelligkeitsdatum,
    this.lieferantName,
    this.lieferantStrasse,
    this.lieferantPlz,
    this.lieferantOrt,
    this.lieferantUstId,
    this.netto,
    this.ustSatz,
    this.ustBetrag,
    this.brutto,
    this.zahlungsweise,
    this.bereitsBezahlt = false,
    this.kategorie,
    this.beschreibung,
    this.rohtext,
  });

  final String? rechnungsnummer;
  final DateTime? rechnungsdatum;
  final DateTime? leistungsdatum;
  final DateTime? faelligkeitsdatum;

  final String? lieferantName;
  final String? lieferantStrasse;
  final String? lieferantPlz;
  final String? lieferantOrt;
  final String? lieferantUstId;

  final double? netto;
  final double? ustSatz;
  final double? ustBetrag;
  final double? brutto;

  /// 'ueberweisung' | 'lastschrift' | 'kreditkarte' | 'paypal' | 'bar'
  final String? zahlungsweise;
  final bool bereitsBezahlt;

  /// Vorschlag für eine Kategorie (Freitext) — KI rät anhand der
  /// erkannten Positionen, welche SKR-Kategorie passen könnte.
  final String? kategorie;

  /// Kurzbeschreibung der Leistung/Warenbezug.
  final String? beschreibung;

  /// Antwort-Rohtext für Debug/Anzeige.
  final String? rohtext;
}

Schema _buildBelegSchema() => Schema.object(properties: {
  'rechnungsnummer':
      Schema.string(description: 'Rechnungs-/Belegnummer. Leer wenn nicht erkannt.'),
  'rechnungsdatum':
      Schema.string(description: 'ISO-Datum der Rechnung (YYYY-MM-DD). Leer wenn nicht erkannt.'),
  'leistungsdatum': Schema.string(
      description: 'ISO-Datum der Leistung, wenn abweichend. Sonst leer.'),
  'faelligkeitsdatum':
      Schema.string(description: 'ISO-Datum der Fälligkeit. Leer wenn nicht erkannt.'),
  'lieferant_name': Schema.string(
      description: 'Unternehmen/Händler/Verkäufer. Bei Barzahlung an Laden: Ladenname.'),
  'lieferant_strasse': Schema.string(description: 'Straße + Hausnummer.'),
  'lieferant_plz': Schema.string(description: 'Postleitzahl.'),
  'lieferant_ort': Schema.string(description: 'Ort.'),
  'lieferant_ust_id':
      Schema.string(description: 'USt-IdNr / Steuernummer. Leer wenn nicht vorhanden.'),
  'netto': Schema.number(
      description: 'Gesamtnetto-Betrag in EUR (Zahl ohne Währungssymbol).'),
  'ust_satz': Schema.number(
      description: 'Umsatzsteuersatz in Prozent (19, 7 oder 0). Leer wenn nicht ausgewiesen.'),
  'ust_betrag': Schema.number(description: 'USt-Betrag in EUR.'),
  'brutto': Schema.number(description: 'Bruttobetrag (Endbetrag) in EUR.'),
  'zahlungsweise': Schema.enumString(
    description: 'Zahlungsweise. "bar" nur bei Barzahlung, sonst "ueberweisung".',
    enumValues: [
      'ueberweisung',
      'lastschrift',
      'kreditkarte',
      'paypal',
      'bar',
    ],
  ),
  'bereits_bezahlt': Schema.boolean(
      description: 'True bei Barzahlung, Kreditkarte-Zahlung oder wenn "bezahlt" auf dem Beleg steht.'),
  'kategorie': Schema.string(
      description:
          'Kurze, menschenlesbare Kategorie, z. B. "Büromaterial", "Tankstelle", "Hotel", "Software-Abo".'),
  'beschreibung': Schema.string(
      description: 'Zwei-bis-drei-Wort-Beschreibung der Leistung, z. B. "Büromaterial Staples", "Kraftstoff Aral".'),
    });

Future<BelegExtraktion> extrahiereBeleg({
  required WidgetRef ref,
  required Uint8List bytes,
  required String mimeType,
}) async {
  final repo = ref.read(einstellungenRepositoryProvider);
  final modellId = await getKiModell(repo, KiAufgabe.belegErfassung);

  final model = FirebaseAI.vertexAI(location: 'europe-west1').generativeModel(
    model: modellId,
    systemInstruction: Content.system(
      'Du bist Buchhalter-Assistent und extrahierst aus einem '
      'Beleg/Kassenbon/Eingangsrechnung die folgenden Felder als '
      'strukturiertes JSON. Regeln:\n'
      '1. Bei Kassenbons ohne Rechnungsnummer die Bon-Nummer nehmen; '
      'sonst Feld leer lassen.\n'
      '2. Barzahlung (Kassenbon mit „Bar", „Cash", „Bargeld") → '
      'zahlungsweise = "bar" und bereits_bezahlt = true.\n'
      '3. Kreditkarten-/EC-Zahlung → zahlungsweise passend und '
      'bereits_bezahlt = true.\n'
      '4. Ausgewiesene MwSt immer auf Rechnungs-Gesamtebene ausgeben; '
      'bei mehreren Steuersätzen den Hauptsatz (größter Anteil) '
      'nehmen.\n'
      '5. Beträge als Dezimalzahl mit Punkt (nicht Komma) zurückgeben.\n'
      '6. Datumsangaben als ISO-String YYYY-MM-DD.\n'
      '7. Leere Strings für Felder, die nicht erkannt werden.\n'
      '8. Bei Preisen unbedingt Netto/USt/Brutto konsistent halten — '
      'wenn nur Brutto gedruckt ist, Netto und USt aus dem Satz '
      'rückrechnen.',
    ),
    generationConfig: GenerationConfig(
      temperature: 0.1,
      responseMimeType: 'application/json',
      responseSchema: _buildBelegSchema(),
    ),
  );

  final response = await model.generateContent([
    Content.multi([
      TextPart(
          'Extrahiere die Daten dieses Belegs gemäß dem vorgegebenen JSON-Schema.'),
      InlineDataPart(mimeType, bytes),
    ]),
  ]);

  // Usage tracking (fire-and-forget — Fehler ignorieren).
  try {
    final logger = ref.read(kiUsageLoggerProvider);
    final email = ref.read(authServiceProvider).currentUser?.email;
    await logger.log(
      aufgabe: KiAufgabe.belegErfassung,
      modellId: modellId,
      usage: response.usageMetadata,
      userEmail: email,
    );
  } catch (_) {}

  final raw = (response.text ?? '').trim();
  if (raw.isEmpty) {
    throw Exception('Leere Antwort vom Modell.');
  }
  final parsed = jsonDecode(raw);
  if (parsed is! Map) {
    throw Exception('Antwort war kein JSON-Objekt.');
  }
  final m = parsed;
  return BelegExtraktion(
    rechnungsnummer: _s(m['rechnungsnummer']),
    rechnungsdatum: _d(m['rechnungsdatum']),
    leistungsdatum: _d(m['leistungsdatum']),
    faelligkeitsdatum: _d(m['faelligkeitsdatum']),
    lieferantName: _s(m['lieferant_name']),
    lieferantStrasse: _s(m['lieferant_strasse']),
    lieferantPlz: _s(m['lieferant_plz']),
    lieferantOrt: _s(m['lieferant_ort']),
    lieferantUstId: _s(m['lieferant_ust_id']),
    netto: _n(m['netto']),
    ustSatz: _n(m['ust_satz']),
    ustBetrag: _n(m['ust_betrag']),
    brutto: _n(m['brutto']),
    zahlungsweise: _s(m['zahlungsweise']),
    bereitsBezahlt: (m['bereits_bezahlt'] as bool?) ?? false,
    kategorie: _s(m['kategorie']),
    beschreibung: _s(m['beschreibung']),
    rohtext: raw,
  );
}

String? _s(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

double? _n(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) {
    return double.tryParse(v.replaceAll(',', '.'));
  }
  return null;
}

DateTime? _d(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  if (t.isEmpty) return null;
  return DateTime.tryParse(t);
}
