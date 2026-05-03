import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class VersandRepository {
  VersandRepository(this._db);
  final AppDatabase _db;

  Stream<List<VersandData>> watchByAuftrag(int auftragId) {
    return (_db.select(_db.versand)
          ..where((t) => t.auftragId.equals(auftragId))
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.datum, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<int> upsert(VersandCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.versand)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.versand).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.versand)..where((t) => t.id.equals(id))).go();
}

final versandRepositoryProvider = Provider<VersandRepository>((ref) {
  return VersandRepository(ref.watch(appDatabaseProvider));
});

final versandByAuftragProvider = StreamProvider.autoDispose
    .family<List<VersandData>, int>((ref, auftragId) {
  return ref.watch(versandRepositoryProvider).watchByAuftrag(auftragId);
});
