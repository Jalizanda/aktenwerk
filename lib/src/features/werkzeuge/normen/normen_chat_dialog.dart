import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:convert';

import '../../../core/ai/normen_chat_service.dart';
import '../../../data/database/app_database.dart';
import '../../../features/akten/auftraege/auftrag_picker.dart';
import '../recherche_ablage/recherche_ablage_repository.dart';
import 'normen_repository.dart';

/// Modaler Chat, der Fragen zur Normen-Bibliothek mit Gemini beantwortet.
/// Metadaten aller Normen werden immer als Kontext mitgegeben, PDFs der
/// bis zu drei inhaltlich passendsten Normen werden hochgeladen.
class NormenChatDialog extends ConsumerStatefulWidget {
  const NormenChatDialog({super.key, this.embedded = false});

  /// `true`, wenn der Dialog in einem [TabBarView] dargestellt wird —
  /// dann wird auf eigene [Dialog]-Hülle verzichtet.
  final bool embedded;

  @override
  ConsumerState<NormenChatDialog> createState() => _NormenChatDialogState();
}

class _NormenChatDialogState extends ConsumerState<NormenChatDialog> {
  final _eingabeCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  NormenChatSession? _session;
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
    if (text.isEmpty || _laedt || _session == null) return;
    _eingabeCtrl.clear();
    setState(() {
      _laedt = true;
      _fehler = null;
    });
    // Optimistisch die Nutzernachricht in die Historie schreiben, damit sie
    // sofort im Chat-Verlauf erscheint. Die eigentliche Eintragung in
    // _session.historie geschieht erst, wenn die Antwort da ist — die
    // Service-Methode fügt dann beide Nachrichten (user+assistant) an.
    WidgetsBinding.instance.addPostFrameCallback((_) => _zumEnde());
    try {
      await _session!.frage(text);
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

  @override
  Widget build(BuildContext context) {
    final normenAsync = ref.watch(normenListProvider);
    final scheme = Theme.of(context).colorScheme;

    final inner = normenAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (normen) {
        _session ??= NormenChatSession(ref, normen);
        final mitPdf = normen
            .where((n) =>
                n.pdfStorageUrl != null && n.pdfStorageUrl!.isNotEmpty)
            .length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(scheme, normen.length, mitPdf),
            const Divider(height: 1),
            Expanded(
              child: _session!.historie.isEmpty
                  ? _buildEmptyState(scheme, normen.length, mitPdf)
                  : _buildVerlauf(scheme),
            ),
            if (_fehler != null) _buildFehler(scheme),
            if (_laedt) _buildLadeIndikator(scheme),
            const Divider(height: 1),
            _buildEingabe(scheme),
          ],
        );
      },
    );
    if (widget.embedded) return inner;
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
        child: inner,
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme, int total, int mitPdf) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Icon(Icons.psychology_alt_outlined,
              color: scheme.primary, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Normen-KI — Fragen stellen',
                    style: Theme.of(context).textTheme.titleLarge),
                Text(
                  '$total Normen in Bibliothek · $mitPdf mit PDF · Top 3 '
                  'mit PDF werden pro Frage an die KI gesendet',
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme scheme, int total, int mitPdf) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined,
              size: 44, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            'Stell eine Frage zu deinen Normen.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Die KI kennt alle $total Einträge aus der Bibliothek als '
            'Kontext. Passt deine Frage zu einer Norm mit PDF, wird der '
            'PDF-Volltext automatisch gelesen und zitiert.',
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
                'Welche DIN gilt für Abdichtungen im Keller?',
                'Was fordert DIN 18195 zu Perimeterdämmung?',
                'Gibt es eine aktuelle WTA-Richtlinie zu Schimmelpilz?',
                'Welche Prüfpflichten nennt die VOB/C zu Estrich?',
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
    final historie = _session!.historie;
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(16),
      itemCount: historie.length,
      itemBuilder: (_, i) => _buildNachricht(historie[i], scheme),
    );
  }

  Widget _buildNachricht(NormenChatNachricht n, ColorScheme scheme) {
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
                if (!istUser && n.verwendeteNormen.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text('Aus PDFs gelesen:',
                          style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic)),
                      for (final norm in n.verwendeteNormen)
                        _normChip(norm, scheme),
                    ],
                  ),
                ],
                if (!istUser) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        icon: const Icon(
                            Icons.bookmark_add_outlined,
                            size: 14),
                        label: const Text(
                            'Zu Recherche-Ablage hinzufügen',
                            style: TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          visualDensity: VisualDensity.compact,
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _zuRechercheAblage(n),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (istUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// Öffnet einen Dialog, in dem der Nutzer die KI-Antwort als Notiz
  /// in die Recherche-Ablage überträgt — optional mit Akten-Zuordnung.
  Future<void> _zuRechercheAblage(NormenChatNachricht nachricht) async {
    // Titel aus erster Frage-Nachricht vor dieser Antwort ermitteln,
    // fallbacks auf Zeitstempel.
    final idx = _session!.historie.indexOf(nachricht);
    String vorschlagTitel = 'Recherche ${_kurzzeit()}';
    for (var i = idx - 1; i >= 0; i--) {
      if (_session!.historie[i].rolle == 'user') {
        vorschlagTitel = _kuerze(_session!.historie[i].inhalt, 80);
        break;
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _MerkenDialog(
        vorschlagTitel: vorschlagTitel,
        inhalt: nachricht.inhalt,
        verwendeteNormenIds:
            nachricht.verwendeteNormen.map((n) => n.id).toList(),
      ),
    );
  }

  String _kurzzeit() {
    final n = DateTime.now();
    return '${n.day}.${n.month}. ${n.hour}:${n.minute.toString().padLeft(2, '0')}';
  }

  String _kuerze(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max).trimRight()}…';

  Widget _normChip(NormenData n, ColorScheme scheme) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.picture_as_pdf,
              size: 12, color: scheme.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(n.nummer,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimaryContainer)),
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
          Text('KI liest passende PDFs und antwortet …',
              style: TextStyle(
                  fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _buildEingabe(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _eingabeCtrl,
              minLines: 1,
              maxLines: 4,
              enabled: !_laedt,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Frage an die Normen-Bibliothek …',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _senden(),
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

/// Dialog zum Ablegen einer KI-Antwort in der Recherche-Zwischenablage.
/// Der Nutzer kann Titel und Text bearbeiten und optional eine Akte
/// zuordnen. Beim Speichern wandert der Eintrag in die Drift-Tabelle
/// `recherche_notizen`.
class _MerkenDialog extends ConsumerStatefulWidget {
  const _MerkenDialog({
    required this.vorschlagTitel,
    required this.inhalt,
    required this.verwendeteNormenIds,
  });
  final String vorschlagTitel;
  final String inhalt;
  final List<int> verwendeteNormenIds;

  @override
  ConsumerState<_MerkenDialog> createState() => _MerkenDialogState();
}

class _MerkenDialogState extends ConsumerState<_MerkenDialog> {
  late final _titelCtrl =
      TextEditingController(text: widget.vorschlagTitel);
  late final _inhaltCtrl = TextEditingController(text: widget.inhalt);
  int? _auftragId;
  bool _saving = false;

  @override
  void dispose() {
    _titelCtrl.dispose();
    _inhaltCtrl.dispose();
    super.dispose();
  }

  Future<void> _speichern() async {
    setState(() => _saving = true);
    try {
      await ref.read(rechercheAblageRepositoryProvider).insert(
            auftragId: _auftragId,
            titel: _titelCtrl.text,
            inhalt: _inhaltCtrl.text,
            quelle: 'Normen-Chat',
            referenzNormenJson: widget.verwendeteNormenIds.isEmpty
                ? null
                : jsonEncode(widget.verwendeteNormenIds),
          );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'In Recherche-Ablage gespeichert — später im Gutachten einfügbar.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.bookmark_add_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('In Recherche-Ablage speichern',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context,
                                rootNavigator: true)
                            .pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _titelCtrl,
                maxLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Titel',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _inhaltCtrl,
                minLines: 4,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: 'Inhalt',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              AuftragPickerField(
                auftragId: _auftragId,
                onChanged: (id) => setState(() => _auftragId = id),
              ),
              const SizedBox(height: 6),
              Text(
                'Ohne Akten-Zuordnung wird die Notiz in jedem Gutachten-'
                'Editor als globale Recherche-Notiz angeboten.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context,
                                rootNavigator: true)
                            .pop(),
                    child: const Text('Abbrechen'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                        : const Icon(Icons.check, size: 16),
                    label: Text(_saving ? 'Speichere …' : 'Speichern'),
                    onPressed: _saving ? null : _speichern,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

