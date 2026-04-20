import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../system/einstellungen/nummernkreis_service.dart';

/// Dokument-Workflow-Service — konvertiert Dokumente ineinander und erzeugt
/// jeweils einen neuen Datensatz (Quelldokument bleibt unangetastet).
///
/// Unterstützte Workflows:
/// - Angebot → Auftragsbestätigung (reines Flag-Setting oder eigenes Angebot mit Typ=AB)
/// - Angebot → Auftrag (erzeugt neue Akte)
/// - Angebot → Rechnung
/// - Auftrag → Rechnung
/// - Rechnung → Gutschrift (Beträge negiert)
/// - Rechnung → Korrektur
class DokumentWorkflowService {
  DokumentWorkflowService(this._db, this._nk);
  final AppDatabase _db;
  final NummernkreisService _nk;

  /// Angebot → neuer Auftrag (Akte). Übernimmt Kunde, Objekt, Betreff,
  /// und verknüpft das Angebot.
  Future<int> angebotToAuftrag(AngeboteData a) async {
    final az = await _nk.nextNumber(NummernkreisTyp.akte);
    return _db.into(_db.auftraege).insert(AuftraegeCompanion.insert(
          aktenzeichen: Value(az),
          art: const Value('privat'),
          status: const Value('offen'),
          kundeId: Value(a.kundeId),
          betreff: Value(a.betreff),
          bezeichnung: Value(a.anfrage),
          objektStrasse: Value(a.objektStrasse),
          objektPlz: Value(a.objektPlz),
          objektOrt: Value(a.objektOrt),
          auftragAm: Value(DateTime.now()),
        ));
  }

  /// Angebot → Rechnung. Positionen, Kunde, Betreff werden übernommen.
  /// Rechnungsnummer wird aus Nummernkreis generiert.
  Future<int> angebotToRechnung(
    AngeboteData a, {
    int? auftragId,
  }) async {
    final nr = await _nk.nextNumber(NummernkreisTyp.rechnung);
    return _db.into(_db.rechnungen).insert(RechnungenCompanion.insert(
          rechnungsnummer: Value(nr),
          typ: const Value('privat'),
          kundeId: Value(a.kundeId),
          auftragId: Value(auftragId),
          rechnungsdatum: Value(DateTime.now()),
          netto: Value(a.netto),
          ustSatz: Value(a.ustSatz),
          ustBetrag: Value(a.ustBetrag),
          brutto: Value(a.brutto),
          positionenJson: Value(a.positionenJson),
          kopftext: Value(a.kopftext),
          fusstext: Value(a.fusstext),
          status: const Value('entwurf'),
        ));
  }

  /// Auftrag → Rechnung. Kunde/Auftrag werden verknüpft.
  Future<int> auftragToRechnung(AuftraegeData a) async {
    final nr = await _nk.nextNumber(NummernkreisTyp.rechnung);
    final typ = a.art == 'gericht' ? 'jveg' : 'privat';
    return _db.into(_db.rechnungen).insert(RechnungenCompanion.insert(
          rechnungsnummer: Value(nr),
          typ: Value(typ),
          kundeId: Value(a.kundeId),
          auftragId: Value(a.id),
          rechnungsdatum: Value(DateTime.now()),
          status: const Value('entwurf'),
        ));
  }

  /// Rechnung → Gutschrift. Positionen werden negiert, Nummernkreis Gutschrift.
  Future<int> rechnungToGutschrift(RechnungenData r) async {
    final nr = await _nk.nextNumber(NummernkreisTyp.rechnung);
    final gutschriftNr = 'G-$nr';
    return _db.into(_db.rechnungen).insert(RechnungenCompanion.insert(
          rechnungsnummer: Value(gutschriftNr),
          typ: const Value('gutschrift'),
          bezugRechnung: Value(r.rechnungsnummer),
          kundeId: Value(r.kundeId),
          auftragId: Value(r.auftragId),
          rechnungsdatum: Value(DateTime.now()),
          netto: Value(-r.netto),
          ustSatz: Value(r.ustSatz),
          ustBetrag: Value(-r.ustBetrag),
          brutto: Value(-r.brutto),
          positionenJson: Value(r.positionenJson),
          kopftext: Value(r.kopftext),
          fusstext: Value(r.fusstext),
          status: const Value('entwurf'),
        ));
  }

  /// Rechnung → Rechnungskorrektur (identische Positionen, User bearbeitet).
  Future<int> rechnungToKorrektur(RechnungenData r) async {
    final nr = await _nk.nextNumber(NummernkreisTyp.rechnung);
    return _db.into(_db.rechnungen).insert(RechnungenCompanion.insert(
          rechnungsnummer: Value('K-$nr'),
          typ: const Value('korrektur'),
          bezugRechnung: Value(r.rechnungsnummer),
          kundeId: Value(r.kundeId),
          auftragId: Value(r.auftragId),
          rechnungsdatum: Value(DateTime.now()),
          netto: Value(r.netto),
          ustSatz: Value(r.ustSatz),
          ustBetrag: Value(r.ustBetrag),
          brutto: Value(r.brutto),
          positionenJson: Value(r.positionenJson),
          kopftext: Value(r.kopftext),
          fusstext: Value(r.fusstext),
          status: const Value('entwurf'),
        ));
  }

  /// Angebot → Auftragsbestätigung (als neues Angebot mit Typ "AB" / Status
  /// `auftragsbestaetigung`).
  Future<int> angebotToAb(AngeboteData a) async {
    final nr = await _nk.nextNumber(NummernkreisTyp.angebot);
    return _db.into(_db.angebote).insert(AngeboteCompanion.insert(
          angebotsnummer: Value('AB-$nr'),
          kundeId: Value(a.kundeId),
          betreff: Value('Auftragsbestätigung zu ${a.angebotsnummer ?? ""}'),
          anfrage: Value(a.anfrage),
          objektStrasse: Value(a.objektStrasse),
          objektPlz: Value(a.objektPlz),
          objektOrt: Value(a.objektOrt),
          bedingungen: Value(a.bedingungen),
          datum: Value(DateTime.now()),
          gueltigBis: Value(a.gueltigBis),
          status: const Value('auftragsbestaetigung'),
          netto: Value(a.netto),
          ustSatz: Value(a.ustSatz),
          ustBetrag: Value(a.ustBetrag),
          brutto: Value(a.brutto),
          positionenJson: Value(a.positionenJson),
          kopftext: Value(a.kopftext),
          fusstext: Value(a.fusstext),
        ));
  }

  /// Prüft, ob für einen Kunden bereits mind. ein Auftrag existiert (für die
  /// Entscheidung, ob der Button „In Auftrag umwandeln" oder „Weiteren Auftrag
  /// anlegen" heißen soll).
  Future<bool> hatKundeAuftrag(int? kundeId) async {
    if (kundeId == null) return false;
    final list = await (_db.select(_db.auftraege)
          ..where((t) => t.kundeId.equals(kundeId))
          ..limit(1))
        .get();
    return list.isNotEmpty;
  }
}

final dokumentWorkflowProvider =
    Provider<DokumentWorkflowService>((ref) {
  return DokumentWorkflowService(
    ref.watch(appDatabaseProvider),
    ref.watch(nummernkreisServiceProvider),
  );
});
