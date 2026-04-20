import 'package:drift/drift.dart';
import 'auftraege_table.dart';
import 'gutachten_table.dart';

/// Fotos / Lichtbildanlage.
class Fotos extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().nullable().references(Auftraege, #id, onDelete: KeyAction.cascade)();
  IntColumn get gutachtenId =>
      integer().nullable().references(Gutachten, #id, onDelete: KeyAction.setNull)();

  TextColumn get titel => text().nullable()();
  /// Raum- oder Ortszuordnung im Objekt (z. B. "Schlafzimmer OG", "Fassade Ost").
  TextColumn get raum => text().nullable()();
  TextColumn get beschreibung => text().nullable()();

  TextColumn get pfad => text().nullable()();
  TextColumn get mimeType => text().nullable()();

  /// Download-URL aus Firebase Storage (wenn das Foto geclouded wurde).
  TextColumn get storageUrl => text().nullable()();

  /// Storage-Pfad relativ zum User-Ordner (z. B. "fotos/17134…_img.jpg").
  TextColumn get storagePfad => text().nullable()();

  /// Eingebettete Daten (Base64 oder raw) – optional. Nach "Bemalen" enthält
  /// dieses Feld das *bemalte* Bild; das Original bleibt in [originalDaten].
  BlobColumn get daten => blob().nullable()();

  /// Unverändertes Originalbild — wird beim ersten Bemalen gesichert,
  /// damit der Nutzer jederzeit zurückwechseln kann.
  BlobColumn get originalDaten => blob().nullable()();
  TextColumn get originalStorageUrl => text().nullable()();
  TextColumn get originalStoragePfad => text().nullable()();

  DateTimeColumn get aufnahmeAm => dateTime().nullable()();
  RealColumn get lat => real().nullable()();
  RealColumn get lon => real().nullable()();

  IntColumn get reihenfolge => integer().withDefault(const Constant(0))();

  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
