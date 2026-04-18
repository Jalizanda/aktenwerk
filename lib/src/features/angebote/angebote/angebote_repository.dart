import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class AngebotWithKunde {
  final AngeboteData angebot;
  final KundenData? kunde;
  const AngebotWithKunde(this.angebot, this.kunde);
}

class AngeboteRepository {
  AngeboteRepository(this._db);
  final AppDatabase _db;

  Stream<List<AngebotWithKunde>> watchAll(
      {String query = '', String? status}) {
    final q = _db.select(_db.angebote).join([
      leftOuterJoin(
          _db.kunden, _db.kunden.id.equalsExp(_db.angebote.kundeId)),
    ]);
    if (status != null) q.where(_db.angebote.status.equals(status));
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where(_db.angebote.angebotsnummer.lower().like(like) |
          _db.angebote.betreff.lower().like(like) |
          _db.kunden.firma.lower().like(like) |
          _db.kunden.nachname.lower().like(like));
    }
    q.orderBy([
      OrderingTerm(
          expression: _db.angebote.datum, mode: OrderingMode.desc),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => AngebotWithKunde(
              r.readTable(_db.angebote),
              r.readTableOrNull(_db.kunden),
            ))
        .toList());
  }

  Future<int> upsert(AngeboteCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.angebote)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.angebote).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.angebote)..where((t) => t.id.equals(id))).go();

  Future<int> nextSequenz() async {
    final row = await (_db.selectOnly(_db.angebote)
          ..addColumns([_db.angebote.id.max()]))
        .getSingle();
    return (row.read(_db.angebote.id.max()) ?? 0) + 1;
  }
}

final angeboteRepositoryProvider = Provider<AngeboteRepository>((ref) {
  return AngeboteRepository(ref.watch(appDatabaseProvider));
});

class AngeboteFilter {
  final String query;
  final String? status;
  const AngeboteFilter({this.query = '', this.status});
  AngeboteFilter copyWith(
          {String? query, String? status, bool clearStatus = false}) =>
      AngeboteFilter(
        query: query ?? this.query,
        status: clearStatus ? null : (status ?? this.status),
      );
}

final angeboteFilterProvider =
    StateProvider<AngeboteFilter>((ref) => const AngeboteFilter());

final angeboteListProvider = StreamProvider<List<AngebotWithKunde>>((ref) {
  final f = ref.watch(angeboteFilterProvider);
  return ref
      .watch(angeboteRepositoryProvider)
      .watchAll(query: f.query, status: f.status);
});
