import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../features/akten/auftraege/auftraege_repository.dart';
import '../../../features/akten/rechnungen/rechnungen_repository.dart';
import '../../../features/auswertung/fortbildungen/fortbildungen_repository.dart';
import '../../../shared/widgets/module_scaffold.dart';

class JahresberichtScreen extends ConsumerStatefulWidget {
  const JahresberichtScreen({super.key});
  @override
  ConsumerState<JahresberichtScreen> createState() =>
      _JahresberichtScreenState();
}

class _JahresberichtScreenState
    extends ConsumerState<JahresberichtScreen> {
  int _jahr = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = NumberFormat.currency(locale: 'de', symbol: '€');
    final auftraege = ref.watch(auftraegeListProvider);
    final rechnungen = ref.watch(rechnungenListProvider);
    final fortbSummen = ref.watch(fortbildungenSummenProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.picture_as_pdf_outlined,
          title: 'Jahresbericht',
          subtitle: 'Zusammenfassung für IHK / Bestellungsbehörde',
          filters: [
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _jahr,
                items: [
                  for (var y = DateTime.now().year; y >= DateTime.now().year - 5; y--)
                    DropdownMenuItem(value: y, child: Text('Jahr $y')),
                ],
                onChanged: (v) =>
                    setState(() => _jahr = v ?? DateTime.now().year),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _block(
                    context,
                    'Gutachten nach Art',
                    auftraege.when(
                      data: (list) {
                        final jahr = list
                            .where((a) =>
                                (a.auftrag.auftragAm ??
                                        a.auftrag.eingangAm)
                                    ?.year ==
                                _jahr)
                            .toList();
                        final privat = jahr
                            .where((a) => a.auftrag.art == 'privat')
                            .length;
                        final gericht = jahr
                            .where((a) => a.auftrag.art == 'gericht')
                            .length;
                        return Column(
                          children: [
                            _kv('Privatgutachten', privat.toString()),
                            _kv('Gerichtsgutachten', gericht.toString()),
                            _kv('Gesamt', jahr.length.toString(),
                                bold: true),
                          ],
                        );
                      },
                      loading: () => const CircularProgressIndicator(),
                      error: (e, _) => Text('$e'),
                    ),
                  ),
                  _block(
                    context,
                    'Umsatz',
                    rechnungen.when(
                      data: (list) {
                        double umsatz = 0;
                        double bezahlt = 0;
                        for (final r in list) {
                          if (r.rechnung.rechnungsdatum?.year != _jahr) {
                            continue;
                          }
                          umsatz += r.rechnung.netto;
                          bezahlt += r.rechnung.bezahlt;
                        }
                        return Column(children: [
                          _kv('Umsatz netto', money.format(umsatz)),
                          _kv('Zahlungseingänge',
                              money.format(bezahlt)),
                        ]);
                      },
                      loading: () => const CircularProgressIndicator(),
                      error: (e, _) => Text('$e'),
                    ),
                  ),
                  _block(
                    context,
                    'Fortbildungsstunden',
                    fortbSummen.when(
                      data: (m) => Column(children: [
                        _kv('Stunden $_jahr',
                            (m[_jahr] ?? 0).toStringAsFixed(1)),
                        _kv(
                          'Vorjahr ${_jahr - 1}',
                          (m[_jahr - 1] ?? 0).toStringAsFixed(1),
                        ),
                      ]),
                      loading: () => const CircularProgressIndicator(),
                      error: (e, _) => Text('$e'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Hinweis: Die IHK-PDF-Vorlage wird in einer späteren Phase automatisch befüllt.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _block(BuildContext context, String title, Widget body) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context).textTheme.titleMedium),
                const Divider(),
                body,
              ],
            ),
          ),
        ),
      );

  Widget _kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(k)),
            Text(v,
                style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ],
        ),
      );
}
