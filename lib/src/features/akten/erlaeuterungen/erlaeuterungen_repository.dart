import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class ErlaeuterungWithAuftrag {
  final ErlaeuterungenData eintrag;
  final AuftraegeData? auftrag;
  const ErlaeuterungWithAuftrag(this.eintrag, this.auftrag);
}

class ErlaeuterungenRepository {
  ErlaeuterungenRepository(this._db);
  final AppDatabase _db;

  Stream<List<ErlaeuterungWithAuftrag>> watchAll({String query = ''}) {
    final q = _db.select(_db.erlaeuterungen).join([
      leftOuterJoin(_db.auftraege,
          _db.auftraege.id.equalsExp(_db.erlaeuterungen.auftragId)),
    ]);
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where(_db.erlaeuterungen.gericht.lower().like(like) |
          _db.erlaeuterungen.richter.lower().like(like) |
          _db.auftraege.aktenzeichen.lower().like(like));
    }
    q.orderBy([
      OrderingTerm(
          expression: _db.erlaeuterungen.terminAm,
          mode: OrderingMode.desc),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => ErlaeuterungWithAuftrag(r.readTable(_db.erlaeuterungen),
            r.readTableOrNull(_db.auftraege)))
        .toList());
  }

  Future<int> upsert(ErlaeuterungenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.erlaeuterungen)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.erlaeuterungen).insert(entry);
  }

  Future<int> delete(int id) => (_db.delete(_db.erlaeuterungen)
        ..where((t) => t.id.equals(id)))
      .go();
}

final erlaeuterungenRepositoryProvider =
    Provider<ErlaeuterungenRepository>((ref) {
  return ErlaeuterungenRepository(ref.watch(appDatabaseProvider));
});

final erlaeuterungenQueryProvider = StateProvider<String>((ref) => '');

final erlaeuterungenListProvider =
    StreamProvider<List<ErlaeuterungWithAuftrag>>((ref) {
  final q = ref.watch(erlaeuterungenQueryProvider);
  return ref.watch(erlaeuterungenRepositoryProvider).watchAll(query: q);
});
