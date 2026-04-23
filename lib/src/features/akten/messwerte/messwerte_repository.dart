import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class MesswerteRepository {
  MesswerteRepository(this._db);
  final AppDatabase _db;

  Stream<List<MesswerteData>> watchByAkte(int auftragId) {
    return (_db.select(_db.messwerte)
          ..where((t) => t.auftragId.equals(auftragId))
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.zeitpunkt, mode: OrderingMode.asc),
          ]))
        .watch();
  }

  Future<int> insert(MesswerteCompanion entry) =>
      _db.into(_db.messwerte).insert(entry);

  Future<int> delete(int id) =>
      (_db.delete(_db.messwerte)..where((t) => t.id.equals(id))).go();
}

final messwerteRepositoryProvider = Provider<MesswerteRepository>((ref) {
  return MesswerteRepository(ref.watch(appDatabaseProvider));
});

final messwerteByAkteProvider = StreamProvider.family
    .autoDispose<List<MesswerteData>, int>((ref, auftragId) {
  return ref.watch(messwerteRepositoryProvider).watchByAkte(auftragId);
});
