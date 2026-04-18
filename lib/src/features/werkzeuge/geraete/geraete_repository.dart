import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class GeraeteRepository {
  GeraeteRepository(this._db);
  final AppDatabase _db;

  Stream<List<GeraeteData>> watchAll(
      {String query = '', bool nurAktiv = true}) {
    final q = _db.select(_db.geraete);
    if (nurAktiv) q.where((t) => t.aktiv.equals(true));
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where((t) =>
          t.bezeichnung.lower().like(like) |
          t.hersteller.lower().like(like) |
          t.modell.lower().like(like) |
          t.seriennummer.lower().like(like));
    }
    q.orderBy([(t) => OrderingTerm(expression: t.bezeichnung)]);
    return q.watch();
  }

  Future<int> upsert(GeraeteCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.geraete)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.geraete).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.geraete)..where((t) => t.id.equals(id))).go();
}

final geraeteRepositoryProvider = Provider<GeraeteRepository>((ref) {
  return GeraeteRepository(ref.watch(appDatabaseProvider));
});

class GeraeteFilter {
  final String query;
  final bool nurAktiv;
  const GeraeteFilter({this.query = '', this.nurAktiv = true});
  GeraeteFilter copyWith({String? query, bool? nurAktiv}) => GeraeteFilter(
        query: query ?? this.query,
        nurAktiv: nurAktiv ?? this.nurAktiv,
      );
}

final geraeteFilterProvider =
    StateProvider<GeraeteFilter>((ref) => const GeraeteFilter());

final geraeteListProvider = StreamProvider<List<GeraeteData>>((ref) {
  final f = ref.watch(geraeteFilterProvider);
  return ref
      .watch(geraeteRepositoryProvider)
      .watchAll(query: f.query, nurAktiv: f.nurAktiv);
});
