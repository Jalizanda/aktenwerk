import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';

/// Vergleicht die aktuelle Akte mit anderen Akten im gleichen
/// Sachgebiet: Stunden, Netto-Honorar und Bearbeitungsdauer.
class AkteBenchmarkCard extends ConsumerWidget {
  const AkteBenchmarkCard({super.key, required this.auftrag});
  final AuftraegeData auftrag;

  static final _money = NumberFormat.currency(
      locale: 'de_DE', symbol: '€', decimalDigits: 2);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<_BenchmarkDaten>(
      future: _load(ref),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const SizedBox(
              height: 60, child: Center(child: CircularProgressIndicator()));
        }
        final d = snap.data!;
        if (d.vergleichsAnzahl == 0) {
          return _Kachel(
            title: 'Kosten-Benchmark',
            child: Text(
              'Noch keine vergleichbaren Akten (gleiches Sachgebiet) vorhanden.',
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
          );
        }
        return _Kachel(
          title:
              'Benchmark (${d.vergleichsAnzahl} vergleichbare Akten · Sachgebiet: ${auftrag.sachgebiet ?? 'unbekannt'})',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Zeile(
                label: 'Stunden',
                ist: '${d.stundenDieseAkte.toStringAsFixed(1)} h',
                schnitt: '⌀ ${d.stundenSchnitt.toStringAsFixed(1)} h',
                delta: d.stundenDieseAkte - d.stundenSchnitt,
                einheit: 'h',
              ),
              _Zeile(
                label: 'Honorar netto',
                ist: _money.format(d.nettoDieseAkte),
                schnitt: '⌀ ${_money.format(d.nettoSchnitt)}',
                delta: d.nettoDieseAkte - d.nettoSchnitt,
                einheit: '€',
              ),
              _Zeile(
                label: 'Dauer Auftrag → Abschluss',
                ist: d.dauerDieseAkteTage == null
                    ? 'offen'
                    : '${d.dauerDieseAkteTage} Tage',
                schnitt: '⌀ ${d.dauerSchnittTage.toStringAsFixed(0)} Tage',
                delta: d.dauerDieseAkteTage == null
                    ? null
                    : d.dauerDieseAkteTage! - d.dauerSchnittTage,
                einheit: 'T',
              ),
            ],
          ),
        );
      },
    );
  }

  Future<_BenchmarkDaten> _load(WidgetRef ref) async {
    final db = ref.read(appDatabaseProvider);
    final sachgebiet = auftrag.sachgebiet;

    final alleAuftraege = await db.select(db.auftraege).get();
    final vergleich = alleAuftraege
        .where((a) => a.id != auftrag.id && a.sachgebiet == sachgebiet)
        .toList();

    final stunden = await db.select(db.stunden).get();
    final rechnungen = await db.select(db.rechnungen).get();

    double stundenFuer(int auftragId) {
      final list = stunden.where((s) => s.auftragId == auftragId);
      return list.fold<double>(0, (a, s) => a + s.minuten / 60.0);
    }

    double nettoFuer(int auftragId) {
      final list = rechnungen
          .where((r) => r.auftragId == auftragId && r.status != 'storniert');
      return list.fold<double>(0, (a, r) => a + r.netto);
    }

    int? dauerTageFuer(AuftraegeData a) {
      final start = a.createdAt;
      final ende = a.abschlussAm;
      if (ende == null) return null;
      return ende.difference(start).inDays;
    }

    final stundenDieseAkte = stundenFuer(auftrag.id);
    final nettoDieseAkte = nettoFuer(auftrag.id);
    final dauerDieseAkte = dauerTageFuer(auftrag);

    if (vergleich.isEmpty) {
      return _BenchmarkDaten(
        vergleichsAnzahl: 0,
        stundenDieseAkte: stundenDieseAkte,
        stundenSchnitt: 0,
        nettoDieseAkte: nettoDieseAkte,
        nettoSchnitt: 0,
        dauerDieseAkteTage: dauerDieseAkte,
        dauerSchnittTage: 0,
      );
    }

    final stundenSchnitt = vergleich
            .map((a) => stundenFuer(a.id))
            .fold<double>(0, (x, y) => x + y) /
        vergleich.length;
    final nettoSchnitt = vergleich
            .map((a) => nettoFuer(a.id))
            .fold<double>(0, (x, y) => x + y) /
        vergleich.length;
    final dauerWerte =
        vergleich.map(dauerTageFuer).whereType<int>().toList();
    final dauerSchnittTage = dauerWerte.isEmpty
        ? 0.0
        : dauerWerte.fold<int>(0, (a, b) => a + b) / dauerWerte.length;

    return _BenchmarkDaten(
      vergleichsAnzahl: vergleich.length,
      stundenDieseAkte: stundenDieseAkte,
      stundenSchnitt: stundenSchnitt,
      nettoDieseAkte: nettoDieseAkte,
      nettoSchnitt: nettoSchnitt,
      dauerDieseAkteTage: dauerDieseAkte,
      dauerSchnittTage: dauerSchnittTage,
    );
  }
}

class _BenchmarkDaten {
  final int vergleichsAnzahl;
  final double stundenDieseAkte;
  final double stundenSchnitt;
  final double nettoDieseAkte;
  final double nettoSchnitt;
  final int? dauerDieseAkteTage;
  final double dauerSchnittTage;
  const _BenchmarkDaten({
    required this.vergleichsAnzahl,
    required this.stundenDieseAkte,
    required this.stundenSchnitt,
    required this.nettoDieseAkte,
    required this.nettoSchnitt,
    required this.dauerDieseAkteTage,
    required this.dauerSchnittTage,
  });
}

class _Kachel extends StatelessWidget {
  const _Kachel({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          const Divider(),
          child,
        ],
      ),
    );
  }
}

class _Zeile extends StatelessWidget {
  const _Zeile({
    required this.label,
    required this.ist,
    required this.schnitt,
    required this.delta,
    required this.einheit,
  });
  final String label;
  final String ist;
  final String schnitt;
  final double? delta;
  final String einheit;

  @override
  Widget build(BuildContext context) {
    String? deltaText;
    Color? deltaColor;
    if (delta != null && delta!.abs() > 0.001) {
      final sign = delta! > 0 ? '+' : '−';
      deltaText =
          '$sign${delta!.abs().toStringAsFixed(1)} $einheit vs. Schnitt';
      deltaColor = delta! > 0 ? AwTokens.red : AwTokens.green;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: AppTheme.slate500)),
          ),
          SizedBox(
            width: 110,
            child: Text(ist,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            width: 140,
            child: Text(schnitt,
                style: TextStyle(
                    fontSize: 12, color: AppTheme.slate500)),
          ),
          if (deltaText != null)
            Expanded(
              child: Text(deltaText,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: deltaColor)),
            ),
        ],
      ),
    );
  }
}
