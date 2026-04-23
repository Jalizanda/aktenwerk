import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_provider.dart';
import 'firestore_service.dart';

/// Ergebnis eines Pull-Durchlaufs: Anzahl gezogener Datensätze pro
/// Firestore-Collection. Collections mit `null` sind bei diesem Lauf
/// übersprungen worden (z. B. weil Firestore nicht verfügbar war).
typedef PullReport = Map<String, int>;

/// Spiegelt Drift-Entitäten bidirektional gegen Firestore. Jede Entity
/// wird in `r.toJson()` serialisiert (Drift-Default: DateTime → ISO-
/// String, Enums → Index, bool/num direkt). Beim Pull baut
/// `XxxData.fromJson(data)` die Entität zurück und wird via
/// `insertOnConflictUpdate` ins lokale Drift geschrieben.
///
/// Trick: Weil DataClass selbst `Insertable` implementiert, kommen
/// push & pull mit einem Einzeiler aus — auch bei neuen Feldern muss
/// hier nichts nachgezogen werden.
class SyncService {
  SyncService(this._db, this._fs);
  final AppDatabase _db;
  final FirestoreService _fs;

  bool get enabled => _fs.enabled;

  /// Push nur der Zeilen, deren `updatedAt` nach [seit] liegt. Wird
  /// vom Auto-Sync-Service alle paar Minuten aufgerufen — hält die
  /// Firestore-Schreibzahlen niedrig, weil unveränderte Rows übersprungen
  /// werden. Gibt die Anzahl gepushter Einträge zurück.
  Future<int> pushChangedSince(DateTime seit) async {
    if (!_fs.enabled) return 0;
    var total = 0;
    total += await _pushChanged(
        'kunden', await _db.select(_db.kunden).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'auftraege', await _db.select(_db.auftraege).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'rechnungen', await _db.select(_db.rechnungen).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'angebote', await _db.select(_db.angebote).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'eingangsrechnungen',
        await _db.select(_db.eingangsrechnungen).get(),
        (r) => r.id,
        (r) => r.updatedAt,
        seit);
    total += await _pushChanged(
        'lieferanten', await _db.select(_db.lieferanten).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'artikel', await _db.select(_db.artikel).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'stunden', await _db.select(_db.stunden).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'auslagen', await _db.select(_db.auslagen).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'normen', await _db.select(_db.normen).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'geraete', await _db.select(_db.geraete).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'textbausteine', await _db.select(_db.textbausteine).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'fortbildungen', await _db.select(_db.fortbildungen).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'gutachten', await _db.select(_db.gutachten).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'anschreiben', await _db.select(_db.anschreiben).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'fotos', await _db.select(_db.fotos).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'dokumente', await _db.select(_db.dokumente).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'benutzer', await _db.select(_db.benutzer).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'einstellungen', await _db.select(_db.einstellungen).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'erlaeuterungen', await _db.select(_db.erlaeuterungen).get(),
        (r) => r.id, (r) => r.updatedAt, seit);
    total += await _pushChanged(
        'recherche_notizen',
        await _db.select(_db.rechercheNotizen).get(),
        (r) => r.id,
        (r) => r.updatedAt,
        seit);
    return total;
  }

  Future<int> _pushChanged<T extends DataClass>(
    String collection,
    Iterable<T> rows,
    int Function(T) idOf,
    DateTime Function(T) updatedAtOf,
    DateTime seit,
  ) async {
    var count = 0;
    for (final r in rows) {
      if (updatedAtOf(r).isAfter(seit)) {
        await _fs.upsert(collection, idOf(r).toString(), r.toJson());
        count++;
      }
    }
    return count;
  }

  /// Push aller lokaler Datensätze in die Cloud (merge auf Doc-Ebene).
  Future<void> syncAll() async {
    if (!_fs.enabled) return;
    await pushKunden();
    await pushAuftraege();
    await pushRechnungen();
    await pushAngebote();
    await pushEingangsrechnungen();
    await pushLieferanten();
    await pushArtikel();
    await pushStunden();
    await pushAuslagen();
    await pushNormen();
    await pushGeraete();
    await pushTextbausteine();
    await pushFortbildungen();
    await pushGutachten();
    await pushAnschreiben();
    await pushFotos();
    await pushDokumente();
    await pushBenutzer();
    await pushEinstellungen();
    await pushErlaeuterungen();
    await pushRechercheNotizen();
  }

  /// Zieht alle wichtigen Collections aus Firestore in das lokale Drift.
  /// Gibt einen Report mit Collection → Anzahl zurück, damit der Nutzer
  /// sieht, ob Daten in der Cloud lagen.
  Future<PullReport> pullAll() async {
    final report = <String, int>{};
    if (!_fs.enabled) return report;
    report['kunden'] = await pullKunden();
    report['auftraege'] = await pullAuftraege();
    report['rechnungen'] = await pullRechnungen();
    report['angebote'] = await pullAngebote();
    report['eingangsrechnungen'] = await pullEingangsrechnungen();
    report['lieferanten'] = await pullLieferanten();
    report['artikel'] = await pullArtikel();
    report['stunden'] = await pullStunden();
    report['auslagen'] = await pullAuslagen();
    report['normen'] = await pullNormen();
    report['geraete'] = await pullGeraete();
    report['textbausteine'] = await pullTextbausteine();
    report['fortbildungen'] = await pullFortbildungen();
    report['gutachten'] = await pullGutachten();
    report['anschreiben'] = await pullAnschreiben();
    report['fotos'] = await pullFotos();
    report['dokumente'] = await pullDokumente();
    report['benutzer'] = await pullBenutzer();
    report['einstellungen'] = await pullEinstellungen();
    report['erlaeuterungen'] = await pullErlaeuterungen();
    report['recherche_notizen'] = await pullRechercheNotizen();
    return report;
  }

  // ------------------------------------------------------------------
  //  Interne Helfer — eine Zeile Push / Pull pro Modul
  // ------------------------------------------------------------------

  Future<void> _pushAll<T extends DataClass>(
    String collection,
    Iterable<T> rows,
    int Function(T) idOf,
  ) async {
    for (final r in rows) {
      await _fs.upsert(collection, idOf(r).toString(), r.toJson());
    }
  }

  Future<int> _pullGeneric<T extends DataClass>(
    String collection,
    T Function(Map<String, dynamic>) fromJson,
    Future<void> Function(T) upsertLokal,
  ) async {
    if (!_fs.enabled) return 0;
    final col = _fs.orgCollection(collection);
    if (col == null) return 0;
    final snap = await col.get();
    var count = 0;
    for (final doc in snap.docs) {
      try {
        final data = fromJson(doc.data());
        await upsertLokal(data);
        count++;
      } catch (_) {
        // Einzelne defekte Docs sollen den Gesamtlauf nicht killen.
      }
    }
    return count;
  }

  // ------------------------------------------------------------------
  //  Push / Pull pro Modul
  // ------------------------------------------------------------------

  Future<void> pushKunden() async =>
      _pushAll('kunden', await _db.select(_db.kunden).get(), (r) => r.id);
  Future<int> pullKunden() => _pullGeneric(
        'kunden',
        KundenData.fromJson,
        (d) async =>
            _db.into(_db.kunden).insertOnConflictUpdate(d).then((_) {}),
      );

  Future<void> pushAuftraege() async => _pushAll(
      'auftraege', await _db.select(_db.auftraege).get(), (r) => r.id);
  Future<int> pullAuftraege() => _pullGeneric(
        'auftraege',
        AuftraegeData.fromJson,
        (d) async =>
            _db.into(_db.auftraege).insertOnConflictUpdate(d).then((_) {}),
      );

  Future<void> pushRechnungen() async => _pushAll(
      'rechnungen', await _db.select(_db.rechnungen).get(), (r) => r.id);
  Future<int> pullRechnungen() => _pullGeneric(
        'rechnungen',
        RechnungenData.fromJson,
        (d) async =>
            _db.into(_db.rechnungen).insertOnConflictUpdate(d).then((_) {}),
      );

  Future<void> pushAngebote() async => _pushAll(
      'angebote', await _db.select(_db.angebote).get(), (r) => r.id);
  Future<int> pullAngebote() => _pullGeneric(
        'angebote',
        AngeboteData.fromJson,
        (d) async =>
            _db.into(_db.angebote).insertOnConflictUpdate(d).then((_) {}),
      );

  Future<void> pushEingangsrechnungen() async => _pushAll(
      'eingangsrechnungen',
      await _db.select(_db.eingangsrechnungen).get(),
      (r) => r.id);
  Future<int> pullEingangsrechnungen() => _pullGeneric(
        'eingangsrechnungen',
        EingangsrechnungenData.fromJson,
        (d) async => _db
            .into(_db.eingangsrechnungen)
            .insertOnConflictUpdate(d)
            .then((_) {}),
      );

  Future<void> pushLieferanten() async => _pushAll(
      'lieferanten', await _db.select(_db.lieferanten).get(), (r) => r.id);
  Future<int> pullLieferanten() => _pullGeneric(
        'lieferanten',
        LieferantenData.fromJson,
        (d) async =>
            _db.into(_db.lieferanten).insertOnConflictUpdate(d).then((_) {}),
      );

  Future<void> pushArtikel() async => _pushAll(
      'artikel', await _db.select(_db.artikel).get(), (r) => r.id);
  Future<int> pullArtikel() => _pullGeneric(
        'artikel',
        ArtikelData.fromJson,
        (d) async =>
            _db.into(_db.artikel).insertOnConflictUpdate(d).then((_) {}),
      );

  Future<void> pushStunden() async => _pushAll(
      'stunden', await _db.select(_db.stunden).get(), (r) => r.id);
  Future<int> pullStunden() => _pullGeneric(
        'stunden',
        StundenData.fromJson,
        (d) async =>
            _db.into(_db.stunden).insertOnConflictUpdate(d).then((_) {}),
      );

  Future<void> pushAuslagen() async => _pushAll(
      'auslagen', await _db.select(_db.auslagen).get(), (r) => r.id);
  Future<int> pullAuslagen() => _pullGeneric(
        'auslagen',
        AuslagenData.fromJson,
        (d) async =>
            _db.into(_db.auslagen).insertOnConflictUpdate(d).then((_) {}),
      );

  Future<void> pushNormen() async => _pushAll(
      'normen', await _db.select(_db.normen).get(), (r) => r.id);
  Future<int> pullNormen() => _pullGeneric(
        'normen',
        NormenData.fromJson,
        (d) async =>
            _db.into(_db.normen).insertOnConflictUpdate(d).then((_) {}),
      );

  Future<void> pushGeraete() async => _pushAll(
      'geraete', await _db.select(_db.geraete).get(), (r) => r.id);
  Future<int> pullGeraete() => _pullGeneric(
        'geraete',
        GeraeteData.fromJson,
        (d) async =>
            _db.into(_db.geraete).insertOnConflictUpdate(d).then((_) {}),
      );

  Future<void> pushTextbausteine() async => _pushAll('textbausteine',
      await _db.select(_db.textbausteine).get(), (r) => r.id);
  Future<int> pullTextbausteine() => _pullGeneric(
        'textbausteine',
        TextbausteineData.fromJson,
        (d) async => _db
            .into(_db.textbausteine)
            .insertOnConflictUpdate(d)
            .then((_) {}),
      );

  Future<void> pushFortbildungen() async => _pushAll('fortbildungen',
      await _db.select(_db.fortbildungen).get(), (r) => r.id);
  Future<int> pullFortbildungen() => _pullGeneric(
        'fortbildungen',
        FortbildungenData.fromJson,
        (d) async => _db
            .into(_db.fortbildungen)
            .insertOnConflictUpdate(d)
            .then((_) {}),
      );

  Future<void> pushGutachten() async => _pushAll(
      'gutachten', await _db.select(_db.gutachten).get(), (r) => r.id);
  Future<int> pullGutachten() => _pullGeneric(
        'gutachten',
        GutachtenData.fromJson,
        (d) async =>
            _db.into(_db.gutachten).insertOnConflictUpdate(d).then((_) {}),
      );

  Future<void> pushAnschreiben() async => _pushAll(
      'anschreiben', await _db.select(_db.anschreiben).get(), (r) => r.id);
  Future<int> pullAnschreiben() => _pullGeneric(
        'anschreiben',
        AnschreibenData.fromJson,
        (d) async =>
            _db.into(_db.anschreiben).insertOnConflictUpdate(d).then((_) {}),
      );

  /// Fotos werden nur mit Metadaten gesynct — die Bilder selbst liegen
  /// in Firebase Storage und bleiben beim Pull dort.
  Future<void> pushFotos() async =>
      _pushAll('fotos', await _db.select(_db.fotos).get(), (r) => r.id);
  Future<int> pullFotos() => _pullGeneric(
        'fotos',
        Foto.fromJson,
        (d) async =>
            _db.into(_db.fotos).insertOnConflictUpdate(d).then((_) {}),
      );

  Future<void> pushDokumente() async => _pushAll(
      'dokumente', await _db.select(_db.dokumente).get(), (r) => r.id);
  Future<int> pullDokumente() => _pullGeneric(
        'dokumente',
        DokumenteData.fromJson,
        (d) async =>
            _db.into(_db.dokumente).insertOnConflictUpdate(d).then((_) {}),
      );

  Future<void> pushBenutzer() async => _pushAll(
      'benutzer', await _db.select(_db.benutzer).get(), (r) => r.id);
  Future<int> pullBenutzer() => _pullGeneric(
        'benutzer',
        BenutzerData.fromJson,
        (d) async =>
            _db.into(_db.benutzer).insertOnConflictUpdate(d).then((_) {}),
      );

  Future<void> pushEinstellungen() async => _pushAll('einstellungen',
      await _db.select(_db.einstellungen).get(), (r) => r.id);
  Future<int> pullEinstellungen() => _pullGeneric(
        'einstellungen',
        EinstellungenData.fromJson,
        (d) async => _db
            .into(_db.einstellungen)
            .insertOnConflictUpdate(d)
            .then((_) {}),
      );

  Future<void> pushErlaeuterungen() async => _pushAll('erlaeuterungen',
      await _db.select(_db.erlaeuterungen).get(), (r) => r.id);
  Future<int> pullErlaeuterungen() => _pullGeneric(
        'erlaeuterungen',
        ErlaeuterungenData.fromJson,
        (d) async => _db
            .into(_db.erlaeuterungen)
            .insertOnConflictUpdate(d)
            .then((_) {}),
      );

  Future<void> pushRechercheNotizen() async => _pushAll(
      'recherche_notizen',
      await _db.select(_db.rechercheNotizen).get(),
      (r) => r.id);
  Future<int> pullRechercheNotizen() => _pullGeneric(
        'recherche_notizen',
        RechercheNotizenData.fromJson,
        (d) async => _db
            .into(_db.rechercheNotizen)
            .insertOnConflictUpdate(d)
            .then((_) {}),
      );
}

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.watch(appDatabaseProvider),
    ref.watch(firestoreServiceProvider),
  );
});
