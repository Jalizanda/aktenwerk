import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Ergebnis eines Normen-Imports aus einer JSON-Datei.
class NormenImportReport {
  const NormenImportReport({
    required this.neu,
    required this.aktualisiert,
    required this.uebersprungen,
  });
  final int neu;
  final int aktualisiert;
  final int uebersprungen;

  int get gesamt => neu + aktualisiert + uebersprungen;
}

/// Importiert eine Normen-JSON-Datei. Bestehende Einträge (Match auf
/// `nummer`, case-insensitive, getrimmt) werden überschrieben — neue
/// angelegt. Nur Katalog-Normen (ohne `auftrag_id`) werden gematcht,
/// auftragsspezifische Normen bleiben unangetastet.
///
/// Das JSON darf mojibake-codierte deutsche Umlaute enthalten (Latin-1
/// → UTF-8 doppelt codiert, z. B. `SchalldÃ¤mmung`). Diese werden
/// automatisch repariert.
Future<NormenImportReport> importiereNormenJson(
  WidgetRef ref,
  Uint8List bytes,
) async {
  final text = utf8.decode(bytes, allowMalformed: true);
  final decoded = jsonDecode(text);
  if (decoded is! List) {
    throw FormatException(
        'JSON muss eine Liste von Normen sein (Array-Top-Level).');
  }

  final db = ref.read(appDatabaseProvider);

  // Bestehende Katalog-Normen (ohne auftragId) für Match-Lookup holen.
  final bestehend = await (db.select(db.normen)
        ..where((t) => t.auftragId.isNull()))
      .get();
  final byNummer = <String, int>{
    for (final n in bestehend) n.nummer.toLowerCase().trim(): n.id,
  };

  var neu = 0;
  var aktualisiert = 0;
  var uebersprungen = 0;
  final jetzt = DateTime.now();

  await db.transaction(() async {
    for (final raw in decoded) {
      if (raw is! Map) {
        uebersprungen++;
        continue;
      }
      final m = raw;
      final nummer = _fixMojibake(_str(m['Nummer / Kennung'])).trim();
      if (nummer.isEmpty) {
        uebersprungen++;
        continue;
      }

      final titel = _fixMojibake(_str(m['Titel']));
      final ausgabe = _fixMojibake(_str(m['Ausgabe / Version']));
      final kategorie =
          _fixMojibake(_str(m['Kategorie'])).ifEmpty('Norm');
      final art = _fixMojibake(_str(m['Art']));
      final herausgeber = _fixMojibake(_str(m['Herausgeber']));
      final relevanz = _fixMojibake(_str(m['Relevanz']));
      final zusammenfassung =
          _fixMojibake(_str(m['Zusammenfassung / Kernaussage']));
      final zitat =
          _fixMojibake(_str(m['Zitat / Keywords / Meta-Tags']));
      final beschreibung =
          _fixMojibake(_str(m['Beschreibung / Gewerke']));
      final gewerk =
          _fixMojibake(_str(m['Gewerke (primär)'])).trim();
      final erwarteterDateiname =
          _fixMojibake(_str(m['Dateiname'])).trim();

      // Erwarteten PDF-Dateinamen in extras persistieren — dient später
      // dem automatischen Match beim PDF-Massen-Upload.
      final extrasJson = erwarteterDateiname.isEmpty
          ? null
          : jsonEncode({'erwarteterDateiname': erwarteterDateiname});

      final match = byNummer[nummer.toLowerCase()];
      if (match != null) {
        await (db.update(db.normen)..where((t) => t.id.equals(match)))
            .write(NormenCompanion(
          titel: _val(titel),
          ausgabe: _val(ausgabe),
          kategorie: _val(kategorie),
          art: _val(art),
          herausgeber: _val(herausgeber),
          relevanz: _val(relevanz),
          zusammenfassung: _val(zusammenfassung),
          zitat: _val(zitat),
          beschreibung: _val(beschreibung),
          gewerk: _val(gewerk),
          extras: extrasJson == null
              ? const Value<String>.absent()
              : Value(extrasJson),
          updatedAt: Value(jetzt),
        ));
        aktualisiert++;
      } else {
        await db.into(db.normen).insert(
              NormenCompanion.insert(
                nummer: nummer,
                titel: _val(titel),
                ausgabe: _val(ausgabe),
                kategorie: _val(kategorie),
                art: _val(art),
                herausgeber: _val(herausgeber),
                relevanz: _val(relevanz),
                zusammenfassung: _val(zusammenfassung),
                zitat: _val(zitat),
                beschreibung: _val(beschreibung),
                gewerk: _val(gewerk),
                extras: extrasJson == null
                    ? const Value<String>.absent()
                    : Value(extrasJson),
                aktiv: const Value(true),
                favorit: const Value(false),
              ),
            );
        neu++;
      }
    }
  });

  return NormenImportReport(
    neu: neu,
    aktualisiert: aktualisiert,
    uebersprungen: uebersprungen,
  );
}

String _str(Object? v) => v is String ? v : '';

Value<String> _val(String s) =>
    s.trim().isEmpty ? const Value<String>.absent() : Value(s.trim());

/// Dreht Latin-1-als-UTF-8-Doppelcodierung um. Aus `SchalldÃ¤mmung`
/// wird `Schalldämmung`. Schleicht bei unmöglichen Byte-Folgen
/// unauffällig zurück auf den Originalstring.
String _fixMojibake(String s) {
  if (s.isEmpty) return s;
  // Heuristik: Nur fixen, wenn klassische Mojibake-Marker drin sind.
  if (!s.contains('Ã') && !s.contains('Â')) return s;
  try {
    final bytes = latin1.encode(s);
    return utf8.decode(bytes);
  } catch (_) {
    return s;
  }
}

extension _StringHelper on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
