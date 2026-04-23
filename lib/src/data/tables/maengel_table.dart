import 'package:drift/drift.dart';
import 'auftraege_table.dart';

/// Mängel-Register je Akte: nummerierte Liste aller festgestellten Mängel
/// mit Bauteil, Ursache, Folge, Priorität (A/B/C nach DIN 4426) und
/// geschätztem Beseitigungsaufwand. Kann im Gutachten als Anlage
/// eingefügt werden.
class Maengel extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get auftragId =>
      integer().references(Auftraege, #id, onDelete: KeyAction.cascade)();

  /// Laufende Mangel-Nummer innerhalb der Akte (z.B. "M-01").
  TextColumn get nummer => text().nullable()();

  /// Betroffenes Bauteil (z.B. "Dach", "Fassade Nord").
  TextColumn get bauteil => text().nullable()();

  TextColumn get beschreibung => text()();

  /// Vermutete Ursache des Mangels.
  TextColumn get ursache => text().nullable()();

  /// Folgen bei Nicht-Beseitigung.
  TextColumn get folge => text().nullable()();

  /// Priorität nach DIN 4426 — 'A' (unverzüglich), 'B' (mittelfristig),
  /// 'C' (langfristig). Wir speichern den rohen Buchstaben.
  TextColumn get prioritaet => text().withDefault(const Constant('B'))();

  /// Geschätzter Beseitigungsaufwand in Euro (netto).
  RealColumn get aufwand => real().nullable()();

  /// Zusatzinfos (z.B. Foto-IDs, Messwerte) als JSON.
  TextColumn get extras => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
