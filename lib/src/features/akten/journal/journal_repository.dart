import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class JournalRepository {
  JournalRepository(this._db);
  final AppDatabase _db;

  Stream<List<JournaleintraegeData>> watchByAkte(int auftragId) {
    return (_db.select(_db.journaleintraege)
          ..where((t) => t.auftragId.equals(auftragId))
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.zeitpunkt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<int> upsert(JournaleintraegeCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.journaleintraege)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.journaleintraege).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.journaleintraege)..where((t) => t.id.equals(id))).go();
}

final journalRepositoryProvider = Provider<JournalRepository>((ref) {
  return JournalRepository(ref.watch(appDatabaseProvider));
});

final journalByAkteProvider = StreamProvider.family
    .autoDispose<List<JournaleintraegeData>, int>((ref, auftragId) {
  return ref.watch(journalRepositoryProvider).watchByAkte(auftragId);
});
