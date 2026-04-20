import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database_provider.dart';

/// Zählt pro Auftrag (by auftragId) die zugeordneten Einträge in jedem Modul.
/// Die Provider-Families sind `family<int, int>` — der Parameter ist die
/// `auftragId`. Sie liefern live aktualisierte Counts via Drift-Streams.

final stundenCountProvider = StreamProvider.family<int, int>((ref, auftragId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.stunden)
        ..where((t) => t.auftragId.equals(auftragId)))
      .watch()
      .map((l) => l.length);
});

final auslagenCountProvider =
    StreamProvider.family<int, int>((ref, auftragId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.auslagen)
        ..where((t) => t.auftragId.equals(auftragId)))
      .watch()
      .map((l) => l.length);
});

final rechnungenCountProvider =
    StreamProvider.family<int, int>((ref, auftragId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.rechnungen)
        ..where((t) => t.auftragId.equals(auftragId)))
      .watch()
      .map((l) => l.length);
});

final angeboteCountProvider =
    StreamProvider.family<int, int?>((ref, kundeId) {
  final db = ref.watch(appDatabaseProvider);
  if (kundeId == null) return Stream.value(0);
  return (db.select(db.angebote)
        ..where((t) => t.kundeId.equals(kundeId)))
      .watch()
      .map((l) => l.length);
});

final gutachtenCountProvider =
    StreamProvider.family<int, int>((ref, auftragId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.gutachten)
        ..where((t) => t.auftragId.equals(auftragId)))
      .watch()
      .map((l) => l.length);
});

final fotosCountProvider = StreamProvider.family<int, int>((ref, auftragId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.fotos)
        ..where((t) => t.auftragId.equals(auftragId)))
      .watch()
      .map((l) => l.length);
});

final dokumenteCountProvider =
    StreamProvider.family<int, int>((ref, auftragId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.dokumente)
        ..where((t) => t.auftragId.equals(auftragId)))
      .watch()
      .map((l) => l.length);
});

final normenCountProvider = StreamProvider.family<int, int>((ref, auftragId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.normen)
        ..where((t) => t.auftragId.equals(auftragId)))
      .watch()
      .map((l) => l.length);
});

final erlaeuterungenCountProvider =
    StreamProvider.family<int, int>((ref, auftragId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.erlaeuterungen)
        ..where((t) => t.auftragId.equals(auftragId)))
      .watch()
      .map((l) => l.length);
});

final geraeteCountProvider = StreamProvider.family<int, int>((ref, auftragId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.auftraegeGeraete)
        ..where((t) => t.auftragId.equals(auftragId)))
      .watch()
      .map((l) => l.length);
});

final anschreibenCountProvider =
    StreamProvider.family<int, int>((ref, auftragId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.anschreiben)
        ..where((t) => t.auftragId.equals(auftragId)))
      .watch()
      .map((l) => l.length);
});

final wiedervorlagenCountProvider =
    StreamProvider.family<int, int>((ref, auftragId) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.wiedervorlagen)
        ..where((t) => t.auftragId.equals(auftragId)))
      .watch()
      .map((l) => l.length);
});
