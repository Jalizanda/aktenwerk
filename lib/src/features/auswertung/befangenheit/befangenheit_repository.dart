import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Verwaltet die manuell gepflegten Einträge im Befangenheits-Register.
/// Automatisch aggregierte Einträge (Auftraggeber, Gericht, Richter aus
/// den Akten) werden im UI direkt aus den jeweiligen Quellen geladen
/// und mit der manuellen Liste zusammengeführt.
class BefangenheitRepository {
  BefangenheitRepository(this._db);
  final AppDatabase _db;

  Stream<List<BefangenheitsEintraegeData>> watchAll() {
    final q = _db.select(_db.befangenheitsEintraege)
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    return q.watch();
  }

  Future<int> upsert(BefangenheitsEintraegeCompanion entry) async {
    final hasId = entry.id.present;
    if (!hasId) {
      return _db.into(_db.befangenheitsEintraege).insert(
            entry.copyWith(updatedAt: Value(DateTime.now())),
          );
    }
    await (_db.update(_db.befangenheitsEintraege)
          ..where((t) => t.id.equals(entry.id.value)))
        .write(entry.copyWith(updatedAt: Value(DateTime.now())));
    return entry.id.value;
  }

  Future<void> delete(int id) async {
    await (_db.delete(_db.befangenheitsEintraege)
          ..where((t) => t.id.equals(id)))
        .go();
  }
}

final befangenheitRepositoryProvider =
    Provider<BefangenheitRepository>((ref) {
  return BefangenheitRepository(ref.watch(appDatabaseProvider));
});

final befangenheitsEintraegeProvider =
    StreamProvider<List<BefangenheitsEintraegeData>>((ref) {
  return ref.watch(befangenheitRepositoryProvider).watchAll();
});
