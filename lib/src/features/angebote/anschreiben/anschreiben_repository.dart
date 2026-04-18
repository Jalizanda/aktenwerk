import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class AnschreibenWithKunde {
  final AnschreibenData anschreiben;
  final KundenData? kunde;
  final AuftraegeData? auftrag;
  const AnschreibenWithKunde(this.anschreiben, this.kunde, this.auftrag);
}

class AnschreibenRepository {
  AnschreibenRepository(this._db);
  final AppDatabase _db;

  Stream<List<AnschreibenWithKunde>> watchAll({String query = ''}) {
    final q = _db.select(_db.anschreiben).join([
      leftOuterJoin(
          _db.kunden, _db.kunden.id.equalsExp(_db.anschreiben.kundeId)),
      leftOuterJoin(_db.auftraege,
          _db.auftraege.id.equalsExp(_db.anschreiben.auftragId)),
    ]);
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where(_db.anschreiben.betreff.lower().like(like) |
          _db.kunden.firma.lower().like(like) |
          _db.kunden.nachname.lower().like(like) |
          _db.auftraege.aktenzeichen.lower().like(like));
    }
    q.orderBy([
      OrderingTerm(
          expression: _db.anschreiben.datum, mode: OrderingMode.desc),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => AnschreibenWithKunde(
              r.readTable(_db.anschreiben),
              r.readTableOrNull(_db.kunden),
              r.readTableOrNull(_db.auftraege),
            ))
        .toList());
  }

  Future<int> upsert(AnschreibenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.anschreiben)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.anschreiben).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.anschreiben)..where((t) => t.id.equals(id))).go();
}

final anschreibenRepositoryProvider = Provider<AnschreibenRepository>((ref) {
  return AnschreibenRepository(ref.watch(appDatabaseProvider));
});

final anschreibenQueryProvider = StateProvider<String>((ref) => '');

final anschreibenListProvider =
    StreamProvider<List<AnschreibenWithKunde>>((ref) {
  final q = ref.watch(anschreibenQueryProvider);
  return ref.watch(anschreibenRepositoryProvider).watchAll(query: q);
});
