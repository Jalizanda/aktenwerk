import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../shared/widgets/badges.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/module_scaffold.dart';
import '../wiedervorlagen/wiedervorlagen_repository.dart';
import 'termine_repository.dart';

final _selectedDayProvider =
    StateProvider<DateTime>((ref) => _dateOnly(DateTime.now()));
final _visibleMonthProvider = StateProvider<DateTime>(
    (ref) => DateTime(DateTime.now().year, DateTime.now().month));
final _termineQueryProvider = StateProvider<String>((ref) => '');

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// ISO-KW nach DIN 1355.
int _weekOfYear(DateTime d) {
  final thursday = d.add(Duration(days: 4 - d.weekday));
  final firstThursday = DateTime(thursday.year, 1, 4)
      .add(Duration(days: 4 - DateTime(thursday.year, 1, 4).weekday));
  return 1 + (thursday.difference(firstThursday).inDays ~/ 7);
}

/// Farbpaare pro Termintyp.
typedef _TypColor = ({Color bg, Color fg, Color dot});

_TypColor _farbeFuer(String typ) => switch (typ) {
      'Ortstermin' => (
          bg: BadgeColors.blueBg,
          fg: BadgeColors.blueFg,
          dot: const Color(0xFF2563EB),
        ),
      'Erläuterung' => (
          bg: BadgeColors.indigoBg,
          fg: BadgeColors.indigoFg,
          dot: const Color(0xFF4F46E5),
        ),
      'Wiedervorlage' => (
          bg: BadgeColors.amberBg,
          fg: BadgeColors.amberFg,
          dot: const Color(0xFFF59E0B),
        ),
      'Frist' => (
          bg: BadgeColors.redBg,
          fg: BadgeColors.redFg,
          dot: const Color(0xFFDC2626),
        ),
      _ => (
          bg: BadgeColors.slateBg,
          fg: BadgeColors.slateFg,
          dot: const Color(0xFF64748B),
        ),
    };

class TermineScreen extends ConsumerWidget {
  const TermineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(termineListProvider);
    final selectedDay = ref.watch(_selectedDayProvider);
    final query = ref.watch(_termineQueryProvider).trim().toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModuleHeader(
          icon: Icons.calendar_month_outlined,
          title: 'Kalender',
          subtitle:
              'Ortstermine, Fristen, Erläuterungstermine und Wiedervorlagen',
          searchHint: 'Suche Titel, Akte, Ort …',
          onSearchChanged: (v) =>
              ref.read(_termineQueryProvider.notifier).state = v,
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.ios_share),
              label: const Text('iCal-Export'),
              onPressed: () async {
                final items = async.valueOrNull ?? const <TerminEintrag>[];
                await _exportIcs(context, items);
              },
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neuer Termin'),
              onPressed: () => _showNeuerTerminDialog(context, ref,
                  initial: selectedDay),
            ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (all) {
              final filtered = query.isEmpty
                  ? all
                  : all.where((t) {
                      final s = [
                        t.titel,
                        t.typ,
                        t.ort ?? '',
                        t.aktenzeichen ?? '',
                      ].join(' ').toLowerCase();
                      return s.contains(query);
                    }).toList();
              return LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth > 1100;
                  final calendar = _CalendarPanel(termine: filtered);
                  final weeks = _WochenKacheln(termine: filtered);
                  final day =
                      _TagesListe(termine: filtered, selectedDay: selectedDay);
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 400, child: calendar),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                weeks,
                                const SizedBox(height: 20),
                                day,
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(height: 520, child: calendar),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              weeks,
                              const SizedBox(height: 20),
                              day,
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------- Kalender-Panel ----------------

class _CalendarPanel extends ConsumerWidget {
  const _CalendarPanel({required this.termine});
  final List<TerminEintrag> termine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleMonth = ref.watch(_visibleMonthProvider);
    final selectedDay = ref.watch(_selectedDayProvider);
    final monthFmt = DateFormat('MMMM yyyy', 'de');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Vorheriger Monat',
                onPressed: () => ref
                    .read(_visibleMonthProvider.notifier)
                    .state = DateTime(
                    visibleMonth.year, visibleMonth.month - 1),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    monthFmt.format(visibleMonth),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.today_outlined),
                tooltip: 'Heute',
                onPressed: () {
                  final t = _dateOnly(DateTime.now());
                  ref.read(_visibleMonthProvider.notifier).state =
                      DateTime(t.year, t.month);
                  ref.read(_selectedDayProvider.notifier).state = t;
                },
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Nächster Monat',
                onPressed: () => ref
                    .read(_visibleMonthProvider.notifier)
                    .state = DateTime(
                    visibleMonth.year, visibleMonth.month + 1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _MonthGrid(
            visibleMonth: visibleMonth,
            selectedDay: selectedDay,
            termine: termine,
            onSelect: (d) =>
                ref.read(_selectedDayProvider.notifier).state = d,
          ),
          const SizedBox(height: 10),
          const _Legende(),
        ],
      ),
    );
  }
}

class _Legende extends StatelessWidget {
  const _Legende();
  @override
  Widget build(BuildContext context) {
    Widget dot(String typ) {
      final c = _farbeFuer(typ);
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: c.dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(typ, style: const TextStyle(fontSize: 10.5)),
          ],
        ),
      );
    }

    return Wrap(
      children: [
        dot('Ortstermin'),
        dot('Erläuterung'),
        dot('Wiedervorlage'),
        dot('Frist'),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.visibleMonth,
    required this.selectedDay,
    required this.termine,
    required this.onSelect,
  });
  final DateTime visibleMonth;
  final DateTime selectedDay;
  final List<TerminEintrag> termine;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final startOffset = first.weekday - 1;
    final daysInMonth =
        DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final today = _dateOnly(DateTime.now());

    // Typen pro Tag einsammeln
    final typenPerTag = <DateTime, Set<String>>{};
    for (final t in termine) {
      typenPerTag.putIfAbsent(t.tag, () => {}).add(t.typ);
    }

    final rows = <Widget>[];
    rows.add(Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(
            width: 28,
            child: Text('KW',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
          ),
          for (final wd in const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'])
            Expanded(
              child: Text(wd,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 10.5, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    ));

    var cursor = first.subtract(Duration(days: startOffset));
    final totalCells = ((startOffset + daysInMonth) / 7).ceil() * 7;
    for (var w = 0; w < totalCells / 7; w++) {
      final cells = <Widget>[];
      cells.add(SizedBox(
        width: 28,
        child: Text('${_weekOfYear(cursor)}',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ));
      for (var d = 0; d < 7; d++) {
        final day = cursor;
        final inMonth = day.month == visibleMonth.month;
        final isToday = day == today;
        final isSelected = day == selectedDay;
        final typen = typenPerTag[day] ?? <String>{};
        cells.add(Expanded(
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelect(day),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: isToday
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.5)
                      : null,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isToday ? FontWeight.w700 : FontWeight.normal,
                        color: inMonth
                            ? (isSelected
                                ? Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer
                                : null)
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _TypPunkte(typen: typen),
                  ],
                ),
              ),
            ),
          ),
        ));
        cursor = cursor.add(const Duration(days: 1));
      }
      rows.add(Row(children: cells));
    }

    return Column(children: rows);
  }
}

/// Zeigt bis zu 4 Farb-Punkte — je einen pro Termintyp am Tag.
class _TypPunkte extends StatelessWidget {
  const _TypPunkte({required this.typen});
  final Set<String> typen;
  @override
  Widget build(BuildContext context) {
    if (typen.isEmpty) return const SizedBox(height: 6);
    final reihenfolge = ['Frist', 'Ortstermin', 'Erläuterung', 'Wiedervorlage'];
    final sortiert = reihenfolge.where(typen.contains).toList();
    return SizedBox(
      height: 6,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in sortiert.take(4))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                    color: _farbeFuer(t).dot, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------- Wochen-Kacheln ----------------

class _WochenKacheln extends StatelessWidget {
  const _WochenKacheln({required this.termine});
  final List<TerminEintrag> termine;

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final nextStart = weekStart.add(const Duration(days: 7));
    final nextEnd = nextStart.add(const Duration(days: 6));

    final current = termine
        .where(
            (t) => !t.tag.isBefore(weekStart) && !t.tag.isAfter(weekEnd))
        .toList();
    final next = termine
        .where(
            (t) => !t.tag.isBefore(nextStart) && !t.tag.isAfter(nextEnd))
        .toList();

    return LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth > 800;
      final a = _WeekSection(
          label: 'Diese Woche',
          start: weekStart,
          end: weekEnd,
          termine: current);
      final b = _WeekSection(
          label: 'Folgewoche',
          start: nextStart,
          end: nextEnd,
          termine: next);
      if (side) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: 12),
            Expanded(child: b),
          ],
        );
      }
      return Column(children: [a, const SizedBox(height: 12), b]);
    });
  }
}

class _WeekSection extends StatelessWidget {
  const _WeekSection({
    required this.label,
    required this.start,
    required this.end,
    required this.termine,
  });
  final String label;
  final DateTime start;
  final DateTime end;
  final List<TerminEintrag> termine;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd.MM.', 'de');
    final kw = _weekOfYear(start);
    // Je Wochentag gruppieren (Mo…So, auch wenn leer).
    final tage = <DateTime>[];
    for (var i = 0; i < 7; i++) {
      tage.add(start.add(Duration(days: i)));
    }
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                PillBadge(
                  text: 'KW $kw',
                  background: BadgeColors.indigoBg,
                  foreground: BadgeColors.indigoFg,
                ),
                const Spacer(),
                Text('${fmt.format(start)} – ${fmt.format(end)}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 6),
            if (termine.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('Keine Einträge.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
              )
            else
              for (final tag in tage) _TagBlock(tag: tag, termine: termine),
          ],
        ),
      ),
    );
  }
}

class _TagBlock extends StatelessWidget {
  const _TagBlock({required this.tag, required this.termine});
  final DateTime tag;
  final List<TerminEintrag> termine;

  @override
  Widget build(BuildContext context) {
    final dayTermine = termine
        .where((t) => t.tag == tag)
        .toList()
      ..sort((a, b) => a.zeitpunkt.compareTo(b.zeitpunkt));
    if (dayTermine.isEmpty) return const SizedBox.shrink();
    final wdFmt = DateFormat('EEE, dd.MM.', 'de');
    final isToday = tag == _dateOnly(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: isToday
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                wdFmt.format(tag),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isToday
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final t in dayTermine) _TerminCard(eintrag: t),
        ],
      ),
    );
  }
}

// ---------------- Tagesliste (unten / in schmaler Ansicht) ----------------

class _TagesListe extends StatelessWidget {
  const _TagesListe({required this.termine, required this.selectedDay});
  final List<TerminEintrag> termine;
  final DateTime selectedDay;

  @override
  Widget build(BuildContext context) {
    final eintraege = termine
        .where((t) => t.tag == selectedDay)
        .toList()
      ..sort((a, b) => a.zeitpunkt.compareTo(b.zeitpunkt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Termine am ${DateFormat('EEEE, dd.MM.yyyy', 'de').format(selectedDay)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Divider(),
        if (eintraege.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Keine Termine an diesem Tag.'),
          )
        else
          for (final t in eintraege) _TerminCard(eintrag: t, kompakt: false),
      ],
    );
  }
}

// ---------------- Einzel-Termin-Karte ----------------

class _TerminCard extends StatelessWidget {
  const _TerminCard({required this.eintrag, this.kompakt = true});
  final TerminEintrag eintrag;
  final bool kompakt;

  @override
  Widget build(BuildContext context) {
    final zeit = DateFormat('HH:mm', 'de').format(eintrag.zeitpunkt);
    final ende = eintrag.ende == null
        ? null
        : DateFormat('HH:mm', 'de').format(eintrag.ende!);
    final c = _farbeFuer(eintrag.typ);
    final hasRoute = ((eintrag.ort ?? '').isNotEmpty) && eintrag.istOrtstermin;
    final hasTel = (eintrag.telefon ?? '').isNotEmpty;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: eintrag.auftragId == null
            ? null
            : () => context.go('/akte/${eintrag.auftragId}'),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: c.dot,
                  borderRadius: BorderRadius.circular(2),
                ),
                constraints: const BoxConstraints(minHeight: 44),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(zeit,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  if (ende != null)
                    Text('– $ende',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ],
                        )),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PillBadge(
                            text: eintrag.typ,
                            background: c.bg,
                            foreground: c.fg),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            eintrag.titel,
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if ((eintrag.ort ?? '').isNotEmpty ||
                        (eintrag.aktenzeichen ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          [eintrag.aktenzeichen, eintrag.ort]
                              .whereType<String>()
                              .where((s) => s.isNotEmpty)
                              .join('  ·  '),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              // Aktions-Icons rechts: Google Maps, Telefon, Google Calendar
              if (hasRoute)
                IconButton(
                  tooltip: 'In Google Maps öffnen',
                  icon: const Icon(Icons.place_outlined, size: 18),
                  onPressed: () => launchUrl(
                    Uri.parse(
                        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(eintrag.ort!)}'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              if (hasTel)
                IconButton(
                  tooltip: 'Anrufen',
                  icon: const Icon(Icons.phone_outlined, size: 18),
                  onPressed: () =>
                      launchUrl(Uri.parse('tel:${eintrag.telefon}')),
                ),
              IconButton(
                tooltip: 'Zu Google Kalender hinzufügen',
                icon: const Icon(Icons.event_available_outlined, size: 18),
                onPressed: () => _googleCalendarLink(eintrag),
              ),
              if (eintrag.auftragId != null)
                IconButton(
                  tooltip: 'Zur Akte',
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  onPressed: () =>
                      context.go('/akte/${eintrag.auftragId}'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Öffnet Google-Kalender-Ereignis-Formular mit vorbefüllten Werten.
Future<void> _googleCalendarLink(TerminEintrag t) async {
  String fmtDt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}T'
      '${d.hour.toString().padLeft(2, '0')}'
      '${d.minute.toString().padLeft(2, '0')}00';
  final start = t.zeitpunkt;
  final end = t.ende ?? start.add(const Duration(hours: 1));
  final uri = Uri.parse(
    'https://calendar.google.com/calendar/render?action=TEMPLATE'
    '&text=${Uri.encodeQueryComponent("[${t.typ}] ${t.titel}")}'
    '&dates=${fmtDt(start)}/${fmtDt(end)}'
    '&details=${Uri.encodeQueryComponent(
        [if ((t.aktenzeichen ?? "").isNotEmpty) "Akte: ${t.aktenzeichen}", "Typ: ${t.typ}"].join("\n"))}'
    '&location=${Uri.encodeQueryComponent(t.ort ?? "")}',
  );
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

// ---------------- Neuer-Termin-Dialog ----------------

Future<void> _showNeuerTerminDialog(
    BuildContext context, WidgetRef ref,
    {DateTime? initial}) async {
  final titel = TextEditingController();
  final anlass = TextEditingController();
  final beschreibung = TextEditingController();
  var datum = initial ?? _dateOnly(DateTime.now());
  var beginn = const TimeOfDay(hour: 9, minute: 0);
  var ende = const TimeOfDay(hour: 10, minute: 0);
  int? auftragId;
  var prio = 'normal';

  final ok = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setState) => StandardFormDialog(
        title: 'Neuer Termin / Wiedervorlage',
        icon: Icons.event_outlined,
        maxWidth: 620,
        maxHeight: 700,
        onCancel: () => Navigator.pop(ctx, false),
        onSave: () => Navigator.pop(ctx, true),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabeledField('Titel *', TextFormField(controller: titel)),
              const SizedBox(height: 12),
              LabeledField(
                'Datum',
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: datum,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => datum = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      suffixIcon: Icon(Icons.calendar_month_outlined),
                    ),
                    child: Text(
                        DateFormat('dd.MM.yyyy', 'de').format(datum)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row2(
                left: LabeledField(
                  'Von',
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                          context: ctx, initialTime: beginn);
                      if (picked != null) setState(() => beginn = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        suffixIcon: Icon(Icons.schedule_outlined),
                      ),
                      child: Text(
                          '${beginn.hour.toString().padLeft(2, '0')}:${beginn.minute.toString().padLeft(2, '0')}'),
                    ),
                  ),
                ),
                right: LabeledField(
                  'Bis',
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                          context: ctx, initialTime: ende);
                      if (picked != null) setState(() => ende = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        suffixIcon: Icon(Icons.schedule_outlined),
                      ),
                      child: Text(
                          '${ende.hour.toString().padLeft(2, '0')}:${ende.minute.toString().padLeft(2, '0')}'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AuftragPickerField(
                auftragId: auftragId,
                onChanged: (id) => setState(() => auftragId = id),
              ),
              const SizedBox(height: 12),
              LabeledField('Anlass / Ort',
                  TextFormField(controller: anlass)),
              const SizedBox(height: 12),
              LabeledField(
                'Beschreibung',
                TextFormField(
                    controller: beschreibung, minLines: 2, maxLines: 4),
              ),
              const SizedBox(height: 12),
              LabeledField(
                'Priorität',
                DropdownButtonFormField<String>(
                  initialValue: prio,
                  items: const [
                    DropdownMenuItem(value: 'niedrig', child: Text('niedrig')),
                    DropdownMenuItem(value: 'normal', child: Text('normal')),
                    DropdownMenuItem(value: 'hoch', child: Text('hoch')),
                  ],
                  onChanged: (v) => setState(() => prio = v ?? 'normal'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (ok != true) return;
  if (titel.text.trim().isEmpty) return;
  final dt = DateTime(
      datum.year, datum.month, datum.day, beginn.hour, beginn.minute);
  final dtEnde = DateTime(
      datum.year, datum.month, datum.day, ende.hour, ende.minute);
  await ref.read(wiedervorlagenRepositoryProvider).upsert(
        WiedervorlagenCompanion.insert(
          titel: titel.text.trim(),
          anlass: anlass.text.trim().isEmpty
              ? const Value.absent()
              : Value(anlass.text.trim()),
          beschreibung: beschreibung.text.trim().isEmpty
              ? const Value.absent()
              : Value(beschreibung.text.trim()),
          auftragId: Value(auftragId),
          faelligAm: Value(dt),
          endeAm: Value(dtEnde.isAfter(dt) ? dtEnde : null),
          prioritaet: Value(prio),
        ),
      );
}

// ---------------- iCal-Export ----------------

Future<void> _exportIcs(
    BuildContext context, List<TerminEintrag> items) async {
  if (items.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Termine zum Exportieren.')));
    }
    return;
  }
  final buffer = StringBuffer();
  buffer.writeln('BEGIN:VCALENDAR');
  buffer.writeln('VERSION:2.0');
  buffer.writeln('PRODID:-//Aktenwerk//Termine//DE');
  buffer.writeln('CALSCALE:GREGORIAN');
  buffer.writeln('X-WR-CALNAME:Aktenwerk');

  String fmtDt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}T'
      '${d.hour.toString().padLeft(2, '0')}'
      '${d.minute.toString().padLeft(2, '0')}00';
  String esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('\n', '\\n')
      .replaceAll(',', '\\,')
      .replaceAll(';', '\\;');

  final stamp = fmtDt(DateTime.now().toUtc());
  for (final t in items) {
    final start = t.zeitpunkt;
    final end = t.ende ?? start.add(const Duration(hours: 1));
    final uid =
        'aktenwerk-${t.typ}-${t.quellId ?? start.millisecondsSinceEpoch}@aktenwerk';
    buffer.writeln('BEGIN:VEVENT');
    buffer.writeln('UID:$uid');
    buffer.writeln('DTSTAMP:${stamp}Z');
    buffer.writeln('DTSTART:${fmtDt(start)}');
    buffer.writeln('DTEND:${fmtDt(end)}');
    buffer.writeln('SUMMARY:${esc('[${t.typ}] ${t.titel}')}');
    if ((t.ort ?? '').isNotEmpty) buffer.writeln('LOCATION:${esc(t.ort!)}');
    final desc = [
      if ((t.aktenzeichen ?? '').isNotEmpty) 'Akte: ${t.aktenzeichen}',
      'Typ: ${t.typ}',
    ].join('\\n');
    buffer.writeln('DESCRIPTION:$desc');
    buffer.writeln('END:VEVENT');
  }
  buffer.writeln('END:VCALENDAR');
  final ics = buffer.toString();

  try {
    await Share.shareXFiles(
      [
        XFile.fromData(
          Uint8List.fromList(utf8.encode(ics)),
          name: 'aktenwerk-termine.ics',
          mimeType: 'text/calendar',
        ),
      ],
      subject: 'Aktenwerk Termine',
      text: 'Aktenwerk – ${items.length} Termine',
    );
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: ics));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('iCal-Daten in die Zwischenablage kopiert.')));
    }
  }
}
