import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/database/app_database.dart';
import '../../data/database/database_provider.dart';
import '../../data/sync/auth_service.dart';
import '../../data/sync/storage_service.dart';
import '../../features/akten/dokumente/dokumente_repository.dart';
import '../widgets/file_upload_section.dart';
import 'document_pdf.dart';

/// Generiert das PDF zu `data`, lädt es unter `prefix/dateiname.pdf` in
/// Firebase Storage hoch und gibt den Download-Link + Metadaten zurück.
///
/// Das Dateiname-Format ist:
/// `<Belegnummer> <Aktenzeichen> <Kundenname> <Datum>.pdf`
///
/// Zusätzlich wird ein Dokument-Eintrag im Dokumente-Modul angelegt
/// (Kategorie = Dokumenttyp, auftragId gesetzt), sodass der Beleg im
/// Dokumente-Reiter der jeweiligen Akte erscheint.
Future<UploadedFile?> archivePdf(
  WidgetRef ref,
  PdfDocumentData data, {
  required String prefix,
  int? auftragId,
  String? aktenzeichen,
}) async {
  final Uint8List bytes = await buildDocumentPdf(data);
  final storage = ref.read(storageServiceProvider);
  final auth = ref.read(authServiceProvider);
  if (!storage.enabled || auth.currentUser == null) {
    return null;
  }

  final dateiname = _buildFilename(data, aktenzeichen);
  final safe = dateiname.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final path = '$prefix/$safe';

  final url = await storage.uploadBytes(
    path,
    bytes: bytes,
    contentType: 'application/pdf',
  );
  if (url == null) return null;

  // Ein Dokumenten-Eintrag in der Akte anlegen, damit der Beleg unter
  // dem Dokumente-Reiter der Akte auftaucht.
  if (auftragId != null) {
    try {
      await ref
          .read(dokumenteRepositoryProvider)
          .upsert(DokumenteCompanion.insert(
            titel: Value(dateiname),
            mimeType: const Value('application/pdf'),
            dateigroesse: Value(bytes.length),
            storageUrl: Value(url),
            storagePfad: Value(path),
            auftragId: Value(auftragId),
            kategorie: Value(data.dokumentTyp),
            datum: Value(data.datum ?? DateTime.now()),
          ));
    } catch (_) {
      // Fehler beim Dokument-Eintrag sind nicht kritisch; PDF liegt in Storage.
    }
  }

  return UploadedFile(
    storageUrl: url,
    dateiname: dateiname,
    mimeType: 'application/pdf',
    groesse: bytes.length,
  );
}

String _buildFilename(PdfDocumentData d, String? aktenzeichen) {
  final belegNr = (d.dokumentNr ?? '').trim();
  final az = (aktenzeichen ?? '').trim();
  final kunde = _kundeNameKurz(d.empfaenger);
  final datum = d.datum == null
      ? DateFormat('yyyy-MM-dd').format(DateTime.now())
      : DateFormat('yyyy-MM-dd').format(d.datum!);
  final parts = [
    if (belegNr.isNotEmpty) belegNr,
    if (az.isNotEmpty) az,
    if (kunde.isNotEmpty) kunde,
    datum,
  ];
  if (parts.isEmpty) return '${d.dokumentTyp}.pdf';
  return '${parts.join(' ')}.pdf';
}

String _kundeNameKurz(KundenData? k) {
  if (k == null) return '';
  final firma = (k.firma ?? '').trim();
  if (firma.isNotEmpty) return firma;
  final nn = (k.nachname ?? '').trim();
  final vn = (k.vorname ?? '').trim();
  return [vn, nn].where((s) => s.isNotEmpty).join(' ');
}

/// Friert einen Beleg ein: PDF wird in Firebase Storage abgelegt + als
/// Dokument in der Akte verlinkt + Status auf "festgeschrieben"/"versendet"
/// gesetzt. Nach dem Einfrieren soll das Dokument nicht mehr bearbeitet
/// werden — dies wird per Status am jeweiligen Datensatz signalisiert.
///
/// Gibt das UploadedFile oder `null` bei Fehler zurück.
Future<UploadedFile?> freezeRechnungAsBeleg(
  WidgetRef ref,
  RechnungenData r,
  PdfDocumentData data,
) async {
  final db = ref.read(appDatabaseProvider);
  final uploaded = await archivePdf(
    ref,
    data,
    prefix: 'belege/rechnungen',
    auftragId: r.auftragId,
    aktenzeichen:
        await _aktenzeichenFor(db, r.auftragId),
  );
  if (uploaded == null) return null;
  await (db.update(db.rechnungen)..where((t) => t.id.equals(r.id))).write(
    RechnungenCompanion(
      pdfStorageUrl: Value(uploaded.storageUrl),
      pdfDateiname: Value(uploaded.dateiname),
      pdfGroesse: Value(uploaded.groesse ?? 0),
      pdfErstelltAm: Value(DateTime.now()),
      status: r.status == 'entwurf' ? const Value('versendet') : const Value.absent(),
      updatedAt: Value(DateTime.now()),
    ),
  );
  return uploaded;
}

Future<UploadedFile?> freezeAngebotAsBeleg(
  WidgetRef ref,
  AngeboteData a,
  PdfDocumentData data,
) async {
  final db = ref.read(appDatabaseProvider);
  // Bei Angeboten gibt es keine direkte Verknüpfung zu Aufträgen — das PDF
  // wird ohne auftragId archiviert (landet ggf. nicht in einem Akten-Tab).
  final uploaded = await archivePdf(
    ref,
    data,
    prefix: 'belege/angebote',
    auftragId: null,
  );
  if (uploaded == null) return null;
  await (db.update(db.angebote)..where((t) => t.id.equals(a.id))).write(
    AngeboteCompanion(
      pdfStorageUrl: Value(uploaded.storageUrl),
      pdfDateiname: Value(uploaded.dateiname),
      pdfGroesse: Value(uploaded.groesse ?? 0),
      pdfErstelltAm: Value(DateTime.now()),
      status:
          a.status == 'entwurf' ? const Value('versendet') : const Value.absent(),
      updatedAt: Value(DateTime.now()),
    ),
  );
  return uploaded;
}

/// Speichert das PDF sofort lokal in der Dokumente-Tabelle (Bytes in `daten`)
/// und versucht danach den Cloud-Upload im Hintergrund.
///
/// Gibt immer true zurück, sobald die lokale Ablage erfolgreich war.
/// Ohne verknüpfte [auftragId] wird nur der Cloud-Upload versucht.
Future<bool> archivePdfLokalUndCloud(
  WidgetRef ref,
  PdfDocumentData data, {
  required int? auftragId,
  required String prefix,
}) async {
  final db = ref.read(appDatabaseProvider);
  final bytes = await buildDocumentPdf(data);
  final az = await _aktenzeichenFor(db, auftragId);
  final dateiname = _buildFilename(data, az);
  final safe = dateiname.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final storagePfad = '$prefix/$safe';

  // 1. Sofort lokal in DB ablegen — funktioniert ohne Netz.
  int? dokumentId;
  if (auftragId != null) {
    dokumentId = await ref.read(dokumenteRepositoryProvider).upsert(
          DokumenteCompanion.insert(
            titel: Value(dateiname),
            mimeType: const Value('application/pdf'),
            dateigroesse: Value(bytes.length),
            daten: Value(bytes),
            storagePfad: Value(storagePfad),
            auftragId: Value(auftragId),
            kategorie: Value(data.dokumentTyp),
            datum: Value(data.datum ?? DateTime.now()),
          ),
        );
  }

  // 2. Cloud-Upload im Hintergrund — best-effort, kein Abbruch bei Fehler.
  _uploadImHintergrund(ref, db, bytes, storagePfad, dateiname, dokumentId);
  return true;
}

void _uploadImHintergrund(
  WidgetRef ref,
  AppDatabase db,
  Uint8List bytes,
  String pfad,
  String dateiname,
  int? dokumentId,
) async {
  try {
    final storage = ref.read(storageServiceProvider);
    final auth = ref.read(authServiceProvider);
    if (!storage.enabled || auth.currentUser == null) return;
    final url = await storage.uploadBytes(
      pfad,
      bytes: bytes,
      contentType: 'application/pdf',
    );
    if (url == null || dokumentId == null) return;
    await (db.update(db.dokumente)..where((t) => t.id.equals(dokumentId)))
        .write(DokumenteCompanion(storageUrl: Value(url)));
  } catch (_) {
    // Cloud-Fehler sind nicht kritisch — lokale Kopie ist bereits gesichert.
  }
}

Future<String?> _aktenzeichenFor(AppDatabase db, int? auftragId) async {
  if (auftragId == null) return null;
  final row = await (db.select(db.auftraege)
        ..where((t) => t.id.equals(auftragId)))
      .getSingleOrNull();
  return row?.aktenzeichen;
}
