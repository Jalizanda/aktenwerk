import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class ProtokolleRepository {
  ProtokolleRepository(this._db);
  final AppDatabase _db;

  Stream<List<ProtokolleData>> watchForAuftrag(int auftragId) {
    return (_db.select(_db.protokolle)
          ..where((t) => t.auftragId.equals(auftragId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.datum, mode: OrderingMode.desc)
          ]))
        .watch();
  }

  Future<int> upsert(ProtokolleCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.protokolle)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.protokolle).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.protokolle)..where((t) => t.id.equals(id))).go();

  Future<ProtokolleData?> byId(int id) =>
      (_db.select(_db.protokolle)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
}

final protokolleRepositoryProvider = Provider<ProtokolleRepository>((ref) {
  return ProtokolleRepository(ref.watch(appDatabaseProvider));
});

final protokolleForAuftragProvider =
    StreamProvider.family<List<ProtokolleData>, int>((ref, auftragId) {
  return ref.watch(protokolleRepositoryProvider).watchForAuftrag(auftragId);
});
