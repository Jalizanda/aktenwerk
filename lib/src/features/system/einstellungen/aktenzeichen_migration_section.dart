import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import 'einstellungen_repository.dart';
import 'nummernkreis_service.dart';

/// Einmaliger Migrations-Helfer: alle Akten, deren Aktenzeichen noch nicht
/// dem konfigurierten AW-Schema entspricht (z. B. Legacy-Format
/// `2026-002`), bekommen aus dem Aktenzeichen-Nummernkreis eine fortlaufende
/// AW-Nummer zugewiesen. Bestehende AW-Nummern bleiben unangetastet.
class AktenzeichenMigrationSection extends ConsumerStatefulWidget {
  const AktenzeichenMigrationSection({super.key});

  @override
  ConsumerState<AktenzeichenMigrationSection> createState() =>
      _AktenzeichenMigrationSectionState();
}

class _AktenzeichenMigrationSectionState
    extends ConsumerState<AktenzeichenMigrationSection> {
  bool _busy = false;
  String? _result;
  String? _error;

  /// Akten, deren AZ vom konfigurierten Muster abweichen — entweder
  /// gar kein AW-Präfix (Legacy `2026-002`) oder zu kurze Stellenzahl
  /// (`AW-005` bei Muster `AW-{NNNN}`).
  Future<({List<AuftraegeData> ohnePraefix, List<AuftraegeData> falscheBreite})>
      _findeKandidaten(String praefix, int breite) async {
    final db = ref.read(appDatabaseProvider);
    final all = await db.select(db.auftraege).get();
    final ohnePraefix = <AuftraegeData>[];
    final falscheBreite = <AuftraegeData>[];
    final padRe = RegExp(r'(\d+)$');
    for (final a in all) {
      final az = a.aktenzeichen?.trim() ?? '';
      if (az.isEmpty ||
          !az.toUpperCase().startsWith(praefix.toUpperCase())) {
        ohnePraefix.add(a);
        continue;
      }
      final m = padRe.firstMatch(az);
      if (m != null && m.group(1)!.length != breite) {
        falscheBreite.add(a);
      }
    }
    return (ohnePraefix: ohnePraefix, falscheBreite: falscheBreite);
  }

  String _praefixAusMuster(String muster) {
    // Alles vor der ersten Platzhalter-Klammer ist der Präfix.
    final idx = muster.indexOf('{');
    if (idx <= 0) return 'AW-';
    return muster.substring(0, idx);
  }

  /// Liest aus dem Muster `AW-{NNNN}` die gewünschte Zähler-Breite (4).
  /// Akzeptiert {N}, {NN}, {NNN}, {NNNN}.
  int _breiteAusMuster(String muster) {
    for (final width in [4, 3, 2, 1]) {
      if (muster.contains('{${'N' * width}}')) return width;
    }
    return 4;
  }

  Future<void> _vorschau() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final repo = ref.read(einstellungenRepositoryProvider);
      final muster = await repo.getOr(
          SettingsKeys.nummernkreisAktenzeichen, 'AW-{NNNN}');
      final praefix = _praefixAusMuster(muster);
      final breite = _breiteAusMuster(muster);
      final res = await _findeKandidaten(praefix, breite);
      final teile = <String>[];
      if (res.ohnePraefix.isNotEmpty) {
        teile.add(
            '${res.ohnePraefix.length} Akte(n) OHNE "$praefix"-Präfix '
            '(bekommen neue AW-Nummer aus dem Zähler):\n'
            '${res.ohnePraefix.map((a) => "  • ${a.aktenzeichen ?? "(leer)"}  →  ${a.betreff ?? a.bezeichnung ?? "—"}").join("\n")}');
      }
      if (res.falscheBreite.isNotEmpty) {
        final padRe = RegExp(r'(\d+)$');
        teile.add(
            '${res.falscheBreite.length} Akte(n) mit falscher Stellenzahl '
            '(werden auf $breite Stellen zero-padded):\n'
            '${res.falscheBreite.map((a) {
          final az = a.aktenzeichen ?? "";
          final m = padRe.firstMatch(az);
          final neu = m == null
              ? az
              : '${az.substring(0, m.start)}${m.group(1)!.padLeft(breite, "0")}';
          return "  • $az  →  $neu";
        }).join("\n")}');
      }
      setState(() {
        _result = teile.isEmpty
            ? 'Alle Akten entsprechen bereits dem Muster "$muster".'
            : teile.join('\n\n');
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _migrieren() async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Aktenzeichen vereinheitlichen?'),
        content: const Text(
          'Alle Akten ohne AW-Präfix erhalten eine fortlaufende '
          'AW-Nummer aus deinem Nummernkreis. Bestehende AW-Akten '
          'bleiben unverändert. Diese Aktion kann nicht rückgängig '
          'gemacht werden — bitte vorher ein Backup ziehen.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Vereinheitlichen'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final db = ref.read(appDatabaseProvider);
      final repo = ref.read(einstellungenRepositoryProvider);
      final nk = ref.read(nummernkreisServiceProvider);

      final muster = await repo.getOr(
          SettingsKeys.nummernkreisAktenzeichen, 'AW-{NNNN}');
      final praefix = _praefixAusMuster(muster);
      final breite = _breiteAusMuster(muster);

      // Erst Zähler an höchste vergebene AW-Nummer angleichen.
      final all = await db.select(db.auftraege).get();
      await nk.syncCounterToHighestUsed(
        NummernkreisTyp.akte,
        all.map((a) => a.aktenzeichen),
      );

      final res = await _findeKandidaten(praefix, breite);
      final umbenannt = <String>[];
      final padRe = RegExp(r'(\d+)$');

      // Schritt 1: Akten ohne Präfix bekommen eine NEUE Nummer aus
      // dem Zähler.
      for (final a in res.ohnePraefix) {
        final neu = await nk.nextNumber(NummernkreisTyp.akte);
        await (db.update(db.auftraege)..where((t) => t.id.equals(a.id)))
            .write(AuftraegeCompanion(
          aktenzeichen: Value(neu),
          updatedAt: Value(DateTime.now()),
        ));
        umbenannt.add('${a.aktenzeichen ?? "(leer)"}  →  $neu');
      }

      // Schritt 2: Akten mit falscher Stellenzahl behalten ihre Zahl,
      // werden aber auf die konfigurierte Breite zero-padded.
      for (final a in res.falscheBreite) {
        final az = a.aktenzeichen ?? '';
        final m = padRe.firstMatch(az);
        if (m == null) continue;
        final neu = '${az.substring(0, m.start)}'
            '${m.group(1)!.padLeft(breite, '0')}';
        if (neu == az) continue;
        await (db.update(db.auftraege)..where((t) => t.id.equals(a.id)))
            .write(AuftraegeCompanion(
          aktenzeichen: Value(neu),
          updatedAt: Value(DateTime.now()),
        ));
        umbenannt.add('$az  →  $neu');
      }

      setState(() {
        _result = umbenannt.isEmpty
            ? 'Keine Akten mussten umbenannt werden.'
            : 'Erfolgreich umbenannt:\n${umbenannt.map((e) => "  • $e").join("\n")}';
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.drive_file_rename_outline,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Aktenzeichen vereinheitlichen',
                    style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Findet alle Akten, deren Aktenzeichen nicht zum konfigurierten '
              'Muster passt:\n'
              '• Akten ohne AW-Präfix (z. B. Legacy "2026-002") bekommen '
              'eine neue, fortlaufende AW-Nummer aus dem Zähler.\n'
              '• Akten mit AW-Präfix aber falscher Stellenzahl (z. B. '
              '"AW-005" bei Muster "AW-{NNNN}") werden zero-padded auf '
              'die korrekte Breite ("AW-0005").',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _vorschau,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Vorschau (nur prüfen)'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _migrieren,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: const Text('Vereinheitlichen'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!,
                    style: TextStyle(
                        color: theme.colorScheme.onErrorContainer)),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(_result!,
                    style: theme.textTheme.bodySmall),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
