import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../shared/widgets/form_widgets.dart';

/// Ein Dialog für das Protokollieren eines Telefonats inkl. Timer für
/// Zeiterfassung und Textfeld für das Transkript/Notiz.
class TelefonNotizDialog extends ConsumerStatefulWidget {
  const TelefonNotizDialog({super.key, required this.auftragId});
  final int auftragId;

  @override
  ConsumerState<TelefonNotizDialog> createState() => _TelefonNotizDialogState();
}

class _TelefonNotizDialogState extends ConsumerState<TelefonNotizDialog> {
  final _notiz = TextEditingController();
  Timer? _timer;
  int _seconds = 0;
  bool _isRunning = false;
  bool _saving = false;

  @override
  void dispose() {
    _timer?.cancel();
    _notiz.dispose();
    super.dispose();
  }

  void _toggleTimer() {
    if (_isRunning) {
      _timer?.cancel();
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _seconds++);
      });
    }
    setState(() => _isRunning = !_isRunning);
  }

  String get _timeString {
    final m = (_seconds / 60).floor().toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _speichern() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final minuten = (_seconds / 60).ceil();
      final finalMinuten = minuten == 0 ? 1 : minuten; // Mindestens 1 Minute
      
      await db.transaction(() async {
        // 1. Stunden erfassen
        await db.into(db.stunden).insert(StundenCompanion.insert(
              auftragId: Value(widget.auftragId),
              datum: Value(DateTime.now()),
              minuten: Value(finalMinuten),
              taetigkeit: const Value('Telefonat'),
              notiz: Value(_notiz.text.trim()),
            ));

        // 2. Notiz als RechercheNotiz speichern
        if (_notiz.text.trim().isNotEmpty) {
          await db.into(db.rechercheNotizen).insert(RechercheNotizenCompanion.insert(
                auftragId: Value(widget.auftragId),
                titel: 'Telefon-Notiz vom ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}',
                inhalt: _notiz.text.trim(),
                quelle: const Value('Telefonat'),
              ));
        }
      });
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Telefonnotiz & Zeiterfassung gespeichert')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Fehler beim Speichern: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.phone_in_talk_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Schnellnotiz Telefonat',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_timeString,
                            style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w300,
                                fontFamily: 'monospace')),
                        const SizedBox(width: 20),
                        FloatingActionButton.small(
                          onPressed: _toggleTimer,
                          elevation: 0,
                          backgroundColor: _isRunning
                              ? Theme.of(context).colorScheme.errorContainer
                              : Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(
                            _isRunning ? Icons.pause : Icons.play_arrow,
                            color: _isRunning
                                ? Theme.of(context).colorScheme.onErrorContainer
                                : Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: LabeledField(
                        'Transkript / Notiz',
                        TextFormField(
                          controller: _notiz,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            hintText: 'Hier kannst du während des Gesprächs tippen...',
                            alignLabelWithHint: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Speichern & Zeiterfassung buchen'),
                    onPressed: _saving ? null : _speichern,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
