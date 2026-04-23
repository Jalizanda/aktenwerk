import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class UebergabeRepository {
  UebergabeRepository(this._db);
  final AppDatabase _db;

  Stream<List<UebergabenData>> watchByAkte(int auftragId) {
    return (_db.select(_db.uebergaben)
          ..where((t) => t.auftragId.equals(auftragId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.datum, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<int> upsert(UebergabenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.uebergaben)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.uebergaben).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.uebergaben)..where((t) => t.id.equals(id))).go();
}

final uebergabeRepositoryProvider = Provider<UebergabeRepository>((ref) {
  return UebergabeRepository(ref.watch(appDatabaseProvider));
});

final uebergabenByAkteProvider = StreamProvider.family
    .autoDispose<List<UebergabenData>, int>((ref, auftragId) {
  return ref.watch(uebergabeRepositoryProvider).watchByAkte(auftragId);
});
