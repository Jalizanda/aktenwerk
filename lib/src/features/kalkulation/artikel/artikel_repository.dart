import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class ArtikelRepository {
  ArtikelRepository(this._db);
  final AppDatabase _db;

  Stream<List<ArtikelData>> watchAll({String query = '', bool nurAktiv = true}) {
    final q = _db.select(_db.artikel);
    if (nurAktiv) q.where((t) => t.aktiv.equals(true));
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where((t) =>
          t.bezeichnung.lower().like(like) |
          t.nummer.lower().like(like) |
          t.kategorie.lower().like(like));
    }
    q.orderBy([(t) => OrderingTerm(expression: t.bezeichnung)]);
    return q.watch();
  }

  Future<int> upsert(ArtikelCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.artikel)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.artikel).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.artikel)..where((t) => t.id.equals(id))).go();
}

final artikelRepositoryProvider = Provider<ArtikelRepository>((ref) {
  return ArtikelRepository(ref.watch(appDatabaseProvider));
});

class ArtikelFilter {
  final String query;
  final bool nurAktiv;
  const ArtikelFilter({this.query = '', this.nurAktiv = true});
  ArtikelFilter copyWith({String? query, bool? nurAktiv}) => ArtikelFilter(
        query: query ?? this.query,
        nurAktiv: nurAktiv ?? this.nurAktiv,
      );
  bool get isActive => query.isNotEmpty || !nurAktiv;
}

final artikelFilterProvider =
    StateProvider<ArtikelFilter>((ref) => const ArtikelFilter());

final artikelListProvider = StreamProvider<List<ArtikelData>>((ref) {
  final f = ref.watch(artikelFilterProvider);
  return ref
      .watch(artikelRepositoryProvider)
      .watchAll(query: f.query, nurAktiv: f.nurAktiv);
});
