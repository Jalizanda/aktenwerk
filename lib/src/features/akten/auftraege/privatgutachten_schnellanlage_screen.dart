import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:signature/signature.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../system/einstellungen/absender_service.dart';
import '../../../data/sync/storage_service.dart';
import '../../system/benutzer/benutzer_repository.dart';
import '../dokumente/dokumente_repository.dart';
import '../kunden/kunden_repository.dart';
import 'auftraege_repository.dart';
import 'privatgutachten_vertrag_pdf.dart';
import 'package:drift/drift.dart' as drift;

class PrivatgutachtenSchnellanlageScreen extends ConsumerStatefulWidget {
  const PrivatgutachtenSchnellanlageScreen({super.key});

  @override
  ConsumerState<PrivatgutachtenSchnellanlageScreen> createState() =>
      _PrivatgutachtenSchnellanlageScreenState();
}

class _PrivatgutachtenSchnellanlageScreenState
    extends ConsumerState<PrivatgutachtenSchnellanlageScreen> {
  KundenData? _selectedKunde;
  final _gegenstandController = TextEditingController();
  final _stundensatzController = TextEditingController(text: '120,00');
  final _vorschussController = TextEditingController(text: '0,00');

  bool _dsgvoAkzeptiert = false;
  bool _widerrufsverzicht = false;

  final _clientSignatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  
  final _svSignatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  @override
  void dispose() {
    _gegenstandController.dispose();
    _stundensatzController.dispose();
    _vorschussController.dispose();
    _clientSignatureController.dispose();
    _svSignatureController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (_selectedKunde == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen Kunden auswählen.')),
      );
      return;
    }
    if (_gegenstandController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte den Vertragsgegenstand angeben.')),
      );
      return;
    }
    if (_clientSignatureController.isEmpty || _svSignatureController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte beide Unterschriften leisten.')),
      );
      return;
    }
    if (!_dsgvoAkzeptiert) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Datenschutz muss akzeptiert werden.')),
      );
      return;
    }

    try {
      final kKunde = _selectedKunde!;
      final stundensatz = double.tryParse(_stundensatzController.text.replaceAll(',', '.')) ?? 0;
      final vorschuss = double.tryParse(_vorschussController.text.replaceAll(',', '.')) ?? 0;
      
      final svSig = await _svSignatureController.toPngBytes();
      final clientSig = await _clientSignatureController.toPngBytes();

      if (!mounted) return;
      final db = ref.read(appDatabaseProvider);
      final repo = ref.read(auftraegeRepositoryProvider);
      
      // Aktenzeichen generieren
      final seq = await repo.nextAktenzeichenSeq();
      final aktenzeichen = '${DateTime.now().year}-${seq.toString().padLeft(4, '0')}';

      // 1. Auftrag in DB anlegen
      final auftragId = await repo.upsert(
        AuftraegeCompanion.insert(
          aktenzeichen: drift.Value(aktenzeichen),
          art: const drift.Value('privat'),
          status: const drift.Value('in_arbeit'),
          kundeId: drift.Value(kKunde.id),
          bezeichnung: drift.Value('Privatgutachten'),
          betreff: drift.Value(_gegenstandController.text.trim()),
          eingangAm: drift.Value(DateTime.now()),
          auftragAm: drift.Value(DateTime.now()),
          notiz: drift.Value('Via Schnellanlage erstellt.'),
          kostenvorschuss: drift.Value(vorschuss),
        )
      );

      if (!mounted) return;
      // 2. PDF generieren
      final absender = await absenderFromSettings(ref);
      if (absender == null) throw Exception('Kein Absender konfiguriert.');

      final pdfData = VertragPdfData(
        kunde: kKunde,
        absender: absender,
        aktenzeichen: aktenzeichen,
        gegenstand: _gegenstandController.text.trim(),
        stundensatz: stundensatz,
        vorschuss: vorschuss,
        dsgvoAkzeptiert: _dsgvoAkzeptiert,
        widerrufsverzicht: _widerrufsverzicht,
        unterschriftKunde: clientSig!,
        unterschriftSv: svSig!,
      );

      final pdfBytes = await buildPrivatgutachtenVertragPdf(pdfData);

      if (!mounted) return;
      // 3. PDF in Storage laden
      final storage = ref.read(storageServiceProvider);
      final safeName = 'Vertrag_$aktenzeichen'.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_') + '.pdf';
      final path = 'auftraege/$auftragId/$safeName';
      final url = await storage.uploadBytes(path, bytes: pdfBytes, contentType: 'application/pdf');

      if (!mounted) return;
      // 4. Dokument anlegen
      if (url != null) {
        await ref.read(dokumenteRepositoryProvider).upsert(
          DokumenteCompanion.insert(
            titel: drift.Value(safeName),
            mimeType: const drift.Value('application/pdf'),
            dateigroesse: drift.Value(pdfBytes.length),
            storageUrl: drift.Value(url),
            storagePfad: drift.Value(path),
            auftragId: drift.Value(auftragId),
            kategorie: const drift.Value('Vertrag / Auftrag'),
            datum: drift.Value(DateTime.now()),
          )
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Akte und Vertrag wurden erfolgreich angelegt!')),
      );
      context.go('/akte/$auftragId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Anlegen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kundenAsync = ref.watch(kundenListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schnellanlage: Privatgutachten'),
        actions: [
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.check),
            label: const Text('Akte & Vertrag anlegen'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader('1. Vertragsparteien', Icons.people_outline),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  side: const BorderSide(color: AwTokens.line),
                  borderRadius: BorderRadius.circular(AwTokens.radiusLg)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: kundenAsync.when(
                  data: (kunden) {
                    return DropdownButtonFormField<KundenData>(
                      decoration: const InputDecoration(labelText: 'Auftraggeber (Kunde)'),
                      value: _selectedKunde,
                      items: kunden.map((k) => DropdownMenuItem(
                            value: k,
                            child: Text(kundeAnzeigename(k)),
                          )).toList(),
                      onChanged: (v) => setState(() => _selectedKunde = v),
                    );
                  },
                  loading: () => const CircularProgressIndicator(),
                  error: (e, _) => Text('Fehler: $e'),
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            _buildSectionHeader('2. Vertragsgegenstand', Icons.assignment_outlined),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  side: const BorderSide(color: AwTokens.line),
                  borderRadius: BorderRadius.circular(AwTokens.radiusLg)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextFormField(
                  controller: _gegenstandController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Genaue Formulierung der zu begutachtenden Punkte',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            _buildSectionHeader('3. Vergütung', Icons.euro_outlined),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  side: const BorderSide(color: AwTokens.line),
                  borderRadius: BorderRadius.circular(AwTokens.radiusLg)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stundensatzController,
                        decoration: const InputDecoration(labelText: 'Stundensatz (€/h)', suffixText: '€'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _vorschussController,
                        decoration: const InputDecoration(labelText: 'Kostenvorschuss (€)', suffixText: '€'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            _buildSectionHeader('4. Rechtliches', Icons.gavel_outlined),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  side: const BorderSide(color: AwTokens.line),
                  borderRadius: BorderRadius.circular(AwTokens.radiusLg)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    CheckboxListTile(
                      title: const Text('Datenschutz (DSGVO) Informationen übergeben'),
                      value: _dsgvoAkzeptiert,
                      onChanged: (v) => setState(() => _dsgvoAkzeptiert = v ?? false),
                    ),
                    CheckboxListTile(
                      title: const Text('Zustimmung zum vorzeitigen Tätigkeitsbeginn (Erlöschen Widerrufsrecht)'),
                      subtitle: const Text('Kunde verzichtet bei sofortigem Tätigkeitsbeginn auf das 14-tägige Widerrufsrecht.'),
                      value: _widerrufsverzicht,
                      onChanged: (v) => setState(() => _widerrufsverzicht = v ?? false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            _buildSectionHeader('5. Unterschriften', Icons.draw_outlined),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Auftraggeber', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(border: Border.all(color: AwTokens.line)),
                        child: Signature(
                          controller: _clientSignatureController,
                          height: 150,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _clientSignatureController.clear(),
                        icon: const Icon(Icons.clear, size: 16),
                        label: const Text('Löschen'),
                      )
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sachverständiger', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(border: Border.all(color: AwTokens.line)),
                        child: Signature(
                          controller: _svSignatureController,
                          height: 150,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _svSignatureController.clear(),
                        icon: const Icon(Icons.clear, size: 16),
                        label: const Text('Löschen'),
                      )
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AwTokens.ink,
            ),
          ),
        ],
      ),
    );
  }
}
