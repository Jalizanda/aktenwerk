import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class MaengelRepository {
  MaengelRepository(this._db);
  final AppDatabase _db;

  Stream<List<MaengelData>> watchByAkte(int auftragId) {
    return (_db.select(_db.maengel)
          ..where((t) => t.auftragId.equals(auftragId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.nummer),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .watch();
  }

  Future<int> upsert(MaengelCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.maengel)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.maengel).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.maengel)..where((t) => t.id.equals(id))).go();

  /// Erzeugt eine neue, laufende Mangel-Nummer innerhalb der Akte
  /// ("M-01", "M-02" …).
  Future<String> nextNummer(int auftragId) async {
    final rows = await (_db.select(_db.maengel)
          ..where((t) => t.auftragId.equals(auftragId)))
        .get();
    final n = rows.length + 1;
    return 'M-${n.toString().padLeft(2, '0')}';
  }
}

final maengelRepositoryProvider = Provider<MaengelRepository>((ref) {
  return MaengelRepository(ref.watch(appDatabaseProvider));
});

final maengelByAkteProvider = StreamProvider.family
    .autoDispose<List<MaengelData>, int>((ref, auftragId) {
  return ref.watch(maengelRepositoryProvider).watchByAkte(auftragId);
});
