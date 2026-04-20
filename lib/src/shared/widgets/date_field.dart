import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'form_widgets.dart';

/// Formularfeld mit deutschem Datum und Kalender-Picker. Label steht —
/// einheitlich zu allen anderen Feldern — **über** dem Eingabefeld.
class DateField extends StatefulWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  State<DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<DateField> {
  static final _fmt = DateFormat('dd.MM.yyyy', 'de');

  @override
  Widget build(BuildContext context) {
    final text = widget.value == null ? '' : _fmt.format(widget.value!);
    return LabeledField(
      widget.label,
      InputDecorator(
        decoration: InputDecoration(
          isDense: true,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.value != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => widget.onChanged(null),
                  tooltip: 'Datum löschen',
                ),
              IconButton(
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                onPressed: _pick,
                tooltip: 'Kalender',
              ),
            ],
          ),
        ),
        child: InkWell(
          onTap: _pick,
          child: Text(
            text,
            style: text.isEmpty
                ? TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)
                : null,
          ),
        ),
      ),
    );
  }

  Future<void> _pick() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.value ?? now,
      firstDate: widget.firstDate ?? DateTime(now.year - 20),
      lastDate: widget.lastDate ?? DateTime(now.year + 10),
      locale: const Locale('de'),
    );
    if (picked != null) widget.onChanged(picked);
  }
}
