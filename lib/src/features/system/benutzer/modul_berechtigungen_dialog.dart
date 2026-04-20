import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'modul_katalog.dart';

/// Zeigt einen Dialog mit Checkboxen pro Modul. Für jeden Modul können
/// zwei Rechte gesetzt werden: „Ansehen" und „Bearbeiten".
///
/// Default: alle Häkchen gesetzt (volle Rechte). Ohne Ansehen-Häkchen sieht
/// der Benutzer das Modul nicht; ohne Bearbeiten-Häkchen nur Read-Only.
Future<ModulRechte?> showModulBerechtigungenDialog(
  BuildContext context, {
  required String memberName,
  String? initialErlaubt,
  String? initialBearbeitbar,
}) {
  return showDialog<ModulRechte>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _ModulBerechtigungenDialog(
      memberName: memberName,
      initialErlaubt: initialErlaubt,
      initialBearbeitbar: initialBearbeitbar,
    ),
  );
}

class _ModulBerechtigungenDialog extends StatefulWidget {
  const _ModulBerechtigungenDialog({
    required this.memberName,
    this.initialErlaubt,
    this.initialBearbeitbar,
  });
  final String memberName;
  final String? initialErlaubt;
  final String? initialBearbeitbar;

  @override
  State<_ModulBerechtigungenDialog> createState() =>
      _ModulBerechtigungenDialogState();
}

class _ModulBerechtigungenDialogState
    extends State<_ModulBerechtigungenDialog> {
  late Set<String> _erlaubt;
  late Set<String> _bearbeitbar;

  @override
  void initState() {
    super.initState();
    // Default: alle gesetzt, wenn noch nichts konfiguriert.
    if (widget.initialErlaubt == null) {
      _erlaubt = alleModulKeys.toSet();
    } else {
      _erlaubt = widget.initialErlaubt!
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();
    }
    if (widget.initialBearbeitbar == null) {
      _bearbeitbar = alleModulKeys.toSet();
    } else {
      _bearbeitbar = widget.initialBearbeitbar!
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();
    }
  }

  void _toggleErlaubt(String key, bool value) {
    setState(() {
      if (value) {
        _erlaubt.add(key);
      } else {
        _erlaubt.remove(key);
        // Ohne Ansehen kein Bearbeiten.
        _bearbeitbar.remove(key);
      }
    });
  }

  void _toggleBearbeitbar(String key, bool value) {
    setState(() {
      if (value) {
        _bearbeitbar.add(key);
        // Ohne Ansehen kein Bearbeiten — also auch Ansehen setzen.
        _erlaubt.add(key);
      } else {
        _bearbeitbar.remove(key);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _erlaubt = alleModulKeys.toSet();
      _bearbeitbar = alleModulKeys.toSet();
    });
  }

  void _selectNone() {
    setState(() {
      _erlaubt = <String>{};
      _bearbeitbar = <String>{};
    });
  }

  void _viewOnly() {
    setState(() {
      _erlaubt = alleModulKeys.toSet();
      _bearbeitbar = <String>{};
    });
  }

  @override
  Widget build(BuildContext context) {
    final gruppen = <String, List<AppModul>>{};
    for (final m in appModule) {
      gruppen.putIfAbsent(m.gruppe, () => []).add(m);
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.tune_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Modul-Berechtigungen',
                            style:
                                Theme.of(context).textTheme.titleMedium),
                        Text(widget.memberName,
                            style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.slate500)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context,
                            rootNavigator: true)
                        .pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.check_box, size: 16),
                    label: const Text('Alle erlauben'),
                    onPressed: _selectAll,
                  ),
                  OutlinedButton.icon(
                    icon:
                        const Icon(Icons.check_box_outline_blank, size: 16),
                    label: const Text('Keine'),
                    onPressed: _selectNone,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('Alle nur Lesen'),
                    onPressed: _viewOnly,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Modul',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate500,
                            letterSpacing: 1)),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text('Ansehen',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate500,
                            letterSpacing: 1)),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text('Bearbeiten',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate500,
                            letterSpacing: 1)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final e in gruppen.entries) ...[
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(12, 12, 12, 6),
                      child: Text(
                        e.key.toUpperCase(),
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.slate500,
                            letterSpacing: 0.08 * 10.5),
                      ),
                    ),
                    for (final m in e.value)
                      _ModulRow(
                        modul: m,
                        ansehen: _erlaubt.contains(m.key),
                        bearbeiten: _bearbeitbar.contains(m.key),
                        onAnsehenChanged: (v) => _toggleErlaubt(m.key, v),
                        onBearbeitenChanged: (v) =>
                            _toggleBearbeitbar(m.key, v),
                      ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context,
                            rootNavigator: true)
                        .pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Speichern'),
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pop(
                        ModulRechte(
                          erlaubt: _erlaubt,
                          bearbeitbar: _bearbeitbar,
                          istAdmin: false,
                        ),
                      );
                    },
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

class _ModulRow extends StatelessWidget {
  const _ModulRow({
    required this.modul,
    required this.ansehen,
    required this.bearbeiten,
    required this.onAnsehenChanged,
    required this.onBearbeitenChanged,
  });
  final AppModul modul;
  final bool ansehen;
  final bool bearbeiten;
  final ValueChanged<bool> onAnsehenChanged;
  final ValueChanged<bool> onBearbeitenChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(modul.icon, size: 18, color: AppTheme.slate500),
                const SizedBox(width: 8),
                Text(modul.label,
                    style: const TextStyle(fontSize: 13.5)),
              ],
            ),
          ),
          SizedBox(
            width: 80,
            child: Center(
              child: Checkbox(
                value: ansehen,
                onChanged: (v) => onAnsehenChanged(v ?? false),
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Center(
              child: Checkbox(
                value: bearbeiten,
                onChanged: ansehen
                    ? (v) => onBearbeitenChanged(v ?? false)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
