import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/anschreiben_chat_service.dart';

/// Modaler Chat, mit dem der Nutzer per Prompt einen Anschreiben-
/// Entwurf von der KI generieren und iterativ verbessern kann. Der
/// zuletzt gelieferte Entwurf lässt sich per „Übernehmen" in den
/// Anschreiben-Editor zurückgeben (als `String` über `Navigator.pop`).
class AnschreibenChatDialog extends ConsumerStatefulWidget {
  const AnschreibenChatDialog({super.key, required this.kontext});

  final AnschreibenKontext kontext;

  @override
  ConsumerState<AnschreibenChatDialog> createState() =>
      _AnschreibenChatDialogState();
}

class _AnschreibenChatDialogState
    extends ConsumerState<AnschreibenChatDialog> {
  final _eingabeCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final AnschreibenChatSession _session =
      AnschreibenChatSession(ref, widget.kontext);
  bool _laedt = false;
  String? _fehler;

  @override
  void dispose() {
    _eingabeCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _senden() async {
    final text = _eingabeCtrl.text.trim();
    if (text.isEmpty || _laedt) return;
    _eingabeCtrl.clear();
    setState(() {
      _laedt = true;
      _fehler = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _zumEnde());
    try {
      await _session.frage(text);
    } catch (e) {
      if (mounted) setState(() => _fehler = e.toString());
    } finally {
      if (mounted) {
        setState(() => _laedt = false);
        WidgetsBinding.instance.addPostFrameCallback((_) => _zumEnde());
      }
    }
  }

  void _zumEnde() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _uebernehmen() {
    final entwurf = _session.letzterEntwurf;
    if (entwurf == null || entwurf.trim().isEmpty) return;
    Navigator.of(context, rootNavigator: true).pop(entwurf);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hatEntwurf = (_session.letzterEntwurf ?? '').trim().isNotEmpty;
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(scheme, hatEntwurf),
            const Divider(height: 1),
            Expanded(
              child: _session.historie.isEmpty
                  ? _buildEmptyState(scheme)
                  : _buildVerlauf(scheme),
            ),
            if (_fehler != null) _buildFehler(scheme),
            if (_laedt) _buildLadeIndikator(scheme),
            const Divider(height: 1),
            _buildEingabe(scheme, hatEntwurf),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme, bool hatEntwurf) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: scheme.primary, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('KI — Anschreiben entwerfen',
                    style: Theme.of(context).textTheme.titleLarge),
                Text(
                  'Beschreibe per Prompt, was im Brief stehen soll. Der Entwurf '
                  'lässt sich beliebig oft verbessern. „Übernehmen" kopiert den '
                  'letzten Entwurf ins Anschreiben.',
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Übernehmen'),
            onPressed: hatEntwurf ? _uebernehmen : null,
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.drafts_outlined, size: 44, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            'Worum geht es in dem Brief?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Beispiele: „Bitte um Terminverschiebung", „Anforderung von '
            'Unterlagen", „Absage eines Ortstermins wegen Krankheit". Die '
            'KI nutzt Akte und Empfänger (falls gewählt) automatisch.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final q in [
                'Bestätigung des Ortstermins mit Wegbeschreibung',
                'Bitte um weitere Unterlagen zur Akte',
                'Erinnerung an ausstehende Rechnung',
                'Freundliche Absage wegen Terminkonflikt',
              ])
                ActionChip(
                  label: Text(q, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    _eingabeCtrl.text = q;
                    _senden();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerlauf(ColorScheme scheme) {
    final historie = _session.historie;
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(16),
      itemCount: historie.length,
      itemBuilder: (_, i) => _buildNachricht(historie[i], scheme),
    );
  }

  Widget _buildNachricht(
      AnschreibenChatNachricht n, ColorScheme scheme) {
    final istUser = n.rolle == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            istUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!istUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: scheme.primary,
              child: const Icon(Icons.auto_awesome,
                  size: 14, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: istUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: istUser
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    n.inhalt,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: istUser
                          ? scheme.onPrimary
                          : scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (istUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildFehler(ColorScheme scheme) {
    return Container(
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              size: 16, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_fehler!,
                style: TextStyle(
                    fontSize: 12, color: scheme.onErrorContainer)),
          ),
          IconButton(
            iconSize: 16,
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _fehler = null),
          ),
        ],
      ),
    );
  }

  Widget _buildLadeIndikator(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: scheme.primary),
          ),
          const SizedBox(width: 10),
          Text('KI entwirft den Brief …',
              style: TextStyle(
                  fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildEingabe(ColorScheme scheme, bool hatEntwurf) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _eingabeCtrl,
              minLines: 1,
              maxLines: 5,
              enabled: !_laedt,
              decoration: InputDecoration(
                isDense: true,
                hintText: hatEntwurf
                    ? 'Änderungswunsch (z. B. „förmlicher", „kürzer") …'
                    : 'Worum geht es in dem Brief? …',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              textInputAction: TextInputAction.newline,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Senden'),
            onPressed: _laedt ? null : _senden,
          ),
        ],
      ),
    );
  }
}
