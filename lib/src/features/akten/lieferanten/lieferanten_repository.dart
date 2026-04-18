import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class LieferantenRepository {
  LieferantenRepository(this._db);
  final AppDatabase _db;

  Stream<List<LieferantenData>> watchAll({String query = ''}) {
    final q = _db.select(_db.lieferanten);
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where((t) =>
          t.firma.lower().like(like) |
          t.ansprechpartner.lower().like(like) |
          t.ort.lower().like(like) |
          t.kategorie.lower().like(like) |
          t.email.lower().like(like));
    }
    q.orderBy([(t) => OrderingTerm(expression: t.firma)]);
    return q.watch();
  }

  Future<int> upsert(LieferantenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.lieferanten)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.lieferanten).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.lieferanten)..where((t) => t.id.equals(id))).go();
}

final lieferantenRepositoryProvider = Provider<LieferantenRepository>((ref) {
  return LieferantenRepository(ref.watch(appDatabaseProvider));
});

final lieferantenQueryProvider = StateProvider<String>((ref) => '');

final lieferantenListProvider =
    StreamProvider<List<LieferantenData>>((ref) {
  final q = ref.watch(lieferantenQueryProvider);
  return ref.watch(lieferantenRepositoryProvider).watchAll(query: q);
});
