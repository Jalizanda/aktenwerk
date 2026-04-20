import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../features/akten/kunden/kunden_repository.dart';
import '../../../features/akten/rechnungen/rechnungen_repository.dart';
import '../../../features/system/einstellungen/absender_service.dart';
import '../../../shared/pdf/document_pdf.dart';
import '../../../shared/pdf/pdf_archiver.dart';
import '../../../shared/positionen/position_model.dart';
import '../../../shared/widgets/date_field.dart';
import '../../../shared/widgets/form_widgets.dart';

Future<void> showOposZahlungDialog(
  BuildContext context,
  WidgetRef ref, {
  required RechnungWithKunde rechnung,
}) async {
  await showDialog(
    context: context,
    useRootNavigator: true,
    builder: (_) => _OposZahlungDialog(eintrag: rechnung),
  );
}

class _OposZahlungDialog extends ConsumerStatefulWidget {
  const _OposZahlungDialog({required this.eintrag});
  final RechnungWithKunde eintrag;
  @override
  ConsumerState<_OposZahlungDialog> createState() =>
      _OposZahlungDialogState();
}

class _OposZahlungDialogState extends ConsumerState<_OposZahlungDialog> {
  static final _money =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);
  static final _dateFmt = DateFormat('dd.MM.yyyy', 'de');

  late final _betrag = TextEditingController();
  late final _skonto = TextEditingController(text: '0');
  late final _notiz = TextEditingController();
  DateTime _zahlungsdatum = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _betrag.dispose();
    _skonto.dispose();
    _notiz.dispose();
    super.dispose();
  }

  double get _offen =>
      widget.eintrag.rechnung.brutto - widget.eintrag.rechnung.bezahlt;

  int get _alter {
    final f = widget.eintrag.rechnung.faelligAm;
    if (f == null) return 0;
    return DateTime.now().difference(f).inDays;
  }

  int get _mahnstufe {
    final a = _alter;
    if (a > 35) return 3;
    if (a > 14) return 2;
    if (a > 0) return 1;
    return 0;
  }

  Future<void> _zahlungErfassen({bool voll = false}) async {
    setState(() => _saving = true);
    final r = widget.eintrag.rechnung;
    final zahlBetrag = voll
        ? _offen
        : (double.tryParse(_betrag.text.replaceAll(',', '.')) ?? 0);
    final skontoProz =
        double.tryParse(_skonto.text.replaceAll(',', '.')) ?? 0;
    // Skonto wird vom Brutto-Betrag der Rechnung abgezogen (vereinfachte
    // Variante: neue bezahlt = bestehendes bezahlt + zahlBetrag; Differenz
    // zur Skonto-Reduktion als "anerkannter Abzug" in der Notiz).
    final skontoAbzug = skontoProz > 0 ? r.brutto * skontoProz / 100 : 0;
    final neuerBezahlt = r.bezahlt + zahlBetrag + skontoAbzug;
    final vollBezahlt = neuerBezahlt >= r.brutto - 0.005;
    final db = ref.read(appDatabaseProvider);
    final bestehendeNotiz = (r.notiz ?? '').trim();
    final zahlNotiz = <String>[
      if (bestehendeNotiz.isNotEmpty) bestehendeNotiz,
      'Zahlung ${_dateFmt.format(_zahlungsdatum)}: '
          '${_money.format(zahlBetrag)}'
          '${skontoProz > 0 ? " (Skonto ${skontoProz.toStringAsFixed(1)} % = ${_money.format(skontoAbzug)})" : ""}'
          '${_notiz.text.trim().isNotEmpty ? " — ${_notiz.text.trim()}" : ""}',
    ].join('\n');

    await (db.update(db.rechnungen)..where((t) => t.id.equals(r.id))).write(
      RechnungenCompanion(
        bezahlt: Value(neuerBezahlt),
        bezahltAm: Value(vollBezahlt ? _zahlungsdatum : r.bezahltAm),
        status: Value(vollBezahlt ? 'bezahlt' : 'teilbezahlt'),
        notiz: Value(zahlNotiz),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(vollBezahlt
                ? 'Rechnung vollständig bezahlt gesetzt.'
                : 'Teilzahlung erfasst: ${_money.format(zahlBetrag)}')),
      );
    }
  }

  Future<void> _mahnungErstellen() async {
    setState(() => _saving = true);
    final r = widget.eintrag.rechnung;
    final absender = await absenderFromSettings(ref);
    final stufe = _mahnstufe == 0 ? 1 : _mahnstufe;
    final stufeLabel = switch (stufe) {
      1 => 'Zahlungserinnerung',
      2 => '1. Mahnung',
      _ => '2. Mahnung',
    };
    final mahngebuhr = switch (stufe) {
      1 => 0.0,
      2 => 5.0,
      _ => 10.0,
    };

    final nr =
        'M-${r.rechnungsnummer ?? r.id}-${DateTime.now().millisecondsSinceEpoch ~/ 10000}';
    final positionen = <Position>[
      Position(
        bezeichnung: 'Offene Rechnung ${r.rechnungsnummer ?? ""} '
            'vom ${r.rechnungsdatum == null ? "—" : _dateFmt.format(r.rechnungsdatum!)}',
        langtext:
            'Fälligkeitsdatum: ${r.faelligAm == null ? "—" : _dateFmt.format(r.faelligAm!)}\n'
            'Überfällig seit: $_alter Tagen\n'
            'Bereits bezahlt: ${_money.format(r.bezahlt)}',
        menge: 1,
        einheit: 'Pos.',
        einzelpreis: _offen,
        ustSatz: 0,
      ),
      if (mahngebuhr > 0)
        Position(
          bezeichnung: 'Mahngebühr ($stufeLabel)',
          menge: 1,
          einheit: 'Pos.',
          einzelpreis: mahngebuhr,
          ustSatz: 0,
        ),
    ];

    final intro = switch (stufe) {
      1 =>
        'mit dieser Zahlungserinnerung möchten wir Sie freundlich darauf hinweisen, '
            'dass die oben genannte Rechnung bislang nicht ausgeglichen wurde. '
            'Bitte überweisen Sie den offenen Betrag bis zum '
            '${_dateFmt.format(DateTime.now().add(const Duration(days: 7)))}.',
      2 =>
        'trotz unserer Zahlungserinnerung ist der Rechnungsbetrag noch nicht '
            'beglichen. Wir bitten Sie dringend, den offenen Betrag zuzüglich '
            'Mahngebühr bis zum '
            '${_dateFmt.format(DateTime.now().add(const Duration(days: 7)))} '
            'zu überweisen.',
      _ =>
        'trotz mehrfacher Mahnung ist der offene Betrag weiterhin nicht '
            'beglichen. Sollte die Zahlung nicht bis zum '
            '${_dateFmt.format(DateTime.now().add(const Duration(days: 7)))} '
            'eingehen, behalten wir uns weitere rechtliche Schritte vor.',
    };

    final pdfData = PdfDocumentData(
      dokumentTyp: stufeLabel,
      dokumentNr: nr,
      datum: DateTime.now(),
      aktenzeichen: widget.eintrag.auftrag?.aktenzeichen,
      betreff: 'Betrifft Rechnung ${r.rechnungsnummer ?? ""}',
      positionen: positionen,
      kopftext: intro,
      fusstext: 'Mit freundlichen Grüßen',
      absender: absender,
      empfaenger: widget.eintrag.kunde,
      brutto: _offen + mahngebuhr,
      mitSepaQr: true,
    );

    final uploaded = await archivePdf(
      ref,
      pdfData,
      prefix: 'mahnungen',
      auftragId: r.auftragId,
      aktenzeichen: widget.eintrag.auftrag?.aktenzeichen,
    );
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    if (uploaded == null) {
      // Fallback: wenigstens Preview zeigen.
      await previewDocumentPdf(pdfData);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Mahnung als PDF angezeigt (Cloud-Upload nicht verfügbar).')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Mahnung archiviert: ${uploaded.dateiname}')));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.eintrag.rechnung;
    final kunde = widget.eintrag.kunde;
    final faellig = r.faelligAm;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.payments_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Zahlung / Mahnung: ${r.rechnungsnummer ?? "Rechnung"}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          kunde == null
                              ? 'Kein Auftraggeber'
                              : kundeAnzeigename(kunde),
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.slate500),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.slate50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _infoRow('Brutto', _money.format(r.brutto)),
                    _infoRow('Bereits bezahlt', _money.format(r.bezahlt)),
                    _infoRow('Offen', _money.format(_offen), bold: true),
                    if (faellig != null)
                      _infoRow(
                          'Fällig am',
                          '${_dateFmt.format(faellig)} '
                              '(${_alter > 0 ? "+$_alter Tage überfällig" : "${-_alter} T bis Fälligkeit"})'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Neue Zahlung erfassen',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row3(
                a: LabeledField(
                    'Betrag €',
                    TextFormField(
                      controller: _betrag,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    )),
                b: DateField(
                    label: 'Zahlungsdatum',
                    value: _zahlungsdatum,
                    onChanged: (v) => setState(
                        () => _zahlungsdatum = v ?? DateTime.now())),
                c: LabeledField(
                    'Skonto %',
                    TextFormField(
                      controller: _skonto,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    )),
              ),
              const SizedBox(height: 10),
              LabeledField(
                'Notiz',
                TextFormField(
                  controller: _notiz,
                  decoration: const InputDecoration(
                    hintText: 'z. B. "Überweisung von Kunde XY"',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _mahnungErstellen,
                    icon: const Icon(Icons.mark_email_unread_outlined,
                        size: 16),
                    label: Text(
                      switch (_mahnstufe) {
                        0 => 'Zahlungserinnerung',
                        1 => 'Zahlungserinnerung',
                        2 => '1. Mahnung',
                        _ => '2. Mahnung',
                      },
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _zahlungErfassen(),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Zahlung erfassen'),
                  ),
                  FilledButton.icon(
                    onPressed:
                        _saving ? null : () => _zahlungErfassen(voll: true),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Voll bezahlt'),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 12.5))),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
