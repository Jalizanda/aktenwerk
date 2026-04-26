import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/geo/plz_autofill.dart';
import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/widgets/signature_pad.dart';
import 'benutzer_repository.dart';

class BenutzerScreen extends ConsumerWidget {
  const BenutzerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeBenutzerProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (b) => _BenutzerForm(key: ValueKey(b?.id ?? 'neu'), benutzer: b),
    );
  }
}

class _BenutzerForm extends ConsumerStatefulWidget {
  const _BenutzerForm({super.key, required this.benutzer});
  final BenutzerData? benutzer;

  @override
  ConsumerState<_BenutzerForm> createState() => _BenutzerFormState();
}

class _BenutzerFormState extends ConsumerState<_BenutzerForm> {
  final _formKey = GlobalKey<FormState>();

  late final _anrede = _tec(widget.benutzer?.anrede);
  late final _titel = _tec(widget.benutzer?.titel);
  late final _vorname = _tec(widget.benutzer?.vorname);
  late final _nachname = _tec(widget.benutzer?.nachname);
  late final _firma = _tec(widget.benutzer?.firma);
  late final _strasse = _tec(widget.benutzer?.strasse);
  late final _plz = _tec(widget.benutzer?.plz);
  late final _ort = _tec(widget.benutzer?.ort);
  late final _telefon = _tec(widget.benutzer?.telefon);
  late final _mobil = _tec(widget.benutzer?.mobil);
  late final _email = _tec(widget.benutzer?.email);
  late final _website = _tec(widget.benutzer?.website);
  late final _steuerNr = _tec(widget.benutzer?.steuerNr);
  late final _ustId = _tec(widget.benutzer?.ustId);
  late final _hrb = _tec(widget.benutzer?.hrb);
  late final _iban = _tec(widget.benutzer?.iban);
  late final _bic = _tec(widget.benutzer?.bic);
  late final _bank = _tec(widget.benutzer?.bank);
  late final _bestellungsText = _tec(widget.benutzer?.bestellungsText);
  late final _gruss = _tec(widget.benutzer?.grussformel);
  late final _standardSatz =
      _tec(widget.benutzer?.standardStundensatz?.toStringAsFixed(2));
  String? _profilBildBase64;
  String? _profilBildMime;
  String? _unterschriftDataUrl;
  final _sigController = SignaturePadController();
  late final VoidCallback _plzAutoFillDispose;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _profilBildBase64 = widget.benutzer?.profilBildBase64;
    _profilBildMime = widget.benutzer?.profilBildMime;
    _unterschriftDataUrl = widget.benutzer?.unterschriftPfad;
    _plzAutoFillDispose = attachPlzAutoFill(_plz, _ort);
  }

  TextEditingController _tec(String? v) => TextEditingController(text: v ?? '');

  @override
  void dispose() {
    _plzAutoFillDispose();
    for (final c in [
      _anrede, _titel, _vorname, _nachname, _firma,
      _strasse, _plz, _ort,
      _telefon, _mobil, _email, _website,
      _steuerNr, _ustId, _hrb, _iban, _bic, _bank,
      _bestellungsText, _gruss, _standardSatz,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(benutzerRepositoryProvider);
    final satz = double.tryParse(_standardSatz.text.trim().replaceAll(',', '.'));
    final companion = BenutzerCompanion(
      anrede: _nt(_anrede),
      titel: _nt(_titel),
      vorname: _nt(_vorname),
      nachname: _nt(_nachname),
      firma: _nt(_firma),
      strasse: _nt(_strasse),
      plz: _nt(_plz),
      ort: _nt(_ort),
      telefon: _nt(_telefon),
      mobil: _nt(_mobil),
      email: _nt(_email),
      website: _nt(_website),
      steuerNr: _nt(_steuerNr),
      ustId: _nt(_ustId),
      hrb: _nt(_hrb),
      iban: _nt(_iban),
      bic: _nt(_bic),
      bank: _nt(_bank),
      bestellungsText: _nt(_bestellungsText),
      grussformel: _nt(_gruss),
      profilBildBase64: Value(_profilBildBase64),
      profilBildMime: Value(_profilBildMime),
      unterschriftPfad: Value(_unterschriftDataUrl),
      standardStundensatz:
          satz == null ? const Value(null) : Value(satz),
    );
    try {
      await repo.saveActive(companion);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil gespeichert')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickProfilBild() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'],
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null || f.size > 1 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Max. 1 MB — bitte kleinere Datei wählen.')));
      }
      return;
    }
    setState(() {
      _profilBildBase64 = base64Encode(f.bytes!);
      _profilBildMime = _mimeForExt(f.extension);
    });
  }

  String _mimeForExt(String? ext) {
    switch ((ext ?? '').toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      default:
        return 'image/png';
    }
  }

  Value<String?> _nt(TextEditingController c) {
    final v = c.text.trim();
    return Value(v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              const Icon(Icons.account_circle_outlined,
                  size: 24, color: AwTokens.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Benutzer',
                        style: theme.textTheme.headlineMedium),
                    Text(
                      'Daten des Sachverständigen für Briefkopf, Rechnungen und Anschreiben',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: const Text('Speichern'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Section('Person', children: [
                      _Row2(
                        left: _L('Anrede', TextFormField(controller: _anrede)),
                        right: _L('Titel', TextFormField(controller: _titel)),
                      ),
                      const SizedBox(height: 12),
                      _Row2(
                        left: _L('Vorname',
                            TextFormField(controller: _vorname)),
                        right: _L('Nachname',
                            TextFormField(controller: _nachname)),
                      ),
                      const SizedBox(height: 12),
                      _L('Firma / Büro',
                          TextFormField(controller: _firma)),
                    ]),
                    _Section('Adresse', children: [
                      _L('Straße',
                          TextFormField(controller: _strasse)),
                      const SizedBox(height: 12),
                      _Row2(
                        flex: const (1, 3),
                        left:
                            _L('PLZ', TextFormField(controller: _plz)),
                        right: _L('Ort', TextFormField(controller: _ort)),
                      ),
                    ]),
                    _Section('Kontakt', children: [
                      _Row2(
                        left: _L(
                          'Telefon',
                          TextFormField(
                              controller: _telefon,
                              keyboardType: TextInputType.phone),
                        ),
                        right: _L(
                          'Mobil',
                          TextFormField(
                              controller: _mobil,
                              keyboardType: TextInputType.phone),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Row2(
                        left: _L(
                          'E-Mail',
                          TextFormField(
                              controller: _email,
                              keyboardType:
                                  TextInputType.emailAddress),
                        ),
                        right: _L(
                          'Website',
                          TextFormField(
                              controller: _website,
                              keyboardType: TextInputType.url),
                        ),
                      ),
                    ]),
                    _Section('Steuer & Bank', children: [
                      _Row2(
                        left: _L('Steuer-Nr.',
                            TextFormField(controller: _steuerNr)),
                        right: _L('USt-ID',
                            TextFormField(controller: _ustId)),
                      ),
                      const SizedBox(height: 12),
                      _L(
                        'HRB / Handelsregister',
                        TextFormField(
                          controller: _hrb,
                          decoration: const InputDecoration(
                            hintText: 'z. B. HRB 12345 (AG Düsseldorf)',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _L('Bank', TextFormField(controller: _bank)),
                      const SizedBox(height: 12),
                      _Row2(
                        flex: const (3, 1),
                        left: _L('IBAN',
                            TextFormField(controller: _iban)),
                        right: _L('BIC',
                            TextFormField(controller: _bic)),
                      ),
                    ]),
                    _Section('Bestellung & Standardwerte', children: [
                      _L(
                        'Standard-Stundensatz (€)',
                        TextFormField(
                          controller: _standardSatz,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _L(
                        'Bestellungstext (für Briefkopf)',
                        TextFormField(
                          controller: _bestellungsText,
                          minLines: 3,
                          maxLines: 6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _L(
                        'Persönliche Grußformel',
                        TextFormField(
                          controller: _gruss,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            hintText:
                                'Mit freundlichen Grüßen\n{Vorname} {Nachname}',
                          ),
                        ),
                      ),
                    ]),
                    _Section('Profilbild', children: [
                      _AvatarPanel(
                        base64: _profilBildBase64,
                        mime: _profilBildMime,
                        onPick: _pickProfilBild,
                        onRemove: () => setState(() {
                          _profilBildBase64 = null;
                          _profilBildMime = null;
                        }),
                      ),
                    ]),
                    _Section('Unterschrift', children: [
                      _SignaturBlock(
                        controller: _sigController,
                        existing: _unterschriftDataUrl,
                        onSaved: (url) =>
                            setState(() => _unterschriftDataUrl = url),
                        onRemoved: () =>
                            setState(() => _unterschriftDataUrl = null),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AvatarPanel extends StatelessWidget {
  const _AvatarPanel({
    required this.base64,
    required this.mime,
    required this.onPick,
    required this.onRemove,
  });
  final String? base64;
  final String? mime;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final has = base64 != null && base64!.isNotEmpty;
    return Row(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: has
              ? (mime == 'image/svg+xml'
                  ? SvgPicture.memory(base64Decode(base64!),
                      fit: BoxFit.cover)
                  : Image.memory(base64Decode(base64!), fit: BoxFit.cover))
              : Icon(Icons.person_outline,
                  size: 44,
                  color: Theme.of(context).colorScheme.outline),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                has
                    ? 'Profilbild hinterlegt (${mime ?? "image"})'
                    : 'Kein Profilbild',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                'PNG, JPG oder SVG · quadratisch, max. 1 MB.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        if (has)
          IconButton(
            tooltip: 'Profilbild entfernen',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: onRemove,
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.upload_file, size: 16),
          label: Text(has ? 'Ersetzen' : 'Profilbild wählen'),
          onPressed: onPick,
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );
}

class _L extends StatelessWidget {
  const _L(this.label, this.child);
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ),
          child,
        ],
      );
}

class _Row2 extends StatelessWidget {
  const _Row2({required this.left, required this.right, this.flex});
  final Widget left;
  final Widget right;
  final (int, int)? flex;
  @override
  Widget build(BuildContext context) {
    final (l, r) = flex ?? (1, 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: l, child: left),
        const SizedBox(width: 12),
        Expanded(flex: r, child: right),
      ],
    );
  }
}


class _SignaturBlock extends StatefulWidget {
  const _SignaturBlock({
    required this.controller,
    required this.existing,
    required this.onSaved,
    required this.onRemoved,
  });
  final SignaturePadController controller;
  final String? existing;
  final void Function(String dataUrl) onSaved;
  final VoidCallback onRemoved;

  @override
  State<_SignaturBlock> createState() => _SignaturBlockState();
}

class _SignaturBlockState extends State<_SignaturBlock> {
  bool _zeichneNeu = false;

  bool get _hatBild =>
      (widget.existing ?? '').trim().isNotEmpty && !_zeichneNeu;

  Uint8List? _decode(String url) {
    try {
      final comma = url.indexOf(',');
      if (comma < 0) return base64Decode(url);
      return base64Decode(url.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_hatBild) {
      final bytes = _decode(widget.existing!);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 320,
            height: 140,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: bytes == null
                ? const Center(child: Text('Kein gültiges Bild'))
                : Image.memory(bytes, fit: BoxFit.contain),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unterschrift hinterlegt',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600)),
                Text(
                  'Wird auf Gutachten und PDF-Briefen mit ausgedruckt.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Neu zeichnen'),
                    onPressed: () {
                      widget.controller.clear();
                      setState(() => _zeichneNeu = true);
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Entfernen'),
                    onPressed: widget.onRemoved,
                  ),
                ]),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Unterschrift mit Maus oder Touch in den Kasten unterhalb '
          'zeichnen, dann „Übernehmen" klicken.',
          style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SignaturePad(controller: widget.controller),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('Unterschrift übernehmen'),
            onPressed: () async {
              final dataUrl = await widget.controller.toDataUrl();
              if (dataUrl == null) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Bitte zuerst eine Unterschrift zeichnen.')),
                  );
                }
                return;
              }
              widget.onSaved(dataUrl);
              setState(() => _zeichneNeu = false);
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Zurücksetzen'),
            onPressed: () => widget.controller.clear(),
          ),
          if ((widget.existing ?? '').isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _zeichneNeu = false),
              child: const Text('Abbrechen'),
            ),
        ]),
      ],
    );
  }
}
