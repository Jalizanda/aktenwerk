import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class FortbildungenRepository {
  FortbildungenRepository(this._db);
  final AppDatabase _db;

  Stream<List<FortbildungenData>> watchAll({String query = '', int? jahr}) {
    final q = _db.select(_db.fortbildungen);
    if (jahr != null) {
      q.where((t) =>
          t.datumVon.year.equals(jahr) | t.datumBis.year.equals(jahr));
    }
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where((t) =>
          t.titel.lower().like(like) |
          t.veranstalter.lower().like(like) |
          t.thema.lower().like(like));
    }
    q.orderBy([
      (t) => OrderingTerm(expression: t.datumVon, mode: OrderingMode.desc)
    ]);
    return q.watch();
  }

  Future<int> upsert(FortbildungenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.fortbildungen)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.fortbildungen).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.fortbildungen)..where((t) => t.id.equals(id))).go();

  /// Summe Fortbildungsstunden pro Kalenderjahr.
  Future<Map<int, double>> summenProJahr() async {
    final rows = await _db.select(_db.fortbildungen).get();
    final out = <int, double>{};
    for (final r in rows) {
      final jahr = (r.datumVon ?? r.datumBis)?.year;
      if (jahr == null) continue;
      out[jahr] = (out[jahr] ?? 0) + r.stunden;
    }
    return out;
  }
}

final fortbildungenRepositoryProvider =
    Provider<FortbildungenRepository>((ref) {
  return FortbildungenRepository(ref.watch(appDatabaseProvider));
});

class FortbildungenFilter {
  final String query;
  final int? jahr;
  const FortbildungenFilter({this.query = '', this.jahr});
  FortbildungenFilter copyWith(
          {String? query, int? jahr, bool clearJahr = false}) =>
      FortbildungenFilter(
        query: query ?? this.query,
        jahr: clearJahr ? null : (jahr ?? this.jahr),
      );
}

final fortbildungenFilterProvider =
    StateProvider<FortbildungenFilter>((ref) => const FortbildungenFilter());

final fortbildungenListProvider =
    StreamProvider<List<FortbildungenData>>((ref) {
  final f = ref.watch(fortbildungenFilterProvider);
  return ref
      .watch(fortbildungenRepositoryProvider)
      .watchAll(query: f.query, jahr: f.jahr);
});

final fortbildungenSummenProvider =
    FutureProvider<Map<int, double>>((ref) async {
  ref.watch(fortbildungenListProvider);
  return ref.watch(fortbildungenRepositoryProvider).summenProJahr();
});
