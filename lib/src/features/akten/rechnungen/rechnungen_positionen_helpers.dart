import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../shared/positionen/position_model.dart';
import '../../../shared/richtext/quill_editor.dart';

/// Hilfsfunktionen zum Befüllen der Positions-Liste einer Rechnung aus
/// verschiedenen Quellen (Stunden, Auslagen, JVEG-Vorlage).
class RechnungenPositionenHelper {
  RechnungenPositionenHelper(this._db, this._settings);
  final AppDatabase _db;
  final EinstellungenRepository _settings;

  /// Aggregiert Stunden des Auftrags nach Tätigkeit und Satz.
  /// Fällt auf den Default-Stundensatz aus den Einstellungen zurück, wenn
  /// der Stundeneintrag keinen eigenen Satz hat.
  Future<List<Position>> honorarAusStunden({
    required int auftragId,
    required String rechnungTyp,
  }) async {
    final rows = await (_db.select(_db.stunden)
          ..where((t) => t.auftragId.equals(auftragId)))
        .get();
    if (rows.isEmpty) return const [];

    // Auftragsweiten Satz und Fallbacks ermitteln.
    final auftrag = await (_db.select(_db.auftraege)
          ..where((t) => t.id.equals(auftragId)))
        .getSingleOrNull();
    final defaultSatz = double.tryParse(
            await _settings.getOr(SettingsKeys.standardStundensatz, '140')) ??
        140;
    final jvegGruppenSatz = switch ((auftrag?.honorargruppe ?? '').trim().toUpperCase()) {
      'M1' => 100.0,
      'M2' => 114.0,
      'M3' => 135.0,
      _ => null,
    };
    final fallback = auftrag?.stundensatz ??
        (rechnungTyp == 'jveg' ? (jvegGruppenSatz ?? defaultSatz) : defaultSatz);

    final grouped = <String, _AggPos>{};
    for (final s in rows) {
      final taetigkeit = (s.taetigkeit == null || s.taetigkeit!.trim().isEmpty)
          ? (rechnungTyp == 'jveg'
              ? 'Zeitaufwand Sachverständiger (§ 9 JVEG${auftrag?.honorargruppe != null ? ", ${auftrag!.honorargruppe}" : ""})'
              : 'Tätigkeit')
          : s.taetigkeit!.trim();
      final satz = s.satz ?? fallback;
      final stunden = s.minuten / 60.0;
      final key = '$taetigkeit|${satz.toStringAsFixed(2)}';
      final agg = grouped.putIfAbsent(
          key, () => _AggPos(taetigkeit: taetigkeit, satz: satz));
      if (rechnungTyp == 'jveg') {
        agg.minuten += s.minuten;
      } else {
        agg.menge += stunden;
      }
    }
    return grouped.values
        .map((a) {
          double menge = a.menge;
          if (rechnungTyp == 'jveg' && a.minuten > 0) {
            final h = (a.minuten / 60).floor();
            final rest = a.minuten % 60;
            if (rest > 30) {
              menge = (h + 1).toDouble();
            } else if (rest > 0) {
              menge = h + 0.5;
            } else {
              menge = h.toDouble();
            }
          }
          return Position(
              bezeichnung: a.taetigkeit,
              menge: _round2(menge),
              einheit: 'h',
              einzelpreis: _round2(a.satz),
              ustSatz: 19,
            );
        })
        .toList();
  }

  /// Übernimmt Auslagen eines Auftrags als Rechnungs-Positionen
  /// (nach Art + Einzelpreis gruppiert).
  Future<List<Position>> auslagenAusAuftrag({required int auftragId}) async {
    final rows = await (_db.select(_db.auslagen)
          ..where((t) => t.auftragId.equals(auftragId)))
        .get();
    if (rows.isEmpty) return const [];

    final grouped = <String, _AggAuslage>{};
    for (final a in rows) {
      final label = (a.beschreibung == null || a.beschreibung!.trim().isEmpty)
          ? _labelForArt(a.art ?? 'sonstiges')
          : a.beschreibung!.trim();
      final einheit = a.einheit ?? _einheitForArt(a.art ?? 'sonstiges');
      final key = '$label|${a.einzelpreis.toStringAsFixed(2)}|$einheit';
      final g = grouped.putIfAbsent(
          key,
          () => _AggAuslage(
                label: label,
                einzelpreis: a.einzelpreis,
                einheit: einheit,
              ));
      g.menge += a.menge;
    }
    return grouped.values
        .map((a) => Position(
              bezeichnung: a.label,
              menge: _round2(a.menge),
              einheit: a.einheit,
              einzelpreis: _round2(a.einzelpreis),
              ustSatz: 19,
            ))
        .toList();
  }

  /// Berechnet JVEG Auslagen anhand eines verknüpften Gutachtens (inkl. Zweitdrucken nach Ausfertigungen).
  Future<List<Position>> jvegAuslagenAusGutachten({
    required int auftragId,
    double honorarNetto = 0,
  }) async {
    final positions = <Position>[];

    final auftrag = await (_db.select(_db.auftraege)
          ..where((t) => t.id.equals(auftragId)))
        .getSingleOrNull();
    final anzAusf = (auftrag?.anzahlAusfertigungen ?? 1) < 1
        ? 1
        : (auftrag?.anzahlAusfertigungen ?? 1);

    // 1. Gutachten laden
    final gutachten = await (_db.select(_db.gutachten)
          ..where((t) => t.auftragId.equals(auftragId)))
        .getSingleOrNull();

    // 1b. Dokumente laden für Datei-Pauschale
    final dokumente = await (_db.select(_db.dokumente)
          ..where((t) => t.auftragId.equals(auftragId)))
        .get();
    final dateienCount = dokumente.length;

    int anschlaege = 0;
    if (gutachten?.abschnitteJson != null) {
      try {
        final map = jsonDecode(gutachten!.abschnitteJson!) as Map<String, dynamic>;
        for (final val in map.values) {
          final text = plainTextFromDeltaJson(val?.toString());
          anschlaege += text.length;
        }
      } catch (_) {}
    }

    // 2. Fotos laden
    final fotos = await (_db.select(_db.fotos)
          ..where((t) => t.auftragId.equals(auftragId)))
        .get();
    final fotoCount = fotos.length;

    // 3. Einstellungen
    final defaultSatzSchreib = double.tryParse(
            await _settings.getOr(SettingsKeys.jvegSchreibsatz, '0.90')) ??
        0.90;
    final defaultSatzFotoErst = double.tryParse(
            await _settings.getOr(SettingsKeys.jvegLichtbildErstes, '2.00')) ??
        2.00;
    final defaultSatzFotoZweit = double.tryParse(
            await _settings.getOr(SettingsKeys.jvegLichtbildWeitere, '0.50')) ??
        0.50;

    // Schreibauslagen (§ 12 Abs. 1 Satz 2 Nr. 3 JVEG): je angefangene 1.000 Anschläge
    if (anschlaege > 0) {
      final blocks = (anschlaege / 1000).ceil();
      positions.add(Position(
        bezeichnung:
            'Schreibauslagen (§ 12 Abs. 1 Nr. 3 JVEG) — $anschlaege Anschläge',
        menge: blocks.toDouble(),
        einheit: 'je 1000 Anschläge',
        einzelpreis: defaultSatzSchreib,
        ustSatz: 19,
      ));
    }

    // Kopien / Mehrfertigungen (§ 7 Abs. 2 JVEG) für weitere Ausfertigungen
    if (anschlaege > 0 && anzAusf > 1) {
      final geschaetzteSeitenProAusf = (anschlaege / 1800).ceil().clamp(1, 999);
      final kopieSeitenGesamt = geschaetzteSeitenProAusf * (anzAusf - 1);
      final erste50 = kopieSeitenGesamt > 50 ? 50 : kopieSeitenGesamt;
      final ab51 = kopieSeitenGesamt > 50 ? kopieSeitenGesamt - 50 : 0;
      positions.add(Position(
        bezeichnung:
            'Kopien / Abschriften s/w bis 50 S. (§ 7 Abs. 2 JVEG, ${anzAusf - 1} Mehrfertigungen)',
        menge: erste50.toDouble(),
        einheit: 'Seite',
        einzelpreis: 0.50,
        ustSatz: 19,
      ));
      if (ab51 > 0) {
        positions.add(Position(
          bezeichnung: 'Kopien / Abschriften s/w ab 51. Seite (§ 7 Abs. 2 JVEG)',
          menge: ab51.toDouble(),
          einheit: 'Seite',
          einzelpreis: 0.15,
          ustSatz: 19,
        ));
      }
    }

    // Lichtbilder (§ 12 Abs. 1 Satz 2 Nr. 2 JVEG)
    if (fotoCount > 0) {
      positions.add(Position(
        bezeichnung: 'Lichtbilder 1. Ausfertigung (§ 12 Abs. 1 Nr. 2 JVEG)',
        menge: fotoCount.toDouble(),
        einheit: 'Stk',
        einzelpreis: defaultSatzFotoErst,
        ustSatz: 19,
      ));
      if (anzAusf > 1) {
        final zweitCount = fotoCount * (anzAusf - 1);
        positions.add(Position(
          bezeichnung:
              'Lichtbilder Zweitdrucke / ${anzAusf - 1} Mehrfertigungen (§ 12 Abs. 1 Nr. 2 JVEG)',
          menge: zweitCount.toDouble(),
          einheit: 'Stk',
          einzelpreis: defaultSatzFotoZweit,
          ustSatz: 19,
        ));
      }
    }

    // Post- und Telekommunikationspauschale (§ 12 Abs. 1 Nr. 5 / § 7 JVEG)
    if (honorarNetto > 0) {
      var porto = _round2(honorarNetto * 0.20);
      if (porto > 15.0) porto = 15.0;
      positions.add(Position(
        bezeichnung: 'Post- und Telekommunikationspauschale (§ 7 JVEG)',
        menge: 1,
        einheit: 'Pauschal',
        einzelpreis: porto,
        ustSatz: 19,
      ));
    }

    if (dateienCount > 0) {
      final gesamtPreis = dateienCount * 1.50;
      final isMax = gesamtPreis >= 5.00;
      positions.add(Position(
        bezeichnung: 'Elektronisch gespeicherte Dateien (§ 7 Abs. 3 JVEG)',
        menge: isMax ? 1 : dateienCount.toDouble(),
        einheit: isMax ? 'Pauschal (Maximalbetrag)' : 'Datei',
        einzelpreis: isMax ? 5.00 : 1.50,
        ustSatz: 19,
      ));
    }

    return positions;
  }

  /// Erzeugt die komplette JVEG-Liquidation direkt aus einer Akte:
  /// Honorar (§ 9 JVEG nach Honorargruppe) + Fahrtkosten/Auslagen (§ 5 JVEG) +
  /// Schreibauslagen & Lichtbilder inkl. Mehrfertigungen (§ 7 / § 12 JVEG)
  /// sowie Vorschuss-Verrechnungshinweis.
  Future<({List<Position> positionen, String? vorschussHinweis})>
      jvegKomplettLiquidationAusAkte({required int auftragId}) async {
    final auftrag = await (_db.select(_db.auftraege)
          ..where((t) => t.id.equals(auftragId)))
        .getSingleOrNull();
    final honorarPos = await honorarAusStunden(
      auftragId: auftragId,
      rechnungTyp: 'jveg',
    );
    final honorarNetto =
        honorarPos.fold<double>(0, (s, p) => s + p.nettoBetrag);
    final auslagenPos = await auslagenAusAuftrag(auftragId: auftragId);
    final gutachtenPos = await jvegAuslagenAusGutachten(
      auftragId: auftragId,
      honorarNetto: honorarNetto,
    );

    final alle = <Position>[
      ...honorarPos,
      ...auslagenPos,
      ...gutachtenPos,
    ];

    String? vorschussHinweis;
    final vorschuss = auftrag?.kostenvorschuss ?? 0;
    if (vorschuss > 0) {
      final vStr = vorschuss.toStringAsFixed(2).replaceAll('.', ',');
      vorschussHinweis =
          'Hinweis zur Abrechnung: Auf diese JVEG-Liquidation ist der angeforderte/gezahlte Auslagenvorschuss in Höhe von $vStr € anzurechnen.';
    }
    return (positionen: alle, vorschussHinweis: vorschussHinweis);
  }

  /// Liefert eine Vorlage typischer JVEG-Auslagen-Positionen (Mengen = 0,
  /// der User füllt die tatsächlichen Werte ein).
  Future<List<Position>> jvegAuslagenPreset() async {
    return const [
      Position(
        bezeichnung: 'Fahrtkosten (§ 5 JVEG)',
        menge: 0,
        einheit: 'km',
        einzelpreis: 0.42,
        ustSatz: 19,
      ),
      Position(
        bezeichnung: 'Schreibauslagen (§ 7 JVEG)',
        menge: 0,
        einheit: 'je 1000 Anschläge',
        einzelpreis: 1.80,
        ustSatz: 19,
      ),
      Position(
        bezeichnung: 'Lichtbilder (§ 7 JVEG)',
        menge: 0,
        einheit: 'Stk',
        einzelpreis: 2.00,
        ustSatz: 19,
      ),
      Position(
        bezeichnung: 'Kopien / Ausdrucke (§ 7 JVEG)',
        menge: 0,
        einheit: 'Seite',
        einzelpreis: 0.50,
        ustSatz: 19,
      ),
      Position(
        bezeichnung: 'Porto / Versand',
        menge: 1,
        einheit: 'Pauschal',
        einzelpreis: 0,
        ustSatz: 19,
      ),
    ];
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100;

  String _labelForArt(String art) => switch (art) {
        'fahrt' => 'Fahrtkosten',
        'schreibauslagen' => 'Schreibauslagen',
        'kopie_sw' => 'Kopien s/w',
        'kopie_farbe' => 'Kopien farbig',
        'lichtbilder' => 'Lichtbilder',
        'porto' => 'Porto / Versand',
        'fremdleistung' => 'Fremdleistung',
        _ => 'Auslage',
      };

  String _einheitForArt(String art) => switch (art) {
        'fahrt' => 'km',
        'schreibauslagen' => 'je 1000 Anschläge',
        'kopie_sw' || 'kopie_farbe' => 'Seite',
        'lichtbilder' => 'Stk',
        _ => 'Stk',
      };
}

class _AggPos {
  _AggPos({required this.taetigkeit, required this.satz});
  final String taetigkeit;
  final double satz;
  double menge = 0;
  int minuten = 0;
}

class _AggAuslage {
  _AggAuslage({
    required this.label,
    required this.einzelpreis,
    required this.einheit,
  });
  final String label;
  final double einzelpreis;
  final String einheit;
  double menge = 0;
}

final rechnungenPositionenHelperProvider =
    Provider<RechnungenPositionenHelper>((ref) {
  return RechnungenPositionenHelper(
    ref.watch(appDatabaseProvider),
    ref.watch(einstellungenRepositoryProvider),
  );
});
