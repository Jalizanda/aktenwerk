import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class FotoWithAuftrag {
  final Foto foto;
  final AuftraegeData? auftrag;
  const FotoWithAuftrag(this.foto, this.auftrag);
}

class FotosRepository {
  FotosRepository(this._db);
  final AppDatabase _db;

  Stream<List<FotoWithAuftrag>> watchAll({int? auftragId}) {
    final q = _db.select(_db.fotos).join([
      leftOuterJoin(
          _db.auftraege, _db.auftraege.id.equalsExp(_db.fotos.auftragId)),
    ]);
    if (auftragId != null) {
      q.where(_db.fotos.auftragId.equals(auftragId));
    }
    q.orderBy([
      OrderingTerm(expression: _db.fotos.reihenfolge),
      OrderingTerm(
          expression: _db.fotos.aufnahmeAm, mode: OrderingMode.desc),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => FotoWithAuftrag(
            r.readTable(_db.fotos), r.readTableOrNull(_db.auftraege)))
        .toList());
  }

  Future<int> upsert(FotosCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.fotos)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.fotos).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.fotos)..where((t) => t.id.equals(id))).go();
}

final fotosRepositoryProvider = Provider<FotosRepository>((ref) {
  return FotosRepository(ref.watch(appDatabaseProvider));
});

final fotosAuftragFilterProvider = StateProvider<int?>((ref) => null);

final fotosListProvider = StreamProvider<List<FotoWithAuftrag>>((ref) {
  final auftragId = ref.watch(fotosAuftragFilterProvider);
  return ref.watch(fotosRepositoryProvider).watchAll(auftragId: auftragId);
});
