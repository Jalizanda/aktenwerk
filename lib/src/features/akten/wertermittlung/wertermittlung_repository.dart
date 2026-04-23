import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class WertermittlungRepository {
  WertermittlungRepository(this._db);
  final AppDatabase _db;

  Stream<WertermittlungenData?> watchForAkte(int auftragId) {
    return (_db.select(_db.wertermittlungen)
          ..where((t) => t.auftragId.equals(auftragId))
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<int> upsert(WertermittlungenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.wertermittlungen)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.wertermittlungen).insert(entry);
  }

  Future<int> delete(int id) => (_db.delete(_db.wertermittlungen)
        ..where((t) => t.id.equals(id)))
      .go();
}

final wertermittlungRepositoryProvider =
    Provider<WertermittlungRepository>((ref) {
  return WertermittlungRepository(ref.watch(appDatabaseProvider));
});

final wertermittlungByAkteProvider = StreamProvider.family
    .autoDispose<WertermittlungenData?, int>((ref, auftragId) {
  return ref.watch(wertermittlungRepositoryProvider).watchForAkte(auftragId);
});
