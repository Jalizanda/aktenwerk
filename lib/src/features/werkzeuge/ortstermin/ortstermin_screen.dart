import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/akten/auftraege/auftraege_repository.dart';
import '../../../features/kalkulation/stunden/stunden_repository.dart';
import '../../../features/werkzeuge/fotos/fotos_repository.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';

/// Fokussierter Ortstermin-Modus: Großflächige Buttons für Fotos,
/// Notizen und Stunden-Timer beim Einsatz vor Ort.
class OrtsterminScreen extends ConsumerStatefulWidget {
  const OrtsterminScreen({super.key});
  @override
  ConsumerState<OrtsterminScreen> createState() =>
      _OrtsterminScreenState();
}

class _OrtsterminScreenState extends ConsumerState<OrtsterminScreen> {
  int? _auftragId;
  final _notizController = TextEditingController();
  final List<_Notiz> _notizen = [];
  int _fotoCount = 0;

  @override
  void dispose() {
    _notizController.dispose();
    super.dispose();
  }

  Future<void> _fotoHinzufuegen() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final repo = ref.read(fotosRepositoryProvider);
    for (final f in res.files) {
      if (f.bytes == null) continue;
      await repo.upsert(FotosCompanion.insert(
        auftragId: Value(_auftragId),
        titel: Value(f.name),
        daten: Value(f.bytes),
        aufnahmeAm: Value(DateTime.now()),
      ));
    }
    setState(() => _fotoCount += res.files.length);
  }

  void _notizSpeichern() {
    final text = _notizController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _notizen.insert(0, _Notiz(DateTime.now(), text));
      _notizController.clear();
    });
  }

  void _timerStart() {
    if (_auftragId == null) return;
    ref.read(stundenTimerProvider.notifier).update((s) => s.copyWith(
          startedAt: DateTime.now(),
          auftragId: _auftragId,
          taetigkeit: 'Ortstermin',
        ));
  }

  Future<void> _timerStop() async {
    final state = ref.read(stundenTimerProvider);
    if (!state.running || state.auftragId == null) return;
    final elapsed = DateTime.now().difference(state.startedAt!).inMinutes;
    await ref.read(stundenRepositoryProvider).upsert(StundenCompanion.insert(
          auftragId: Value(state.auftragId),
          datum: Value(DateTime.now()),
          beginn: Value(state.startedAt),
          ende: Value(DateTime.now()),
          minuten: Value(elapsed == 0 ? 1 : elapsed),
          taetigkeit: const Value('Ortstermin'),
        ));
    ref.read(stundenTimerProvider.notifier).update((s) => s.copyWith(reset: true));
  }

  Future<void> _alleNotizenInAuftragNotiz() async {
    if (_auftragId == null || _notizen.isEmpty) return;
    final repo = ref.read(auftraegeRepositoryProvider);
    final auftrag = await repo.byId(_auftragId!);
    if (auftrag == null) return;
    final oldNotiz = auftrag.notiz ?? '';
    final neueNotiz = _notizen
        .map((n) => '[${DateFormat('dd.MM.yyyy HH:mm').format(n.zeit)}] ${n.text}')
        .join('\n');
    await repo.upsert(AuftraegeCompanion(
      id: Value(auftrag.id),
      notiz: Value('$oldNotiz\n\n$neueNotiz'.trim()),
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('${_notizen.length} Notizen in Auftrag übernommen')),
      );
      setState(() => _notizen.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(stundenTimerProvider);
    final elapsed = timer.startedAt == null
        ? Duration.zero
        : DateTime.now().difference(timer.startedAt!);
    final fmt = DateFormat('HH:mm:ss');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.place_outlined,
          title: 'Ortstermin-Modus',
          subtitle: 'Vor Ort: Fotos, Notizen, Zeiterfassung',
          filters: [
            SizedBox(
              width: 360,
              child: AuftragPickerField(
                auftragId: _auftragId,
                onChanged: (id) => setState(() => _auftragId = id),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ActionCard(
                        icon: Icons.photo_camera_outlined,
                        title: 'Foto hinzufügen',
                        subtitle: 'Aus Dateien oder Kamera ($_fotoCount heute)',
                        onTap: _auftragId == null ? null : _fotoHinzufuegen,
                      ),
                      const SizedBox(height: 12),
                      _ActionCard(
                        icon: timer.running
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline,
                        title: timer.running
                            ? 'Timer stoppen'
                            : 'Timer starten',
                        subtitle: timer.running
                            ? 'Läuft ${_formatDuration(elapsed)}'
                            : 'Zeit für Ortstermin erfassen',
                        onTap: _auftragId == null
                            ? null
                            : (timer.running ? _timerStop : _timerStart),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Schnell-Notiz',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _notizController,
                                minLines: 2,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText:
                                      'Was soll festgehalten werden?',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.icon(
                                  onPressed: _notizSpeichern,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Notiz hinzufügen'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 3,
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Text('Gesammelte Notizen',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium),
                              const Spacer(),
                              if (_notizen.isNotEmpty)
                                TextButton.icon(
                                  onPressed: _alleNotizenInAuftragNotiz,
                                  icon: const Icon(Icons.save_outlined),
                                  label: const Text('In Auftrag übernehmen'),
                                ),
                            ],
                          ),
                          const Divider(),
                          Expanded(
                            child: _notizen.isEmpty
                                ? const EmptyListState(
                                    icon: Icons.notes,
                                    title: 'Noch keine Notizen')
                                : ListView.separated(
                                    itemCount: _notizen.length,
                                    separatorBuilder: (_, _) =>
                                        const Divider(height: 1),
                                    itemBuilder: (_, i) {
                                      final n = _notizen[i];
                                      return ListTile(
                                        dense: true,
                                        title: Text(n.text),
                                        subtitle: Text(fmt.format(n.zeit)),
                                        trailing: IconButton(
                                          icon: const Icon(
                                              Icons.delete_outline),
                                          onPressed: () => setState(
                                              () => _notizen.removeAt(i)),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) =>
      '${d.inHours.toString().padLeft(2, '0')}:'
      '${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
      '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

class _Notiz {
  final DateTime zeit;
  final String text;
  const _Notiz(this.zeit, this.text);
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
