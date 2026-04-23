import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../features/akten/rechnungen/zahlungsziel_vorlagen.dart';
import '../../../shared/widgets/form_widgets.dart';
import 'einstellungen_repository.dart';

/// Einstellungen-Kachel: CRUD für die Zahlungsziel-Vorlagen, die im
/// Rechnungs-Editor als Dropdown „Zahlungsbedingung" erscheinen.
class ZahlungszieleSection extends ConsumerStatefulWidget {
  const ZahlungszieleSection({super.key});
  @override
  ConsumerState<ZahlungszieleSection> createState() =>
      _ZahlungszieleSectionState();
}

class _ZahlungszieleSectionState
    extends ConsumerState<ZahlungszieleSection> {
  List<ZahlungszielVorlage>? _vorlagen;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = ref.read(einstellungenRepositoryProvider);
    final list = await ladeZahlungszielVorlagen(repo);
    if (mounted) {
      setState(() {
        _vorlagen = [...list];
        _loading = false;
      });
    }
  }

  Future<void> _speichern() async {
    if (_vorlagen == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(einstellungenRepositoryProvider);
      await speichereZahlungszielVorlagen(repo, _vorlagen!);
      ref.invalidate(zahlungszielVorlagenProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Zahlungsziel-Vorlagen gespeichert.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _zuruecksetzen() async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('Zurücksetzen?'),
        content: const Text(
            'Alle eigenen Zahlungsziel-Vorlagen werden durch die Aktenwerk-Standards ersetzt.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Zurücksetzen')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _vorlagen = [...zahlungszielVorlagenDefaults]);
  }

  Future<void> _neu() async {
    final neu = await showDialog<ZahlungszielVorlage>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const _VorlageEditor(),
    );
    if (neu == null || _vorlagen == null) return;
    setState(() => _vorlagen = [..._vorlagen!, neu]);
  }

  Future<void> _bearbeiten(int i) async {
    final aktuell = _vorlagen![i];
    final neu = await showDialog<ZahlungszielVorlage>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _VorlageEditor(eintrag: aktuell),
    );
    if (neu == null) return;
    setState(() {
      _vorlagen![i] = neu;
    });
  }

  void _loeschen(int i) {
    setState(() => _vorlagen!.removeAt(i));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final list = _vorlagen ?? const <ZahlungszielVorlage>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vorlagen erscheinen im Rechnungs-Editor als Dropdown '
          '„Zahlungsbedingung". Beim Auswählen werden Zahlungsziel, '
          'Fälligkeit und Schlusstext automatisch gesetzt; bei Skonto '
          'rechnet Aktenwerk den Zahlbetrag live aus.',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('— keine Vorlagen —'),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Column(
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  ListTile(
                    dense: true,
                    leading: Icon(
                      list[i].bar
                          ? Icons.payments_outlined
                          : list[i].skontoProzent != null
                              ? Icons.percent
                              : Icons.event_outlined,
                      color: AppTheme.accent600,
                    ),
                    title: Text(list[i].label,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(_zusammenfassung(list[i]),
                        style: const TextStyle(fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: 'Bearbeiten',
                          onPressed: () => _bearbeiten(i),
                        ),
                        IconButton(
                          icon:
                              const Icon(Icons.delete_outline, size: 18),
                          tooltip: 'Löschen',
                          onPressed: () => _loeschen(i),
                        ),
                      ],
                    ),
                  ),
                  if (i < list.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _saving ? null : _neu,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Neue Vorlage'),
            ),
            OutlinedButton.icon(
              onPressed: _saving ? null : _zuruecksetzen,
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('Standards wiederherstellen'),
            ),
            FilledButton.tonalIcon(
              onPressed: _saving ? null : _speichern,
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 16),
              label: const Text('Speichern'),
            ),
          ],
        ),
      ],
    );
  }

  String _zusammenfassung(ZahlungszielVorlage v) {
    final parts = <String>[];
    if (v.tage == 0 && v.bar) {
      parts.add('Barzahlung');
    } else if (v.tage == 0) {
      parts.add('sofort fällig');
    } else {
      parts.add('${v.tage} Tage netto');
    }
    if (v.skontoProzent != null && v.skontoTage != null) {
      parts.add(
          '${v.skontoProzent!.toStringAsFixed(1).replaceAll('.', ',')} % Skonto bei ${v.skontoTage} Tagen');
    }
    return parts.join(' · ');
  }
}

class _VorlageEditor extends StatefulWidget {
  const _VorlageEditor({this.eintrag});
  final ZahlungszielVorlage? eintrag;
  @override
  State<_VorlageEditor> createState() => _VorlageEditorState();
}

class _VorlageEditorState extends State<_VorlageEditor> {
  late final _label = TextEditingController(text: widget.eintrag?.label ?? '');
  late final _tage = TextEditingController(
      text: (widget.eintrag?.tage ?? 14).toString());
  late final _text =
      TextEditingController(text: widget.eintrag?.text ?? '');
  late final _skontoProzent = TextEditingController(
      text: widget.eintrag?.skontoProzent?.toString() ?? '');
  late final _skontoTage = TextEditingController(
      text: widget.eintrag?.skontoTage?.toString() ?? '');
  late bool _bar = widget.eintrag?.bar ?? false;

  @override
  void dispose() {
    _label.dispose();
    _tage.dispose();
    _text.dispose();
    _skontoProzent.dispose();
    _skontoTage.dispose();
    super.dispose();
  }

  void _speichern() {
    final label = _label.text.trim();
    if (label.isEmpty) return;
    final tage = int.tryParse(_tage.text.trim()) ?? 0;
    final prozent = double.tryParse(
        _skontoProzent.text.replaceAll(',', '.').trim());
    final skontoTage = int.tryParse(_skontoTage.text.trim());
    final vorlage = ZahlungszielVorlage(
      key: widget.eintrag?.key ??
          label
              .toLowerCase()
              .replaceAll(RegExp(r'\s+'), '_')
              .replaceAll(RegExp(r'[^a-z0-9_]'), ''),
      label: label,
      tage: tage,
      text: _text.text.trim(),
      bar: _bar,
      skontoProzent: prozent == null || prozent <= 0 ? null : prozent,
      skontoTage: (prozent != null && skontoTage != null && skontoTage > 0)
          ? skontoTage
          : null,
    );
    Navigator.of(context, rootNavigator: true).pop(vorlage);
  }

  @override
  Widget build(BuildContext context) {
    return StandardFormDialog(
      title: widget.eintrag == null
          ? 'Neue Zahlungsziel-Vorlage'
          : 'Zahlungsziel-Vorlage bearbeiten',
      icon: Icons.event_available_outlined,
      maxWidth: 620,
      maxHeight: 680,
      onCancel: () => Navigator.of(context, rootNavigator: true).pop(),
      onSave: _speichern,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LabeledField(
              'Bezeichnung (für Dropdown) *',
              TextFormField(controller: _label, autofocus: true),
            ),
            const SizedBox(height: 12),
            Row2(
              left: LabeledField(
                'Zahlungsziel (Tage)',
                TextFormField(
                  controller: _tage,
                  keyboardType: TextInputType.number,
                ),
              ),
              right: Row(
                children: [
                  Checkbox(
                    value: _bar,
                    onChanged: (v) =>
                        setState(() => _bar = v ?? false),
                  ),
                  const Expanded(
                    child: Text(
                        'Barzahlung (Schlusstext: „in bar erhalten ___")'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row2(
              left: LabeledField(
                'Skonto (%)',
                TextFormField(
                  controller: _skontoProzent,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      hintText: 'z. B. 2 oder 3; leer = ohne Skonto'),
                ),
              ),
              right: LabeledField(
                'Skonto-Frist (Tage)',
                TextFormField(
                  controller: _skontoTage,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(hintText: 'z. B. 7 oder 10'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            LabeledField(
              'Schlusstext der Rechnung',
              TextFormField(
                controller: _text,
                minLines: 3,
                maxLines: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
