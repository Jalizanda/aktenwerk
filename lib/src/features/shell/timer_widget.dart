import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/aw_tokens.dart';
import '../../data/database/app_database.dart';
import '../akten/auftraege/auftraege_repository.dart';
import '../kalkulation/stunden/stunden_repository.dart';

/// Globaler Timer-State — persistiert den gestarteten Zeitpunkt, Auftrags-ID
/// und Pausen-Summe während der Session.
class TimerState {
  final DateTime? startedAt;
  final Duration elapsed;
  final int? auftragId;
  final bool paused;

  const TimerState({
    this.startedAt,
    this.elapsed = Duration.zero,
    this.auftragId,
    this.paused = false,
  });

  bool get running => startedAt != null && !paused;

  TimerState copyWith({
    DateTime? startedAt,
    Duration? elapsed,
    int? auftragId,
    bool? paused,
    bool clearStart = false,
    bool clearAuftrag = false,
  }) =>
      TimerState(
        startedAt: clearStart ? null : (startedAt ?? this.startedAt),
        elapsed: elapsed ?? this.elapsed,
        auftragId: clearAuftrag ? null : (auftragId ?? this.auftragId),
        paused: paused ?? this.paused,
      );

  Duration get currentElapsed {
    if (startedAt == null) return elapsed;
    if (paused) return elapsed;
    return elapsed + DateTime.now().difference(startedAt!);
  }
}

class TimerNotifier extends Notifier<TimerState> {
  @override
  TimerState build() => const TimerState();

  void start({int? auftragId}) {
    state = state.copyWith(
      startedAt: DateTime.now(),
      paused: false,
      auftragId: auftragId ?? state.auftragId,
    );
  }

  void pause() {
    if (state.startedAt == null || state.paused) return;
    final added = DateTime.now().difference(state.startedAt!);
    state = state.copyWith(
      elapsed: state.elapsed + added,
      startedAt: null,
      paused: true,
    );
  }

  void resume() {
    state = state.copyWith(startedAt: DateTime.now(), paused: false);
  }

  void reset() {
    state = const TimerState();
  }

  void setAuftrag(int? id) {
    state = state.copyWith(
      auftragId: id,
      clearAuftrag: id == null,
    );
  }

  /// Stoppt den Timer, speichert den Eintrag in `stunden` und resettet.
  Future<void> stopAndSave() async {
    if (state.startedAt == null && state.elapsed == Duration.zero) return;
    final total = state.currentElapsed;
    final minuten = total.inSeconds ~/ 60;
    if (minuten <= 0 || state.auftragId == null) {
      reset();
      return;
    }
    await ref.read(stundenRepositoryProvider).upsert(StundenCompanion.insert(
          auftragId: Value(state.auftragId!),
          datum: Value(DateTime.now()),
          minuten: Value(minuten),
          taetigkeit: const Value('Erfasst per Timer'),
        ));
    reset();
  }
}

final timerProvider =
    NotifierProvider<TimerNotifier, TimerState>(TimerNotifier.new);

/// Kompaktes Timer-Widget für die Top-Bar.
class TimerWidget extends ConsumerStatefulWidget {
  const TimerWidget({super.key});
  @override
  ConsumerState<TimerWidget> createState() => _TimerWidgetState();
}

class _TimerWidgetState extends ConsumerState<TimerWidget> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(timerProvider);
    final elapsed = state.currentElapsed;
    final running = state.running;

    return Material(
      color: running ? AwTokens.greenSoft : AppTheme.slate100,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openPicker(context),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                running
                    ? Icons.play_arrow
                    : (state.paused
                        ? Icons.pause
                        : Icons.timer_outlined),
                size: 16,
                color: running
                    ? AwTokens.green
                    : AppTheme.slate500,
              ),
              const SizedBox(width: 6),
              Text(
                _fmt(elapsed),
                style: TextStyle(
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w600,
                  color: running
                      ? AwTokens.green
                      : AppTheme.slate700,
                ),
              ),
              const SizedBox(width: 6),
              if (state.startedAt != null || state.elapsed > Duration.zero)
                IconButton(
                  tooltip: running ? 'Pause' : 'Weiter',
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(running ? Icons.pause : Icons.play_arrow),
                  onPressed: () {
                    if (running) {
                      ref.read(timerProvider.notifier).pause();
                    } else {
                      ref.read(timerProvider.notifier).resume();
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (_) => const _TimerDialog(),
    );
  }
}

class _TimerDialog extends ConsumerStatefulWidget {
  const _TimerDialog();
  @override
  ConsumerState<_TimerDialog> createState() => _TimerDialogState();
}

class _TimerDialogState extends ConsumerState<_TimerDialog> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(timerProvider);
    final auftraegeAsync = ref.watch(auftraegeListProvider);
    final elapsed = state.currentElapsed;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stunden-Timer',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  _fmt(elapsed),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: state.running
                        ? AwTokens.green
                        : AppTheme.slate700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Auftrag',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.slate500,
                      letterSpacing: 1)),
              const SizedBox(height: 4),
              auftraegeAsync.when(
                loading: () =>
                    const LinearProgressIndicator(minHeight: 2),
                error: (e, _) => Text('Fehler: $e'),
                data: (auftraege) => DropdownButton<int?>(
                  value: state.auftragId,
                  isExpanded: true,
                  hint: const Text('Auftrag wählen'),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('— (keiner)')),
                    for (final a in auftraege)
                      DropdownMenuItem(
                        value: a.auftrag.id,
                        child: Text(
                          '${a.auftrag.aktenzeichen ?? "?"} · '
                          '${a.auftrag.betreff ?? a.auftrag.bezeichnung ?? ""}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) =>
                      ref.read(timerProvider.notifier).setAuftrag(id),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!state.running && state.startedAt == null)
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Starten'),
                      onPressed: state.auftragId == null
                          ? null
                          : () => ref.read(timerProvider.notifier).start(),
                    )
                  else if (state.running)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                      onPressed: () =>
                          ref.read(timerProvider.notifier).pause(),
                    )
                  else
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Weiter'),
                      onPressed: () =>
                          ref.read(timerProvider.notifier).resume(),
                    ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.restore),
                    label: const Text('Zurücksetzen'),
                    onPressed: () =>
                        ref.read(timerProvider.notifier).reset(),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Stoppen & speichern'),
                    onPressed: elapsed.inMinutes < 1 ||
                            state.auftragId == null
                        ? null
                        : () async {
                            await ref
                                .read(timerProvider.notifier)
                                .stopAndSave();
                            if (context.mounted) {
                              Navigator.of(context, rootNavigator: true)
                                  .pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Stunden-Eintrag gespeichert')));
                            }
                          },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Der Eintrag wird in «Stunden» mit dem eingetragenen Auftrag '
                'abgelegt. Mindestlänge: 1 Minute.',
                style: TextStyle(
                    fontSize: 11, color: AppTheme.slate500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
