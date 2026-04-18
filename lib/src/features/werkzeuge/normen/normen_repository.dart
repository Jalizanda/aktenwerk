import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class NormenRepository {
  NormenRepository(this._db);
  final AppDatabase _db;

  Stream<List<NormenData>> watchAll(
      {String query = '', bool nurFavoriten = false}) {
    final q = _db.select(_db.normen);
    if (nurFavoriten) q.where((t) => t.favorit.equals(true));
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where((t) =>
          t.nummer.lower().like(like) |
          t.titel.lower().like(like) |
          t.kategorie.lower().like(like));
    }
    q.orderBy([(t) => OrderingTerm(expression: t.nummer)]);
    return q.watch();
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
}

final normenRepositoryProvider = Provider<NormenRepository>((ref) {
  return NormenRepository(ref.watch(appDatabaseProvider));
});

class NormenFilter {
  final String query;
  final bool nurFavoriten;
  const NormenFilter({this.query = '', this.nurFavoriten = false});
  NormenFilter copyWith({String? query, bool? nurFavoriten}) =>
      NormenFilter(
        query: query ?? this.query,
        nurFavoriten: nurFavoriten ?? this.nurFavoriten,
      );
}

final normenFilterProvider =
    StateProvider<NormenFilter>((ref) => const NormenFilter());

final normenListProvider = StreamProvider<List<NormenData>>((ref) {
  final f = ref.watch(normenFilterProvider);
  return ref
      .watch(normenRepositoryProvider)
      .watchAll(query: f.query, nurFavoriten: f.nurFavoriten);
});
