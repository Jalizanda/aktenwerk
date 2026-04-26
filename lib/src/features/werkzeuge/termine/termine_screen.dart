import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_provider.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../../../features/akten/auftraege/auftraege_form.dart';
import '../../../features/akten/erlaeuterungen/erlaeuterungen_repository.dart';
import '../../../features/akten/erlaeuterungen/erlaeuterungen_screen.dart';
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

/// Ansichtsmodus des Kalenders: kompakt = bisherige Split-Ansicht
/// (Mini-Kalender + Wochenkacheln), monat = ganzseitige Monatsansicht
/// mit Event-Pillen und rechter Sidebar (Heute-Agenda + Filter).
enum _ViewMode { kompakt, monat }

final _viewModeProvider =
    StateProvider<_ViewMode>((ref) => _ViewMode.monat);

/// Filter-Map pro Terminkategorie: Wenn ein Key auf false steht, wird
/// der Typ in der Monatsansicht ausgeblendet.
final _typFilterProvider = StateProvider<Map<String, bool>>((ref) => {
      'Ortstermin': true,
      'Erläuterung': true,
      'Wiedervorlage': true,
      'Frist': true,
    });

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
            _ViewModeToggle(),
            OutlinedButton.icon(
              icon: const Icon(Icons.today_outlined, size: 16),
              label: const Text('Heute'),
              onPressed: () {
                final t = _dateOnly(DateTime.now());
                ref.read(_visibleMonthProvider.notifier).state =
                    DateTime(t.year, t.month);
                ref.read(_selectedDayProvider.notifier).state = t;
              },
            ),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Termin'),
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
              final mode = ref.watch(_viewModeProvider);
              if (mode == _ViewMode.monat) {
                return _BigMonatView(termine: filtered);
              }
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
        onTap: () => _openTermin(context, eintrag),
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

// ======================================================================
// Big-Month-View (AW §5 Kalender-Pattern: 7×5 Grid mit Event-Pillen)
// ======================================================================

class _ViewModeToggle extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(_viewModeProvider);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AwTokens.line),
        borderRadius: BorderRadius.circular(AwTokens.radiusMd),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segButton(ref, _ViewMode.kompakt, 'Liste', mode),
          _segButton(ref, _ViewMode.monat, 'Monat', mode),
        ],
      ),
    );
  }

  Widget _segButton(
      WidgetRef ref, _ViewMode target, String label, _ViewMode current) {
    final active = current == target;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(_viewModeProvider.notifier).state = target,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AwTokens.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(AwTokens.radiusSm),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: active ? AwTokens.white : AwTokens.mute,
          ),
        ),
      ),
    );
  }
}

class _BigMonatView extends ConsumerWidget {
  const _BigMonatView({required this.termine});
  final List<TerminEintrag> termine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleMonth = ref.watch(_visibleMonthProvider);
    final typFilter = ref.watch(_typFilterProvider);
    final sichtbar = termine
        .where((t) => typFilter[t.typ] ?? true)
        .toList();

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > 1100;
        final grid = _BigMonthGrid(
          visibleMonth: visibleMonth,
          termine: sichtbar,
          onSelect: (d) =>
              ref.read(_selectedDayProvider.notifier).state = d,
          onMonthChange: (m) =>
              ref.read(_visibleMonthProvider.notifier).state = m,
        );
        if (!wide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                grid,
                const SizedBox(height: 20),
                _HeuteAgenda(termine: sichtbar),
                const SizedBox(height: 16),
                _FilterSidebar(),
              ],
            ),
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: grid,
              ),
            ),
            Container(
              width: 320,
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: AwTokens.line)),
                color: AwTokens.white,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HeuteAgenda(termine: sichtbar),
                    const SizedBox(height: 20),
                    _FilterSidebar(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BigMonthGrid extends StatelessWidget {
  const _BigMonthGrid({
    required this.visibleMonth,
    required this.termine,
    required this.onSelect,
    required this.onMonthChange,
  });
  final DateTime visibleMonth;
  final List<TerminEintrag> termine;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<DateTime> onMonthChange;

  @override
  Widget build(BuildContext context) {
    final monthFmt = DateFormat('MMMM yyyy', 'de');
    final first = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final startOffset = first.weekday - 1;
    final daysInMonth =
        DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final today = _dateOnly(DateTime.now());

    final perTag = <DateTime, List<TerminEintrag>>{};
    for (final t in termine) {
      perTag.putIfAbsent(t.tag, () => []).add(t);
    }

    final totalCells = ((startOffset + daysInMonth) / 7).ceil() * 7;
    final weeksCount = totalCells ~/ 7;

    final counters = _zaehle(termine, visibleMonth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Meta-Zeile: eyebrow + H1 + Monat-Zähler
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'KALENDER · ${monthFmt.format(visibleMonth).toUpperCase()}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 11 * 0.05,
                      color: AwTokens.mute,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    monthFmt.format(visibleMonth),
                    style: const TextStyle(
                      fontSize: AwTokens.textH1,
                      fontWeight: FontWeight.w600,
                      letterSpacing: AwTokens.textH1 * -0.025,
                      color: AwTokens.ink,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    counters,
                    style: const TextStyle(
                      fontSize: AwTokens.textMd,
                      color: AwTokens.mute,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              color: AwTokens.mute,
              tooltip: 'Vorheriger Monat',
              onPressed: () => onMonthChange(
                  DateTime(visibleMonth.year, visibleMonth.month - 1)),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              color: AwTokens.mute,
              tooltip: 'Nächster Monat',
              onPressed: () => onMonthChange(
                  DateTime(visibleMonth.year, visibleMonth.month + 1)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Kopfzeile MO-SO
        Container(
          decoration: BoxDecoration(
            color: AwTokens.paper,
            border: Border.all(color: AwTokens.line),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AwTokens.radiusLg),
            ),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
          child: Row(
            children: [
              for (final wd in const ['MO', 'DI', 'MI', 'DO', 'FR', 'SA', 'SO'])
                Expanded(
                  child: Text(
                    wd,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 10.5 * 0.05,
                      color: AwTokens.mute,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Grid
        Container(
          decoration: const BoxDecoration(
            color: AwTokens.white,
            border: Border(
              left: BorderSide(color: AwTokens.line),
              right: BorderSide(color: AwTokens.line),
              bottom: BorderSide(color: AwTokens.line),
            ),
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(AwTokens.radiusLg),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var w = 0; w < weeksCount; w++)
                _buildWeekRow(
                  context,
                  weekIndex: w,
                  startOffset: startOffset,
                  visibleMonth: visibleMonth,
                  today: today,
                  perTag: perTag,
                  isLast: w == weeksCount - 1,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeekRow(
    BuildContext context, {
    required int weekIndex,
    required int startOffset,
    required DateTime visibleMonth,
    required DateTime today,
    required Map<DateTime, List<TerminEintrag>> perTag,
    required bool isLast,
  }) {
    final first = DateTime(visibleMonth.year, visibleMonth.month, 1)
        .subtract(Duration(days: startOffset));
    return SizedBox(
      height: 120,
      child: Row(
        children: [
          for (var d = 0; d < 7; d++)
            Expanded(
              child: _buildDayCell(
                context,
                day: first.add(Duration(days: weekIndex * 7 + d)),
                visibleMonth: visibleMonth,
                today: today,
                entries: perTag[first.add(Duration(days: weekIndex * 7 + d))] ??
                    const [],
                showRightBorder: d < 6,
                showBottomBorder: !isLast,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDayCell(
    BuildContext context, {
    required DateTime day,
    required DateTime visibleMonth,
    required DateTime today,
    required List<TerminEintrag> entries,
    required bool showRightBorder,
    required bool showBottomBorder,
  }) {
    final inMonth = day.month == visibleMonth.month;
    final isToday = day == today;
    return InkWell(
      onTap: () => onSelect(day),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: isToday ? AwTokens.orangeSoft : null,
          border: Border(
            right: showRightBorder
                ? const BorderSide(color: AwTokens.line)
                : BorderSide.none,
            bottom: showBottomBorder
                ? const BorderSide(color: AwTokens.line)
                : BorderSide.none,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dayNumber(day, isToday: isToday, inMonth: inMonth),
            const SizedBox(height: 4),
            for (final e in entries.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: _EventPill(e: e),
              ),
            if (entries.length > 3)
              Padding(
                padding: const EdgeInsets.only(left: 2, top: 2),
                child: Text(
                  '+${entries.length - 3} weitere',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AwTokens.mute,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dayNumber(DateTime day,
      {required bool isToday, required bool inMonth}) {
    final text = '${day.day}';
    if (isToday) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AwTokens.orange,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AwTokens.white,
          ),
        ),
      );
    }
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: inMonth ? AwTokens.ink : AwTokens.muteSoft,
      ),
    );
  }

  String _zaehle(List<TerminEintrag> termine, DateTime visibleMonth) {
    final start = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final end = DateTime(visibleMonth.year, visibleMonth.month + 1, 0);
    int c(String typ) => termine
        .where((t) =>
            t.typ == typ &&
            !t.tag.isBefore(start) &&
            !t.tag.isAfter(end))
        .length;
    final teile = <String>[
      if (c('Ortstermin') > 0) '${c('Ortstermin')} Ortstermine',
      if (c('Frist') > 0) '${c('Frist')} Fristen',
      if (c('Erläuterung') > 0) '${c('Erläuterung')} Gerichtstermine',
      if (c('Wiedervorlage') > 0) '${c('Wiedervorlage')} Wiedervorlagen',
    ];
    return teile.isEmpty ? 'Keine Termine in diesem Monat' : teile.join(' · ');
  }
}

/// Event-Pill in einer Monatszelle — Dot links, Titel rechts, Farbe je Typ.
/// Tap öffnet die Akte (sofern verknüpft) oder den passenden Editor.
class _EventPill extends StatelessWidget {
  const _EventPill({required this.e});
  final TerminEintrag e;
  @override
  Widget build(BuildContext context) {
    final c = _farbeFuer(e.typ);
    return Material(
      color: c.bg,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => _openTermin(context, e),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: c.fg, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  e.titel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: c.fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zentrale Aktion „Termin öffnen" — zeigt einen Detail-Dialog mit
/// Zeit, Ort, Akte + Aktions-Buttons (Akte öffnen, Schließen).
/// Wird von Big-Month-Pille, Heute-Agenda und _TerminCard verwendet.
void _openTermin(BuildContext context, TerminEintrag e) {
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _TerminDetailDialog(eintrag: e),
  );
}

class _TerminDetailDialog extends StatelessWidget {
  const _TerminDetailDialog({required this.eintrag});
  final TerminEintrag eintrag;

  @override
  Widget build(BuildContext context) {
    final c = _farbeFuer(eintrag.typ);
    final dateFmt = DateFormat('EEEE, d. MMMM yyyy', 'de');
    final timeFmt = DateFormat('HH:mm', 'de');
    final start = eintrag.zeitpunkt;
    final ende = eintrag.ende;
    final zeit = ende == null
        ? timeFmt.format(start)
        : '${timeFmt.format(start)} – ${timeFmt.format(ende)}';

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AwTokens.radiusXl),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AwTokens.radiusXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
                decoration: const BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: AwTokens.line)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: c.dot,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            eintrag.typ.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 10 * 0.05,
                              color: AwTokens.mute,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            eintrag.titel,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 16 * -0.015,
                              color: AwTokens.ink,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      iconSize: 16,
                      icon: const Icon(Icons.close),
                      color: AwTokens.mute,
                      tooltip: 'Schließen',
                      onPressed: () =>
                          Navigator.of(context, rootNavigator: true).pop(),
                    ),
                  ],
                ),
              ),
              // Body — Daten-Zeilen
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DetailRow(
                      icon: Icons.calendar_today_outlined,
                      label: dateFmt.format(start),
                    ),
                    _DetailRow(
                      icon: Icons.schedule_outlined,
                      label: zeit,
                    ),
                    if ((eintrag.ort ?? '').isNotEmpty)
                      _DetailRow(
                        icon: Icons.location_on_outlined,
                        label: eintrag.ort!,
                      ),
                    if ((eintrag.aktenzeichen ?? '').isNotEmpty)
                      _DetailRow(
                        icon: Icons.folder_open_outlined,
                        label: 'Akte ${eintrag.aktenzeichen}',
                        labelColor: AwTokens.orange,
                      ),
                    if ((eintrag.telefon ?? '').isNotEmpty)
                      _DetailRow(
                        icon: Icons.phone_outlined,
                        label: eintrag.telefon!,
                      ),
                  ],
                ),
              ),
              // Footer
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: AwTokens.paper,
                  border: Border(top: BorderSide(color: AwTokens.line)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (eintrag.istOrtstermin &&
                        (eintrag.ort ?? '').isNotEmpty)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.directions_outlined, size: 16),
                        label: const Text('Route'),
                        onPressed: () => _routeOeffnen(context, eintrag.ort!),
                      ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Bearbeiten'),
                      onPressed: () {
                        Navigator.of(context, rootNavigator: true).pop();
                        _editTermin(context, eintrag);
                      },
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context, rootNavigator: true).pop(),
                      child: const Text('Schließen'),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: Text(_actionLabel(eintrag)),
                      onPressed: () {
                        Navigator.of(context, rootNavigator: true).pop();
                        _navigateToSource(context, eintrag);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _actionLabel(TerminEintrag e) {
    if (e.auftragId != null) return 'Akte öffnen';
    return switch (e.typ) {
      'Wiedervorlage' => 'Wiedervorlagen',
      'Erläuterung' => 'Erläuterungen',
      _ => 'Öffnen',
    };
  }

  /// Öffnet den passenden Editor für den Termin-Typ.
  /// Ortstermin/Frist → Auftrag-Editor (mit vorausgewähltem Datensatz).
  /// Erläuterung → Erläuterungs-Editor.
  /// Wiedervorlage → Listen-Screen mit ID-Filter.
  Future<void> _editTermin(BuildContext context, TerminEintrag e) async {
    final container = ProviderScope.containerOf(context);
    final db = container.read(appDatabaseProvider);
    switch (e.typ) {
      case 'Ortstermin':
      case 'Frist':
        if (e.auftragId == null) return;
        final auftrag = await (db.select(db.auftraege)
              ..where((t) => t.id.equals(e.auftragId!)))
            .getSingleOrNull();
        if (auftrag == null || !context.mounted) return;
        await showAuftragFormDialog(context, auftrag: auftrag);
        return;
      case 'Erläuterung':
        if (e.quellId == null) return;
        final erl = await (db.select(db.erlaeuterungen)
              ..where((t) => t.id.equals(e.quellId!)))
            .getSingleOrNull();
        if (erl == null || !context.mounted) return;
        AuftraegeData? auftrag;
        if (erl.auftragId != null) {
          auftrag = await (db.select(db.auftraege)
                ..where((t) => t.id.equals(erl.auftragId!)))
              .getSingleOrNull();
        }
        if (!context.mounted) return;
        await showErlaeuterungEditor(
          context,
          eintrag: ErlaeuterungWithAuftrag(erl, auftrag),
        );
        return;
      case 'Wiedervorlage':
        // Kein direkter Editor exportiert — User landet in der
        // Wiedervorlagen-Liste und kann den Eintrag dort anklicken.
        context.go('/wiedervorlagen');
        return;
    }
  }

  void _navigateToSource(BuildContext context, TerminEintrag e) {
    if (e.auftragId != null) {
      context.go('/akte/${e.auftragId}');
      return;
    }
    switch (e.typ) {
      case 'Wiedervorlage':
        context.go('/wiedervorlagen');
        return;
      case 'Erläuterung':
        context.go('/erlaeuterungen');
        return;
    }
  }

  Future<void> _routeOeffnen(BuildContext context, String ort) async {
    final url = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(ort)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    this.labelColor,
  });
  final IconData icon;
  final String label;
  final Color? labelColor;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AwTokens.mute),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: labelColor ?? AwTokens.ink,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeuteAgenda extends StatelessWidget {
  const _HeuteAgenda({required this.termine});
  final List<TerminEintrag> termine;
  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final heute = termine.where((t) => t.tag == today).toList()
      ..sort((a, b) => a.zeitpunkt.compareTo(b.zeitpunkt));
    final dateFmt = DateFormat('d. MMMM', 'de');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'HEUTE · ${dateFmt.format(today).toUpperCase()}',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 10 * 0.08,
            color: AwTokens.mute,
          ),
        ),
        const SizedBox(height: 8),
        if (heute.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Keine Termine heute',
              style: TextStyle(
                  fontSize: 12.5, color: AwTokens.mute, height: 1.4),
            ),
          )
        else
          for (final t in heute)
            InkWell(
              onTap: () => _openTermin(context, t),
              borderRadius: BorderRadius.circular(AwTokens.radiusSm),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        DateFormat('HH:mm').format(t.zeitpunkt),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AwTokens.ink,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.titel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AwTokens.ink,
                              height: 1.35,
                            ),
                          ),
                          if ((t.ort ?? '').isNotEmpty)
                            Text(
                              t.ort!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AwTokens.mute,
                                height: 1.35,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _FilterSidebar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(_typFilterProvider);
    const typen = ['Ortstermin', 'Frist', 'Erläuterung', 'Wiedervorlage'];
    const labels = {
      'Ortstermin': 'Ortstermine',
      'Frist': 'Fristen',
      'Erläuterung': 'Gerichtstermine',
      'Wiedervorlage': 'Wiedervorlagen',
    };
    return Container(
      decoration: BoxDecoration(
        color: AwTokens.white,
        border: Border.all(color: AwTokens.line),
        borderRadius: BorderRadius.circular(AwTokens.radiusLg),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'KALENDER',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 10 * 0.08,
              color: AwTokens.mute,
            ),
          ),
          const SizedBox(height: 8),
          for (final t in typen)
            InkWell(
              onTap: () => ref.read(_typFilterProvider.notifier).state = {
                ...filter,
                t: !(filter[t] ?? true),
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    _CheckSquare(
                      active: filter[t] ?? true,
                      color: _farbeFuer(t).dot,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      labels[t] ?? t,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AwTokens.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CheckSquare extends StatelessWidget {
  const _CheckSquare({required this.active, required this.color});
  final bool active;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: active ? color : AwTokens.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: active ? color : AwTokens.lineStrong, width: 1.5),
      ),
      child: active
          ? const Icon(Icons.check, size: 12, color: AwTokens.white)
          : null,
    );
  }
}
