import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../einstellungen/einstellungen_repository.dart';

class KontenRepository {
  KontenRepository(this._db);
  final AppDatabase _db;

  Stream<List<KontenData>> watchAll({String skr = 'SKR03'}) {
    return (_db.select(_db.konten)
          ..where((t) => t.skr.equals(skr))
          ..orderBy([(t) => OrderingTerm(expression: t.nummer)]))
        .watch();
  }

  Future<List<KontenData>> allFor(String skr) =>
      (_db.select(_db.konten)..where((t) => t.skr.equals(skr)))
          .get();

  Future<int> upsert(KontenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.konten)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.konten).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.konten)..where((t) => t.id.equals(id))).go();

  Future<void> seedDefaults() async {
    final existing = await _db.select(_db.konten).get();
    if (existing.isNotEmpty) return;
    for (final k in _defaultSkr03) {
      await _db.into(_db.konten).insert(KontenCompanion.insert(
            nummer: k.$1,
            bezeichnung: k.$2,
            skr: const Value('SKR03'),
            kategorie: Value(k.$3),
            ustSatz: Value(k.$4),
          ));
    }
    for (final k in _defaultSkr04) {
      await _db.into(_db.konten).insert(KontenCompanion.insert(
            nummer: k.$1,
            bezeichnung: k.$2,
            skr: const Value('SKR04'),
            kategorie: Value(k.$3),
            ustSatz: Value(k.$4),
          ));
    }
  }

  /// Liefert das Erlöskonto, das zum USt-Satz passt. Wenn kein passendes
  /// Konto gefunden wird, `null`.
  Future<String?> erloeskontoFor(double? ustSatz, String skr) async {
    final list = await allFor(skr);
    final ertraege = list
        .where((k) => k.kategorie == 'ertrag' && k.aktiv)
        .toList();
    if (ertraege.isEmpty) return null;
    if (ustSatz == null) return ertraege.first.nummer;
    // Nach USt-Satz filtern (exakter Match bevorzugt).
    final match = ertraege.firstWhere(
        (k) => (k.ustSatz ?? -1) == ustSatz,
        orElse: () => ertraege.firstWhere(
            (k) => (k.ustSatz ?? 0) > 0, orElse: () => ertraege.first));
    return match.nummer;
  }
}

/// Typische Erlös- und Aufwandskonten für SKR03 (vereinfacht).
const _defaultSkr03 = <(String, String, String, double?)>[
  ('8400', 'Erlöse 19 % USt', 'ertrag', 19.0),
  ('8300', 'Erlöse 7 % USt', 'ertrag', 7.0),
  ('8120', 'Steuerfreie Umsätze § 4 Nr. 1 UStG', 'ertrag', 0.0),
  ('8200', 'Erlöse (allgemein)', 'ertrag', null),
  ('3300', 'Wareneingang 19 % VSt', 'aufwand', 19.0),
  ('4100', 'Löhne & Gehälter', 'aufwand', null),
  ('4120', 'Bezüge des Geschäftsführers', 'aufwand', null),
  ('4210', 'Miete / Pacht', 'aufwand', 19.0),
  ('4360', 'Versicherungen', 'aufwand', 0.0),
  ('4380', 'Beiträge', 'aufwand', 0.0),
  ('4400', 'Kfz-Kosten', 'aufwand', 19.0),
  ('4600', 'Werbekosten', 'aufwand', 19.0),
  ('4650', 'Bewirtungskosten', 'aufwand', 19.0),
  ('4910', 'Porto', 'aufwand', 0.0),
  ('4920', 'Telefon / Internet', 'aufwand', 19.0),
  ('4930', 'Bürobedarf', 'aufwand', 19.0),
  ('4940', 'Zeitschriften / Bücher', 'aufwand', 7.0),
  ('4945', 'Fortbildungskosten', 'aufwand', 19.0),
  ('4980', 'Werkzeuge / Kleingeräte', 'aufwand', 19.0),
  ('1200', 'Bank', 'finanz', null),
  ('1000', 'Kasse', 'finanz', null),
  ('1770', 'Umsatzsteuer 19 %', 'umsatzsteuer', 19.0),
  ('1771', 'Umsatzsteuer 7 %', 'umsatzsteuer', 7.0),
  ('1576', 'Abziehbare Vorsteuer 19 %', 'umsatzsteuer', 19.0),
  ('1571', 'Abziehbare Vorsteuer 7 %', 'umsatzsteuer', 7.0),
];

/// Typische Erlös- und Aufwandskonten für SKR04 (vereinfacht).
const _defaultSkr04 = <(String, String, String, double?)>[
  ('4400', 'Erlöse 19 % USt', 'ertrag', 19.0),
  ('4300', 'Erlöse 7 % USt', 'ertrag', 7.0),
  ('4120', 'Steuerfreie Umsätze § 4 Nr. 1 UStG', 'ertrag', 0.0),
  ('5300', 'Wareneingang 19 % VSt', 'aufwand', 19.0),
  ('6000', 'Löhne & Gehälter', 'aufwand', null),
  ('6020', 'Bezüge des Geschäftsführers', 'aufwand', null),
  ('6310', 'Miete / Pacht', 'aufwand', 19.0),
  ('6400', 'Versicherungen', 'aufwand', 0.0),
  ('6420', 'Beiträge', 'aufwand', 0.0),
  ('6520', 'Kfz-Kosten', 'aufwand', 19.0),
  ('6600', 'Werbekosten', 'aufwand', 19.0),
  ('6640', 'Bewirtungskosten', 'aufwand', 19.0),
  ('6800', 'Porto', 'aufwand', 0.0),
  ('6805', 'Telefon / Internet', 'aufwand', 19.0),
  ('6815', 'Bürobedarf', 'aufwand', 19.0),
  ('6820', 'Zeitschriften / Bücher', 'aufwand', 7.0),
  ('6821', 'Fortbildungskosten', 'aufwand', 19.0),
  ('6845', 'Werkzeuge / Kleingeräte', 'aufwand', 19.0),
  ('1800', 'Bank', 'finanz', null),
  ('1600', 'Kasse', 'finanz', null),
  ('3806', 'Umsatzsteuer 19 %', 'umsatzsteuer', 19.0),
  ('3801', 'Umsatzsteuer 7 %', 'umsatzsteuer', 7.0),
  ('1406', 'Abziehbare Vorsteuer 19 %', 'umsatzsteuer', 19.0),
  ('1401', 'Abziehbare Vorsteuer 7 %', 'umsatzsteuer', 7.0),
];

final kontenRepositoryProvider = Provider<KontenRepository>((ref) {
  return KontenRepository(ref.watch(appDatabaseProvider));
});

/// Aktueller Kontenrahmen aus den Einstellungen (SKR03 oder SKR04).
final aktuellerSkrProvider = Provider<String>((ref) {
  final settings = ref.watch(einstellungenProvider).valueOrNull;
  return settings?[SettingsKeys.datevKontenrahmen] ?? 'SKR03';
});

final kontenListProvider = StreamProvider<List<KontenData>>((ref) {
  final skr = ref.watch(aktuellerSkrProvider);
  return ref.watch(kontenRepositoryProvider).watchAll(skr: skr);
});
