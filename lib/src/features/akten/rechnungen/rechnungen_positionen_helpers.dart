import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../features/system/einstellungen/einstellungen_repository.dart';
import '../../../shared/positionen/position_model.dart';

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
    final defaultSatz =
        double.tryParse(await _settings.getOr(SettingsKeys.standardStundensatz, '140')) ?? 140;
    final fallback = auftrag?.stundensatz ?? defaultSatz;

    final grouped = <String, _AggPos>{};
    for (final s in rows) {
      final taetigkeit = (s.taetigkeit == null || s.taetigkeit!.trim().isEmpty)
          ? 'Tätigkeit'
          : s.taetigkeit!.trim();
      final satz = s.satz ?? fallback;
      final stunden = s.minuten / 60.0;
      final key = '$taetigkeit|${satz.toStringAsFixed(2)}';
      final agg = grouped.putIfAbsent(
          key, () => _AggPos(taetigkeit: taetigkeit, satz: satz));
      agg.menge += stunden;
    }
    return grouped.values
        .map((a) => Position(
              bezeichnung: a.taetigkeit,
              menge: _round2(a.menge),
              einheit: 'h',
              einzelpreis: _round2(a.satz),
              ustSatz: 19,
            ))
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
