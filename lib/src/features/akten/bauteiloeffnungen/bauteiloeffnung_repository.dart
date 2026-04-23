import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class BauteiloeffnungRepository {
  BauteiloeffnungRepository(this._db);
  final AppDatabase _db;

  Stream<List<BauteiloeffnungenData>> watchByAkte(int auftragId) {
    return (_db.select(_db.bauteiloeffnungen)
          ..where((t) => t.auftragId.equals(auftragId))
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.datum, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<int> upsert(BauteiloeffnungenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.bauteiloeffnungen)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.bauteiloeffnungen).insert(entry);
  }

  Future<int> delete(int id) => (_db.delete(_db.bauteiloeffnungen)
        ..where((t) => t.id.equals(id)))
      .go();
}

final bauteiloeffnungRepositoryProvider =
    Provider<BauteiloeffnungRepository>((ref) {
  return BauteiloeffnungRepository(ref.watch(appDatabaseProvider));
});

final bauteiloeffnungenByAkteProvider = StreamProvider.family
    .autoDispose<List<BauteiloeffnungenData>, int>((ref, auftragId) {
  return ref
      .watch(bauteiloeffnungRepositoryProvider)
      .watchByAkte(auftragId);
});
