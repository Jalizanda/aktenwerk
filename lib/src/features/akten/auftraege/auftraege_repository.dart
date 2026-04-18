import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

enum AuftragArt { privat, gericht }

extension AuftragArtX on AuftragArt {
  String get dbValue => name;
  String get label => switch (this) {
        AuftragArt.privat => 'Privatgutachten',
        AuftragArt.gericht => 'Gerichtsgutachten',
      };
  static AuftragArt fromDb(String? s) => AuftragArt.values.firstWhere(
        (v) => v.name == s,
        orElse: () => AuftragArt.privat,
      );
}

enum AuftragStatus { offen, inArbeit, wartet, abgeschlossen, abgerechnet, storniert }

extension AuftragStatusX on AuftragStatus {
  String get dbValue => switch (this) {
        AuftragStatus.offen => 'offen',
        AuftragStatus.inArbeit => 'in_arbeit',
        AuftragStatus.wartet => 'wartet',
        AuftragStatus.abgeschlossen => 'abgeschlossen',
        AuftragStatus.abgerechnet => 'abgerechnet',
        AuftragStatus.storniert => 'storniert',
      };
  String get label => switch (this) {
        AuftragStatus.offen => 'offen',
        AuftragStatus.inArbeit => 'in Arbeit',
        AuftragStatus.wartet => 'wartet',
        AuftragStatus.abgeschlossen => 'abgeschlossen',
        AuftragStatus.abgerechnet => 'abgerechnet',
        AuftragStatus.storniert => 'storniert',
      };
  static AuftragStatus fromDb(String? s) => AuftragStatus.values.firstWhere(
        (v) => v.dbValue == s,
        orElse: () => AuftragStatus.offen,
      );
}

/// Gemeinsame Ansicht: Auftrag + dessen Auftraggeber (Join-Ergebnis).
class AuftragWithKunde {
  final AuftraegeData auftrag;
  final KundenData? kunde;
  const AuftragWithKunde(this.auftrag, this.kunde);
}

class AuftraegeRepository {
  AuftraegeRepository(this._db);
  final AppDatabase _db;

  Stream<List<AuftragWithKunde>> watchAll({
    String query = '',
    AuftragArt? art,
    AuftragStatus? status,
  }) {
    final q = _db.select(_db.auftraege).join([
      leftOuterJoin(
        _db.kunden,
        _db.kunden.id.equalsExp(_db.auftraege.kundeId),
      ),
    ]);

    if (art != null) {
      q.where(_db.auftraege.art.equals(art.dbValue));
    }
    if (status != null) {
      q.where(_db.auftraege.status.equals(status.dbValue));
    }
    if (query.trim().isNotEmpty) {
      final like = '%${query.trim().toLowerCase()}%';
      q.where(
        _db.auftraege.aktenzeichen.lower().like(like) |
            _db.auftraege.bezeichnung.lower().like(like) |
            _db.auftraege.objektOrt.lower().like(like) |
            _db.auftraege.objektStrasse.lower().like(like) |
            _db.auftraege.gerichtsAktenzeichen.lower().like(like) |
            _db.kunden.firma.lower().like(like) |
            _db.kunden.nachname.lower().like(like),
      );
    }

    q.orderBy([
      OrderingTerm(
          expression: _db.auftraege.eingangAm, mode: OrderingMode.desc),
      OrderingTerm(
          expression: _db.auftraege.createdAt, mode: OrderingMode.desc),
    ]);

    return q.watch().map((rows) {
      return rows
          .map((r) => AuftragWithKunde(
                r.readTable(_db.auftraege),
                r.readTableOrNull(_db.kunden),
              ))
          .toList(growable: false);
    });
  }

  Future<AuftraegeData?> byId(int id) =>
      (_db.select(_db.auftraege)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> upsert(AuftraegeCompanion entry) async {
    if (entry.id.present) {
      await (_db.update(_db.auftraege)
            ..where((t) => t.id.equals(entry.id.value)))
          .write(entry.copyWith(updatedAt: Value(DateTime.now())));
      return entry.id.value;
    }
    return _db.into(_db.auftraege).insert(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.auftraege)..where((t) => t.id.equals(id))).go();

  /// Nächste freie Sequenznummer für Aktenzeichen (einfach: max(id)+1).
  Future<int> nextAktenzeichenSeq() async {
    final max = await (_db.selectOnly(_db.auftraege)
          ..addColumns([_db.auftraege.id.max()]))
        .getSingle();
    final current = max.read(_db.auftraege.id.max()) ?? 0;
    return current + 1;
  }
}

final auftraegeRepositoryProvider = Provider<AuftraegeRepository>((ref) {
  return AuftraegeRepository(ref.watch(appDatabaseProvider));
});

class AuftraegeFilter {
  final String query;
  final AuftragArt? art;
  final AuftragStatus? status;
  const AuftraegeFilter({this.query = '', this.art, this.status});

  AuftraegeFilter copyWith({
    String? query,
    AuftragArt? art,
    AuftragStatus? status,
    bool clearArt = false,
    bool clearStatus = false,
  }) =>
      AuftraegeFilter(
        query: query ?? this.query,
        art: clearArt ? null : (art ?? this.art),
        status: clearStatus ? null : (status ?? this.status),
      );

  bool get isActive => query.isNotEmpty || art != null || status != null;
}

final auftraegeFilterProvider =
    StateProvider<AuftraegeFilter>((ref) => const AuftraegeFilter());

final auftraegeListProvider =
    StreamProvider<List<AuftragWithKunde>>((ref) {
  final f = ref.watch(auftraegeFilterProvider);
  return ref.watch(auftraegeRepositoryProvider).watchAll(
        query: f.query,
        art: f.art,
        status: f.status,
      );
});
