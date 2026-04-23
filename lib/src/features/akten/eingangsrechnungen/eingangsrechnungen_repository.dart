import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class EingangsrechnungWithAuftrag {
  final EingangsrechnungenData rechnung;
  final AuftraegeData? auftrag;
  const EingangsrechnungWithAuftrag(this.rechnung, this.auftrag);
}

class EingangsrechnungenRepository {
  EingangsrechnungenRepository(this._db);
  final AppDatabase _db;

  Stream<List<EingangsrechnungWithAuftrag>> watchAll(
      {String query = '', String? status}) {
    final q = _db.select(_db.eingangsrechnungen).join([
      leftOuterJoin(_db.auftraege,
          _db.auftraege.id.equalsExp(_db.eingangsrechnungen.auftragId)),
    ]);
    if (status != null) {
      q.where(_db.eingangsrechnungen.status.equals(status));
    }
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where(_db.eingangsrechnungen.rechnungsnummer.lower().like(like) |
          _db.eingangsrechnungen.beschreibung.lower().like(like) |
          _db.eingangsrechnungen.kategorie.lower().like(like));
    }
    q.orderBy([
      OrderingTerm(
          expression: _db.eingangsrechnungen.rechnungsdatum,
          mode: OrderingMode.desc),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => EingangsrechnungWithAuftrag(
            r.readTable(_db.eingangsrechnungen),
            r.readTableOrNull(_db.auftraege)))
        .toList());
  }

  Future<int> upsert(EingangsrechnungenCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.eingangsrechnungen)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.eingangsrechnungen).insert(entry);
  }

  Future<int> delete(int id) => (_db.delete(_db.eingangsrechnungen)
        ..where((t) => t.id.equals(id)))
      .go();

  /// Markiert einen Datensatz als geprüft / wieder als ungeprüft.
  /// Wird vom Listen-Haken und vom Form-Speichern aufgerufen.
  Future<void> setGeprueft(int id, bool value) async {
    await (_db.update(_db.eingangsrechnungen)
          ..where((t) => t.id.equals(id)))
        .write(EingangsrechnungenCompanion(
      geprueft: Value(value),
      updatedAt: Value(DateTime.now()),
    ));
  }
}

final eingangsrechnungenRepositoryProvider =
    Provider<EingangsrechnungenRepository>((ref) {
  return EingangsrechnungenRepository(ref.watch(appDatabaseProvider));
});

class EingangsrechnungenFilter {
  final String query;
  final String? status;
  const EingangsrechnungenFilter({this.query = '', this.status});
  EingangsrechnungenFilter copyWith(
          {String? query, String? status, bool clearStatus = false}) =>
      EingangsrechnungenFilter(
        query: query ?? this.query,
        status: clearStatus ? null : (status ?? this.status),
      );
}

final eingangsrechnungenFilterProvider =
    StateProvider<EingangsrechnungenFilter>(
        (ref) => const EingangsrechnungenFilter());

final eingangsrechnungenListProvider =
    StreamProvider<List<EingangsrechnungWithAuftrag>>((ref) {
  final f = ref.watch(eingangsrechnungenFilterProvider);
  return ref
      .watch(eingangsrechnungenRepositoryProvider)
      .watchAll(query: f.query, status: f.status);
});
