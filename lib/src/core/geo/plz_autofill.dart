import 'dart:async';

import 'package:flutter/widgets.dart';

import 'plz_service.dart';

/// Verbindet ein PLZ- mit einem Ort-`TextEditingController` so, dass beim
/// Eintragen einer 5-stelligen PLZ der Ort automatisch nachgeladen und
/// gesetzt wird — aber nur, wenn der Ort noch leer ist (bestehende
/// Eingaben werden nicht überschrieben).
///
/// Liefert eine `dispose`-Funktion, die in `State.dispose` aufgerufen
/// werden sollte, um den Listener wieder zu lösen.
VoidCallback attachPlzAutoFill(
  TextEditingController plz,
  TextEditingController ort,
) {
  String? lastLookup;
  Timer? debounce;

  void onChange() {
    final value = plz.text.trim();
    if (value.length != 5) return;
    if (int.tryParse(value) == null) return;
    if (value == lastLookup) return;
    lastLookup = value;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), () async {
      final result = await PlzService.ortFromPlz(value);
      if (result == null || result.isEmpty) return;
      // Nur überschreiben, wenn das Ort-Feld leer ist oder noch der
      // vorige Auto-Fill-Wert drin steht.
      if (ort.text.trim().isEmpty) {
        ort.text = result;
        ort.selection = TextSelection.collapsed(offset: result.length);
      }
    });
  }

  plz.addListener(onChange);
  return () {
    debounce?.cancel();
    plz.removeListener(onChange);
  };
}
