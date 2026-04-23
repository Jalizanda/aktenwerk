import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Vordefinierte Kategorien (Bausachverständige).
const List<String> normKategorien = [
  'Norm',
  'Richtlinie',
  'Merkblatt',
  'Gesetz',
  'Verordnung',
  'Leitfaden',
  'Fachregel',
  'Rechtsprechung',
  'Sonstiges',
];

const List<String> aktualitaetStatusWerte = [
  'aktuell',
  'veraltet',
  'unbekannt',
];

class NormenRepository {
  NormenRepository(this._db);
  final AppDatabase _db;

  Stream<List<NormenData>> watchAll({
    String query = '',
    bool nurFavoriten = false,
    String? gewerk,
    String? kategorie,
    String? aktualitaetStatus,
  }) {
    final q = _db.select(_db.normen);
    q.where((t) => t.auftragId.isNull());
    if (nurFavoriten) q.where((t) => t.favorit.equals(true));
    if (gewerk != null && gewerk.isNotEmpty) {
      q.where((t) => t.gewerk.equals(gewerk));
    }
    if (kategorie != null && kategorie.isNotEmpty) {
      q.where((t) => t.kategorie.equals(kategorie));
    }
    if (aktualitaetStatus != null && aktualitaetStatus.isNotEmpty) {
      if (aktualitaetStatus == '_unbekannt_oder_leer') {
        // Spezialfall: Status-Feld null ODER explizit "unbekannt"
        q.where((t) =>
            t.aktualitaetStatus.isNull() |
            t.aktualitaetStatus.equals('unbekannt'));
      } else {
        q.where((t) => t.aktualitaetStatus.equals(aktualitaetStatus));
      }
    }
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where((t) =>
          t.nummer.lower().like(like) |
          t.titel.lower().like(like) |
          t.kategorie.lower().like(like) |
          t.gewerk.lower().like(like));
    }
    q.orderBy([(t) => OrderingTerm(expression: t.nummer)]);
    return q.watch();
  }

  /// Liefert alle im Katalog vorkommenden Gewerke (distinct, sortiert).
  Future<List<String>> distinctGewerke() async {
    final rows = await (_db.selectOnly(_db.normen, distinct: true)
          ..addColumns([_db.normen.gewerk])
          ..where(_db.normen.gewerk.isNotNull() &
              _db.normen.gewerk.length.isBiggerThanValue(0))
          ..where(_db.normen.auftragId.isNull()))
        .get();
    return rows
        .map((r) => r.read(_db.normen.gewerk))
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Future<int> upsert(NormenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.normen)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.normen).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.normen)..where((t) => t.id.equals(id))).go();

  Future<void> toggleFavorit(int id, bool value) async {
    await (_db.update(_db.normen)..where((t) => t.id.equals(id)))
        .write(NormenCompanion(favorit: Value(value)));
  }

  Future<void> setAktiv(int id, bool value) async {
    await (_db.update(_db.normen)..where((t) => t.id.equals(id)))
        .write(NormenCompanion(
            aktiv: Value(value), updatedAt: Value(DateTime.now())));
  }

  Future<void> setAktualitaet(
    int id, {
    required String status,
    String? quelle,
    String? notiz,
  }) async {
    await (_db.update(_db.normen)..where((t) => t.id.equals(id))).write(
      NormenCompanion(
        aktualitaetStatus: Value(status),
        aktualitaetGeprueftAm: Value(DateTime.now()),
        aktualitaetQuelle:
            quelle == null || quelle.trim().isEmpty ? const Value(null) : Value(quelle),
        aktualitaetNotiz:
            notiz == null || notiz.trim().isEmpty ? const Value(null) : Value(notiz),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

final normenRepositoryProvider = Provider<NormenRepository>((ref) {
  return NormenRepository(ref.watch(appDatabaseProvider));
});

class NormenFilter {
  final String query;
  final bool nurFavoriten;
  final String? gewerk;
  final String? kategorie;

  /// Aktualitäts-Filter: null = egal, 'aktuell' / 'veraltet' /
  /// 'unbekannt' / '_unbekannt_oder_leer' für "noch nicht geprüft".
  final String? aktualitaetStatus;

  const NormenFilter({
    this.query = '',
    this.nurFavoriten = false,
    this.gewerk,
    this.kategorie,
    this.aktualitaetStatus,
  });
  NormenFilter copyWith({
    String? query,
    bool? nurFavoriten,
    // Nullable-Overrides: wenn man "Alle Gewerke/Kategorien/Status"
    // wählen will, wird `null` an `copyWith` übergeben — dafür brauchen
    // wir explizite Sentinels.
    Object? gewerkOverride = _sentinel,
    Object? kategorieOverride = _sentinel,
    Object? aktualitaetStatusOverride = _sentinel,
  }) =>
      NormenFilter(
        query: query ?? this.query,
        nurFavoriten: nurFavoriten ?? this.nurFavoriten,
        gewerk: identical(gewerkOverride, _sentinel)
            ? gewerk
            : gewerkOverride as String?,
        kategorie: identical(kategorieOverride, _sentinel)
            ? kategorie
            : kategorieOverride as String?,
        aktualitaetStatus: identical(aktualitaetStatusOverride, _sentinel)
            ? aktualitaetStatus
            : aktualitaetStatusOverride as String?,
      );
}

const _sentinel = Object();

final normenFilterProvider =
    StateProvider<NormenFilter>((ref) => const NormenFilter());

final normenListProvider = StreamProvider<List<NormenData>>((ref) {
  final f = ref.watch(normenFilterProvider);
  return ref
      .watch(normenRepositoryProvider)
      .watchAll(
        query: f.query,
        nurFavoriten: f.nurFavoriten,
        gewerk: f.gewerk,
        kategorie: f.kategorie,
        aktualitaetStatus: f.aktualitaetStatus,
      );
});

/// Liste aller im Katalog vorhandenen Gewerke.
final normenGewerkeProvider = FutureProvider<List<String>>((ref) async {
  // Bei Änderungen an der Normen-Liste automatisch neu berechnen.
  ref.watch(normenListProvider);
  return ref.watch(normenRepositoryProvider).distinctGewerke();
});
