import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class QualifikationenRepository {
  QualifikationenRepository(this._db);
  final AppDatabase _db;

  Stream<List<QualifikationenData>> watchAll() {
    return (_db.select(_db.qualifikationen)
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.gueltigBis, mode: OrderingMode.asc),
            (t) => OrderingTerm(expression: t.titel),
          ]))
        .watch();
  }

  Future<int> upsert(QualifikationenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.qualifikationen)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.qualifikationen).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.qualifikationen)..where((t) => t.id.equals(id))).go();
}

final qualifikationenRepositoryProvider =
    Provider<QualifikationenRepository>((ref) {
  return QualifikationenRepository(ref.watch(appDatabaseProvider));
});

final qualifikationenListProvider =
    StreamProvider<List<QualifikationenData>>((ref) {
  return ref.watch(qualifikationenRepositoryProvider).watchAll();
});
