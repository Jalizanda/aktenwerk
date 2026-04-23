import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../features/werkzeuge/wiedervorlagen/wiedervorlagen_repository.dart';

class RechnungWithKunde {
  final RechnungenData rechnung;
  final KundenData? kunde;
  final AuftraegeData? auftrag;
  const RechnungWithKunde(this.rechnung, this.kunde, this.auftrag);
}

class RechnungenRepository {
  RechnungenRepository(this._db, this._wv);
  final AppDatabase _db;
  final WiedervorlagenRepository _wv;

  Stream<List<RechnungWithKunde>> watchAll(
      {String query = '', String? status}) {
    final q = _db.select(_db.rechnungen).join([
      leftOuterJoin(
          _db.kunden, _db.kunden.id.equalsExp(_db.rechnungen.kundeId)),
      leftOuterJoin(_db.auftraege,
          _db.auftraege.id.equalsExp(_db.rechnungen.auftragId)),
    ]);
    if (status != null) {
      q.where(_db.rechnungen.status.equals(status));
    }
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where(_db.rechnungen.rechnungsnummer.lower().like(like) |
          _db.auftraege.aktenzeichen.lower().like(like) |
          _db.kunden.firma.lower().like(like) |
          _db.kunden.nachname.lower().like(like));
    }
    q.orderBy([
      OrderingTerm(
          expression: _db.rechnungen.rechnungsdatum,
          mode: OrderingMode.desc),
      OrderingTerm(
          expression: _db.rechnungen.createdAt, mode: OrderingMode.desc),
    ]);
    return q.watch().map((rows) => rows
        .map((r) => RechnungWithKunde(
              r.readTable(_db.rechnungen),
              r.readTableOrNull(_db.kunden),
              r.readTableOrNull(_db.auftraege),
            ))
        .toList());
  }

  Future<RechnungenData?> byId(int id) =>
      (_db.select(_db.rechnungen)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> upsert(RechnungenCompanion entry) async {
    final int id;
    if (entry.id.present) {
      await (_db.update(_db.rechnungen)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      id = entry.id.value;
    } else {
      id = await _db.into(_db.rechnungen).insert(entry);
    }
    await _trigger(id);
    return id;
  }

  /// Legt eine Wiedervorlage "Mahnung prüfen" an, wenn eine Rechnung
  /// offen ist und ein Fälligkeitsdatum hat. Idempotent — mehrfach
  /// aufrufbar, erzeugt aber nur eine Wiedervorlage pro Rechnung.
  Future<void> _trigger(int id) async {
    try {
      final r = await byId(id);
      if (r == null) return;
      if (r.status == 'bezahlt' || r.status == 'storniert') return;
      final faellig = r.faelligAm;
      if (faellig == null) return;
      await _wv.ausloeseTrigger(
        triggerTyp: 'rechnung.mahnung',
        triggerQuellId: id,
        titel:
            'Mahnung prüfen — Rg. ${r.rechnungsnummer ?? id}',
        faelligAm: faellig.add(const Duration(days: 14)),
        auftragId: r.auftragId,
        anlass: 'Rechnungs-Fälligkeit überschritten?',
        prioritaet: 'hoch',
      );
    } catch (_) {
      // Trigger ist best-effort, niemals blockierend.
    }
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.rechnungen)..where((t) => t.id.equals(id))).go();

  Future<void> setPdfArchive(
    int id, {
    required String storageUrl,
    required String dateiname,
    required int groesse,
  }) async {
    await (_db.update(_db.rechnungen)..where((t) => t.id.equals(id))).write(
      RechnungenCompanion(
        pdfStorageUrl: Value(storageUrl),
        pdfDateiname: Value(dateiname),
        pdfGroesse: Value(groesse),
        pdfErstelltAm: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> nextSequenz() async {
    final row = await (_db.selectOnly(_db.rechnungen)
          ..addColumns([_db.rechnungen.id.max()]))
        .getSingle();
    return (row.read(_db.rechnungen.id.max()) ?? 0) + 1;
  }
}

final rechnungenRepositoryProvider = Provider<RechnungenRepository>((ref) {
  return RechnungenRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(wiedervorlagenRepositoryProvider),
  );
});

class RechnungenFilter {
  final String query;
  final String? status;
  const RechnungenFilter({this.query = '', this.status});
  RechnungenFilter copyWith(
          {String? query, String? status, bool clearStatus = false}) =>
      RechnungenFilter(
        query: query ?? this.query,
        status: clearStatus ? null : (status ?? this.status),
      );
}

final rechnungenFilterProvider =
    StateProvider<RechnungenFilter>((ref) => const RechnungenFilter());

final rechnungenListProvider =
    StreamProvider<List<RechnungWithKunde>>((ref) {
  final f = ref.watch(rechnungenFilterProvider);
  return ref
      .watch(rechnungenRepositoryProvider)
      .watchAll(query: f.query, status: f.status);
});
