import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/aw_tokens.dart';

/// Öffnet den interaktiven Formeleditor für Bausachverständige.
///
/// Ermöglicht das Erstellen sauber formatierter mathematischer Formeln,
/// Berechnungen, Brüche, Fuß- und Hochnoten (Indizes & Exponenten)
/// und typischer Bauphysik-/Statik-Nachweise.
Future<String?> showFormelEditorDialog(
  BuildContext context, {
  String? initialText,
}) async {
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _FormelEditorDialog(initialText: initialText),
  );
}

class _FormelEditorDialog extends StatefulWidget {
  const _FormelEditorDialog({this.initialText});
  final String? initialText;

  @override
  State<_FormelEditorDialog> createState() => _FormelEditorDialogState();
}

class _FormelEditorDialogState extends State<_FormelEditorDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialText ?? '');
  final FocusNode _focusNode = FocusNode();

  void _insert(String text) {
    final sel = _ctrl.selection;
    final current = _ctrl.text;
    final start = sel.isValid ? sel.start : current.length;
    final end = sel.isValid ? sel.end : current.length;
    final neu = current.replaceRange(start, end, text);
    _ctrl.text = neu;
    _ctrl.selection = TextSelection.collapsed(offset: start + text.length);
    _focusNode.requestFocus();
    setState(() {});
  }

  void _setVorlage(String vorlage) {
    if (_ctrl.text.trim().isEmpty) {
      _ctrl.text = vorlage;
    } else {
      _insert('\n$vorlage');
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 700;

    return Dialog(
      insetPadding: isMobile
          ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 780),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.accent50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.functions,
                        color: AppTheme.accent600, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Formeleditor & Berechnungen',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Formeln mit Brüchen, Indizes, Exponenten und Rechenwegen erstellen',
                          style: TextStyle(fontSize: 12, color: AwTokens.mute),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Inhalt
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Textfeld für die Formel
                    Text(
                      'Formel / Berechnungstext:',
                      style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold, color: AwTokens.ink),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _ctrl,
                      focusNode: _focusNode,
                      maxLines: 4,
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'z. B. s_cr,N = 3 · h_ef = 3 · 50 mm = 150 mm\nAc,N / (2 · A⁰c,N) = ½ · (1 + s / s_cr,N) = 0,90',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),

                    // Live-Vorschau Box
                    Text(
                      'Vorschau im Gutachten:',
                      style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold, color: AwTokens.ink),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 1)),
                        ],
                      ),
                      child: _ctrl.text.trim().isEmpty
                          ? Text(
                              '(Hier erscheint die formatierte Vorschau)',
                              style: TextStyle(
                                  color: AwTokens.mute,
                                  fontStyle: FontStyle.italic,
                                  fontSize: 13),
                            )
                          : SelectableText(
                              _ctrl.text,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                    const SizedBox(height: 16),

                    // Baustein-Tabs & Buttons
                    _buildSectionHeader('Schnell-Symbole & Operatoren'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _symbolBtn('·', 'Mal / Multiplikation'),
                        _symbolBtn('×', 'Kreuz-Multiplikation'),
                        _symbolBtn('±', 'Plus-Minus'),
                        _symbolBtn('≤', 'Kleiner-Gleich'),
                        _symbolBtn('≥', 'Größer-Gleich'),
                        _symbolBtn('≈', 'Ungefähr / Rund'),
                        _symbolBtn('≠', 'Ungleich'),
                        _symbolBtn('√', 'Wurzel'),
                        _symbolBtn('∆', 'Delta (Differenz)'),
                        _symbolBtn('∑', 'Summe'),
                        _symbolBtn('½', 'Einhalb Bruch'),
                        _symbolBtn('⅓', 'Eindrittel Bruch'),
                        _symbolBtn('¼', 'Einviertel Bruch'),
                        _symbolBtn('—', 'Gedankenstrich'),
                      ],
                    ),
                    const SizedBox(height: 14),

                    _buildSectionHeader('Fußnoten & Indizes (Tiefstellung)'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        _symbolBtn('₀', '0'),
                        _symbolBtn('₁', '1'),
                        _symbolBtn('₂', '2'),
                        _symbolBtn('₃', '3'),
                        _symbolBtn('₄', '4'),
                        _symbolBtn('₅', '5'),
                        _symbolBtn('₆', '6'),
                        _symbolBtn('₇', '7'),
                        _symbolBtn('₈', '8'),
                        _symbolBtn('₉', '9'),
                        _symbolBtn('ₑ', 'e'),
                        _symbolBtn('ₕ', 'h'),
                        _symbolBtn('ᵢ', 'i'),
                        _symbolBtn('ₖ', 'k'),
                        _symbolBtn('ₗ', 'l'),
                        _symbolBtn('ₘ', 'm'),
                        _symbolBtn('ₙ', 'n'),
                        _symbolBtn('ᵣ', 'r'),
                        _symbolBtn('ₛ', 's'),
                        _symbolBtn('ₜ', 't'),
                        _symbolBtn('ᵤ', 'u'),
                        _symbolBtn('ᵥ', 'v'),
                        _symbolBtn('ₓ', 'x'),
                        _textBtn('s_cr,N', 's_cr,N (charakteristischer Achsabstand)'),
                        _textBtn('c_cr,N', 'c_cr,N (charakteristischer Randabstand)'),
                        _textBtn('h_ef', 'h_ef (effektive Verankerungstiefe)'),
                        _textBtn('h_ef,red', 'h_ef,red (reduzierte Verankerungstiefe)'),
                        _textBtn('N_Rk', 'N_Rk (charakteristischer Zugwiderstand)'),
                        _textBtn('V_Rk', 'V_Rk (charakteristischer Querwiderstand)'),
                        _textBtn('N_Ed', 'N_Ed (Bemessungszugkraft)'),
                        _textBtn('V_Ed', 'V_Ed (Bemessungsquerkraft)'),
                        _textBtn('M_Ed', 'M_Ed (Bemessungsbiegemoment)'),
                        _textBtn('W_el', 'W_el (Widerstandsmoment)'),
                        _textBtn('f_Rsi', 'f_Rsi (Temperaturfaktor)'),
                        _textBtn('U_f', 'U_f (Rahmen-U-Wert)'),
                        _textBtn('U_g', 'U_g (Glas-U-Wert)'),
                        _textBtn('U_cw', 'U_cw (Fassaden-U-Wert)'),
                      ],
                    ),
                    const SizedBox(height: 14),

                    _buildSectionHeader('Hochnoten & Exponenten (Hochstellung)'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        _symbolBtn('²', 'Quadrat (z. B. m²)'),
                        _symbolBtn('³', 'Kubik (z. B. m³)'),
                        _symbolBtn('⁴', 'Hoch 4 (z. B. cm⁴)'),
                        _symbolBtn('⁰', 'Hoch 0'),
                        _symbolBtn('¹', 'Hoch 1'),
                        _symbolBtn('⁵', 'Hoch 5'),
                        _symbolBtn('⁶', 'Hoch 6'),
                        _symbolBtn('⁷', 'Hoch 7'),
                        _symbolBtn('⁸', 'Hoch 8'),
                        _symbolBtn('⁹', 'Hoch 9'),
                        _symbolBtn('⁺', 'Hoch Plus'),
                        _symbolBtn('⁻', 'Hoch Minus'),
                        _symbolBtn('°', 'Grad'),
                      ],
                    ),
                    const SizedBox(height: 14),

                    _buildSectionHeader('Griechische Buchstaben'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        _symbolBtn('α', 'alpha'),
                        _symbolBtn('β', 'beta'),
                        _symbolBtn('γ', 'gamma'),
                        _symbolBtn('δ', 'delta'),
                        _symbolBtn('ε', 'epsilon'),
                        _symbolBtn('η', 'eta'),
                        _symbolBtn('θ', 'theta'),
                        _symbolBtn('λ', 'lambda'),
                        _symbolBtn('μ', 'my / my_k'),
                        _symbolBtn('π', 'pi'),
                        _symbolBtn('ρ', 'rho'),
                        _symbolBtn('σ', 'sigma (Spannung)'),
                        _symbolBtn('τ', 'tau (Schubspannung)'),
                        _symbolBtn('φ', 'phi'),
                        _symbolBtn('ψ', 'psi (Abminderungsbeiwert)'),
                        _symbolBtn('ω', 'omega'),
                        _symbolBtn('Ω', 'Omega'),
                      ],
                    ),
                    const SizedBox(height: 14),

                    _buildSectionHeader('Bautypische Einheiten'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _textBtn('kN/m', 'kN/m'),
                        _textBtn('kN', 'kN'),
                        _textBtn('N/mm²', 'N/mm²'),
                        _textBtn('MN/m²', 'MN/m²'),
                        _textBtn('W/(m²K)', 'W/(m²K)'),
                        _textBtn('cm⁴', 'cm⁴ (Trägheitsmoment)'),
                        _textBtn('cm³', 'cm³ (Widerstandsmoment)'),
                        _textBtn('mm', 'mm'),
                        _textBtn('m', 'm'),
                        _textBtn('kg/m²', 'kg/m²'),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Fertige Vorlagen
                    _buildSectionHeader('Praxis-Vorlagen (1-Klick übernehmen)'),
                    const SizedBox(height: 8),
                    _vorlageCard(
                      titel: 'Fischer Bolzenanker FBN II: Achsabstand (EN 1992-4 / ETAG 001)',
                      inhalt:
                          's_cr,N = 3 · h_ef = 3 · 50 mm = 150 mm\n'
                          'Ac,N / (2 · A⁰c,N) = ½ · (1 + s / s_cr,N) = ½ · (1 + 120 mm / 150 mm) = 0,90\n'
                          '(Geometrisches Verhältnis der projizierten Betonausbruchflächen)',
                    ),
                    const SizedBox(height: 6),
                    _vorlageCard(
                      titel: 'Fischer Bolzenanker FBN II: Randabstand (EN 1992-4)',
                      inhalt:
                          'c_cr,N = 1,5 · h_ef = 1,5 · 50 mm = 75 mm\n'
                          'c_vorh = 80 mm ≥ c_cr,N = 75 mm (voller Bruchkegel ohne Randabminderung bezüglich Querzug)',
                    ),
                    const SizedBox(height: 6),
                    _vorlageCard(
                      titel: 'Geländerpfosten: Biegemoment & Spannungsnachweis',
                      inhalt:
                          'M_Ed = H_k · γ_Q · h = 1,0 kN/m · 1,5 · 1,0 m = 1,50 kNm = 150 kNcm\n'
                          'σ_Ed = M_Ed / W_el = 150 kNcm / 4,85 cm³ = 30,9 kN/cm² = 309 N/mm² > f_y,d = 218 N/mm² (Überlastet)',
                    ),
                    const SizedBox(height: 6),
                    _vorlageCard(
                      titel: 'Wärmeschutz: Temperaturfaktor f_Rsi (DIN 4108-2)',
                      inhalt:
                          'f_Rsi = (θ_si - θ_e) / (θ_i - θ_e) ≥ 0,70\n'
                          'θ_si = Oberflächentemperatur innen, θ_i = 20,0 °C, θ_e = -5,0 °C',
                    ),
                    const SizedBox(height: 6),
                    _vorlageCard(
                      titel: 'Fassaden U_cw-Wert nach DIN EN ISO 12631',
                      inhalt:
                          'U_cw = (∑ A_g · U_g + ∑ A_f · U_f + ∑ l_g · Ψ_g) / A_ges ≤ 1,5 W/(m²K)',
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),

            // Footer
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Feld leeren'),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() {});
                    },
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('In Gutachten einfügen'),
                    onPressed: () {
                      final text = _ctrl.text.trim();
                      if (text.isEmpty) {
                        Navigator.pop(context);
                      } else {
                        Navigator.pop(context, text);
                      }
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

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: AwTokens.ink2,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _symbolBtn(String symbol, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => _insert(symbol),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text(
            symbol,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: 'Courier',
            ),
          ),
        ),
      ),
    );
  }

  Widget _textBtn(String text, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => _insert(text),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.blue.shade900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _vorlageCard({required String titel, required String inhalt}) {
    return InkWell(
      onTap: () => _setVorlage(inhalt),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.amber.shade50.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 14, color: Colors.amber.shade800),
                const SizedBox(width: 6),
                Text(
                  titel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Übernehmen ▾',
                  style: TextStyle(fontSize: 11, color: Colors.blue),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              inhalt,
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 11.5,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
