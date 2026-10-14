import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

class AktenImportService {
  AktenImportService(this._db);
  final AppDatabase _db;

  Future<void> importAkte() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    final archive = ZipDecoder().decodeBytes(bytes);
    
    // Find JSON file
    ArchiveFile? jsonFile;
    for (final f in archive.files) {
      if (f.name.startsWith('akte_') && f.name.endsWith('.json')) {
        jsonFile = f;
        break;
      }
    }
    if (jsonFile == null) throw Exception('Keine akte_*.json im ZIP gefunden.');

    final jsonContent = utf8.decode(jsonFile.content as List<int>);
    final data = jsonDecode(jsonContent) as Map<String, dynamic>;

    await _db.transaction(() async {
      // 1. Kunde anlegen (immer neu, um Überschreiben zu verhindern)
      int? newKundeId;
      if (data['kunde'] != null) {
        final k = KundenData.fromJson(data['kunde']);
        newKundeId = await _db.into(_db.kunden).insert(KundenCompanion.insert(
          firma: Value(k.firma),
          vorname: Value(k.vorname),
          nachname: Value(k.nachname),
          strasse: Value(k.strasse),
          plz: Value(k.plz),
          ort: Value(k.ort),
          land: Value(k.land),
          email: Value(k.email),
          telefon: Value(k.telefon),
          typ: Value(k.typ),
          createdAt: Value(k.createdAt),
          updatedAt: Value(DateTime.now()),
        ));
      }

      // 2. Auftrag anlegen
      final a = AuftraegeData.fromJson(data['auftrag']);
      final newAuftragId = await _db.into(_db.auftraege).insert(AuftraegeCompanion.insert(
        kundeId: Value(newKundeId),
        aktenzeichen: Value(a.aktenzeichen),
        gerichtsAktenzeichen: Value(a.gerichtsAktenzeichen),
        betreff: Value(a.betreff),
        status: Value(a.status),
        stundensatz: Value(a.stundensatz),
        beweisbeschluss1: Value(a.beweisbeschluss1),
        createdAt: Value(a.createdAt),
        updatedAt: Value(DateTime.now()),
      ));

      // 3. Stunden
      if (data['stunden'] != null) {
        for (final s in data['stunden']) {
          final h = StundenData.fromJson(s);
          await _db.into(_db.stunden).insert(StundenCompanion.insert(
            auftragId: Value(newAuftragId),
            datum: Value(h.datum),
            taetigkeit: Value(h.taetigkeit),
            notiz: Value(h.notiz),
            minuten: Value(h.minuten),
            satz: Value(h.satz),
            abgerechnet: Value(h.abgerechnet),
          ));
        }
      }

      // 4. Auslagen
      if (data['auslagen'] != null) {
        for (final aData in data['auslagen']) {
          final x = AuslagenData.fromJson(aData);
          await _db.into(_db.auslagen).insert(AuslagenCompanion.insert(
            auftragId: Value(newAuftragId),
            datum: Value(x.datum),
            art: Value(x.art),
            beschreibung: Value(x.beschreibung),
            menge: Value(x.menge),
            einzelpreis: Value(x.einzelpreis),
            einheit: Value(x.einheit),
          ));
        }
      }

      // 5. Gutachten
      if (data['gutachten'] != null) {
        for (final g in data['gutachten']) {
          final x = GutachtenData.fromJson(g);
          await _db.into(_db.gutachten).insert(GutachtenCompanion.insert(
            auftragId: Value(newAuftragId),
            titel: Value(x.titel),
            abschnitteJson: Value(x.abschnitteJson),
            createdAt: Value(x.createdAt),
            updatedAt: Value(DateTime.now()),
          ));
        }
      }

      // 6. Notizen
      if (data['rechercheNotizen'] != null) {
        for (final n in data['rechercheNotizen']) {
          final x = RechercheNotizenData.fromJson(n);
          await _db.into(_db.rechercheNotizen).insert(RechercheNotizenCompanion.insert(
            auftragId: Value(newAuftragId),
            titel: x.titel,
            inhalt: x.inhalt,
            createdAt: Value(x.createdAt),
          ));
        }
      }

      // 7. Rechnungen
      if (data['rechnungen'] != null) {
        for (final r in data['rechnungen']) {
          final x = RechnungenData.fromJson(r);
          await _db.into(_db.rechnungen).insert(RechnungenCompanion.insert(
            auftragId: Value(newAuftragId),
            rechnungsnummer: Value(x.rechnungsnummer),
            rechnungsdatum: Value(x.rechnungsdatum),
            faelligAm: Value(x.faelligAm),
            status: Value(x.status),
            netto: Value(x.netto),
            ustSatz: Value(x.ustSatz),
            ustBetrag: Value(x.ustBetrag),
            brutto: Value(x.brutto),
            bezahlt: Value(x.bezahlt),
            bezahltAm: Value(x.bezahltAm),
            notiz: Value(x.notiz),
            positionenJson: Value(x.positionenJson),
          ));
        }
      }

      // 8. Fotos & Dokumente (inkl. Blob aus ZIP)
      if (data['fotos'] != null) {
        for (final f in data['fotos']) {
          final x = Foto.fromJson(f);
          final ext = x.pfad?.split('.').last ?? 'jpg';
          final name = 'fotos/${x.id}_${x.titel ?? "Foto"}.$ext'.replaceAll(RegExp(r'[^\w\.\-\/]'), '_');
          final file = archive.findFile(name);
          
          await _db.into(_db.fotos).insert(FotosCompanion.insert(
            auftragId: Value(newAuftragId),
            titel: Value(x.titel),
            pfad: Value(x.pfad),
            beschreibung: Value(x.beschreibung),
            aufnahmeAm: Value(x.aufnahmeAm),
            daten: file != null ? Value(Uint8List.fromList(file.content as List<int>)) : const Value.absent(),
            createdAt: Value(x.createdAt),
          ));
        }
      }

      if (data['dokumente'] != null) {
        for (final d in data['dokumente']) {
          final x = DokumenteData.fromJson(d);
          final name = 'dokumente/${x.id}_${x.titel ?? "Dokument.pdf"}'.replaceAll(RegExp(r'[^\w\.\-\/]'), '_');
          final file = archive.findFile(name);
          
          await _db.into(_db.dokumente).insert(DokumenteCompanion.insert(
            auftragId: Value(newAuftragId),
            titel: Value(x.titel),
            pfad: Value(x.pfad),
            kategorie: Value(x.kategorie),
            datum: Value(x.datum),
            beschreibung: Value(x.beschreibung),
            daten: file != null ? Value(Uint8List.fromList(file.content as List<int>)) : const Value.absent(),
            createdAt: Value(x.createdAt),
          ));
        }
      }
    });
  }
}

final aktenImportServiceProvider = Provider<AktenImportService>((ref) {
  return AktenImportService(ref.watch(appDatabaseProvider));
});
