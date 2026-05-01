import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ai/norm_rag_service.dart';
import '../../../core/theme/aw_tokens.dart';
import '../../../data/database/app_database.dart';
import '../recherche_ablage/recherche_ablage_repository.dart';
import 'norm_chat_history_repository.dart';
import 'normen_repository.dart';

/// RAG-basiertes Chat-UI mit links liegender Verlaufs-Sidebar (wie ChatGPT).
class NormenRagChatDialog extends ConsumerStatefulWidget {
  const NormenRagChatDialog({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<NormenRagChatDialog> createState() =>
      _NormenRagChatDialogState();
}

class _NormenRagChatDialogState extends ConsumerState<NormenRagChatDialog> {
  final _eingabeCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<NormChatNachricht> _historie = [];
  int? _aktiveChatId;
  bool _laedt = false;
  String? _fehler;
  final bool _autoSpeichern = true;

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
      _historie.add(NormChatNachricht(
        rolle: 'user',
        text: text,
        zeit: DateTime.now(),
      ));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _zumEnde());
    try {
      final service = ref.read(normRagServiceProvider);
      final antwort = await service.frage(
        frage: text,
        historie: _historie.take(_historie.length - 1).toList(),
      );
      if (!mounted) return;
      setState(() {
        _historie.add(NormChatNachricht(
          rolle: 'assistant',
          text: antwort.antwort,
          quellen: antwort.quellen,
          zeit: DateTime.now(),
        ));
      });
      // Auto-Speichern nach jeder Antwort
      if (_autoSpeichern) {
        final repo = ref.read(normChatHistoryRepositoryProvider);
        final id = await repo.save(
          id: _aktiveChatId,
          nachrichten: _historie,
        );
        if (mounted) setState(() => _aktiveChatId = id);
      }
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

  void _neuerChat() {
    setState(() {
      _historie.clear();
      _aktiveChatId = null;
      _fehler = null;
      _eingabeCtrl.clear();
    });
  }

  Future<void> _ladeChat(NormChat chat) async {
    final repo = ref.read(normChatHistoryRepositoryProvider);
    final nachrichten = repo.ladeNachrichten(chat);
    setState(() {
      _historie
        ..clear()
        ..addAll(nachrichten);
      _aktiveChatId = chat.id;
      _fehler = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _zumEnde());
  }

  Future<void> _quelleOeffnen(NormChatQuelle q) async {
    if (q.normId == null) return;
    final norm = await ref.read(normenRepositoryProvider).byId(q.normId!);
    final url = norm?.pdfStorageUrl;
    if (url == null || url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF-Quelle nicht verfügbar.')));
      return;
    }
    final uri = Uri.parse('$url#page=${q.page}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Kontextmenü-Aktionen pro Chat-Eintrag in der Sidebar.
  Future<void> _chatAktion(NormChat chat, String aktion) async {
    final repo = ref.read(normChatHistoryRepositoryProvider);
    switch (aktion) {
      case 'umbenennen':
        await _umbenennenDialog(chat, repo);
        break;
      case 'loeschen':
        await _loeschenDialog(chat, repo);
        break;
      case 'kopieren_recherche':
        await _kopiereInRecherche(chat, repo);
        break;
    }
  }

  Future<void> _umbenennenDialog(
      NormChat chat, NormChatHistoryRepository repo) async {
    final ctrl = TextEditingController(text: chat.titel);
    final neu = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Chat umbenennen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Titel'),
          onSubmitted: (v) => Navigator.of(dialogCtx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(null),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(ctrl.text),
              child: const Text('Speichern')),
        ],
      ),
    );
    if (neu != null && neu.trim().isNotEmpty) {
      await repo.rename(chat.id, neu);
    }
  }

  Future<void> _loeschenDialog(
      NormChat chat, NormChatHistoryRepository repo) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Chat löschen?'),
        content: Text('„${chat.titel}" dauerhaft entfernen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Abbrechen')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AwTokens.red),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('Löschen')),
        ],
      ),
    );
    if (ok == true) {
      await repo.delete(chat.id);
      if (_aktiveChatId == chat.id) _neuerChat();
    }
  }

  Future<void> _kopiereInRecherche(
      NormChat chat, NormChatHistoryRepository repo) async {
    final nachrichten = repo.ladeNachrichten(chat);
    if (nachrichten.isEmpty) return;

    // 1) Eindeutige Norm-Referenzen aus den Quellen ziehen — Norm-Stammdaten
    //    aus der DB nachladen, damit Titel + Ausgabe stabil sind (auch wenn
    //    die KI die Norm-Nummer in der Antwort verkürzt).
    final normenRepo = ref.read(normenRepositoryProvider);
    final referenzen = <_NormReferenz>[];
    final geseheneIds = <int>{};
    for (final n in nachrichten) {
      for (final q in n.quellen) {
        if (q.normId == null) continue;
        if (geseheneIds.add(q.normId!)) {
          final norm = await normenRepo.byId(q.normId!);
          if (norm != null) {
            referenzen.add(_NormReferenz(
              normId: norm.id,
              nummer: norm.nummer,
              titel: norm.titel,
              ausgabe: norm.ausgabe,
              beschreibung: norm.beschreibung,
              seiten: <int>{q.page},
            ));
          }
        } else {
          // weitere Seiten für eine bereits erfasste Norm
          referenzen
              .firstWhere((r) => r.normId == q.normId)
              .seiten
              .add(q.page);
        }
      }
    }

    // 2) Inhalt = lesbarer Verlauf mit besseren Quellenangaben
    final buf = StringBuffer();
    for (final n in nachrichten) {
      final rolle = n.rolle == 'user' ? 'Frage' : 'Antwort';
      buf.writeln('## $rolle');
      buf.writeln(n.text.trim());
      buf.writeln();
    }
    if (referenzen.isNotEmpty) {
      buf.writeln('## Quellen');
      for (final r in referenzen) {
        final ausg = r.ausgabe?.trim();
        final tit = r.titel?.trim();
        final teile = <String>[
          r.nummer,
          if (tit != null && tit.isNotEmpty) tit,
          if (ausg != null && ausg.isNotEmpty) 'Ausgabe $ausg',
          'S. ${(r.seiten.toList()..sort()).join(", ")}',
        ];
        buf.writeln('• ${teile.join(", ")}');
      }
    }

    // 3) Strukturierte Norm-Referenzen für späteres Übernehmen in die Akte
    final referenzJson = jsonEncode(referenzen
        .map((r) => {
              'normId': r.normId,
              'nummer': r.nummer,
              'titel': r.titel,
              'ausgabe': r.ausgabe,
              'seiten': r.seiten.toList()..sort(),
            })
        .toList());

    try {
      await ref.read(rechercheAblageRepositoryProvider).insert(
            titel: chat.titel,
            inhalt: buf.toString().trim(),
            quelle: 'Normen-Chat',
            referenzNormenJson:
                referenzen.isEmpty ? null : referenzJson,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Chat in Recherche-Ablage übernommen.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 260,
          child: _ChatSidebar(
            aktiveChatId: _aktiveChatId,
            onChatTap: _ladeChat,
            onNeuerChat: _neuerChat,
            onAktion: _chatAktion,
          ),
        ),
        VerticalDivider(width: 1, color: scheme.outlineVariant),
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: AwTokens.orange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              _aktiveChatId == null
                                  ? 'Neuer Normen-Chat'
                                  : 'Normen-Chat (gespeichert)',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(
                            'Antwortet aus der gesamten indexierten Normen-Bibliothek mit Quellenverweisen.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _historie.isEmpty
                    ? const _LeererZustand()
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _historie.length,
                        itemBuilder: (_, i) => _ChatEintrag(
                          nachricht: _historie[i],
                          onQuelleTap: _quelleOeffnen,
                        ),
                      ),
              ),
              if (_fehler != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  color: scheme.errorContainer,
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: scheme.error, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_fehler!,
                              style: TextStyle(color: scheme.error))),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _fehler = null),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _eingabeCtrl,
                        enabled: !_laedt,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Frage zur Normen-Bibliothek …',
                          isDense: true,
                        ),
                        onSubmitted: (_) => _senden(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _laedt ? null : _senden,
                      icon: _laedt
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send, size: 16),
                      label: const Text('Senden'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (widget.embedded) return body;
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 800),
        child: body,
      ),
    );
  }
}

class _ChatSidebar extends ConsumerWidget {
  const _ChatSidebar({
    required this.aktiveChatId,
    required this.onChatTap,
    required this.onNeuerChat,
    required this.onAktion,
  });
  final int? aktiveChatId;
  final void Function(NormChat) onChatTap;
  final VoidCallback onNeuerChat;
  final Future<void> Function(NormChat chat, String aktion) onAktion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(normChatHistoryListProvider);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            child: FilledButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Neuer Chat'),
              onPressed: onNeuerChat,
              style: FilledButton.styleFrom(
                backgroundColor: AwTokens.orange,
                minimumSize: const Size.fromHeight(40),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('Fehler: $e',
                          style: TextStyle(color: scheme.error)))),
              data: (list) {
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Hier erscheinen Deine gespeicherten Chats. Stelle eine Frage — der Verlauf wird automatisch gespeichert.',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  );
                }
                final df = DateFormat('dd.MM.yyyy HH:mm', 'de');
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final c = list[i];
                    final aktiv = c.id == aktiveChatId;
                    return _ChatSidebarItem(
                      titel: c.titel,
                      datum: df.format(c.updatedAt),
                      aktiv: aktiv,
                      onTap: () => onChatTap(c),
                      onAktion: (a) => onAktion(c, a),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatSidebarItem extends StatelessWidget {
  const _ChatSidebarItem({
    required this.titel,
    required this.datum,
    required this.aktiv,
    required this.onTap,
    required this.onAktion,
  });
  final String titel;
  final String datum;
  final bool aktiv;
  final VoidCallback onTap;
  final void Function(String) onAktion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: aktiv
            ? AwTokens.orangeSoft
            : Colors.transparent,
        child: Row(
          children: [
            Icon(Icons.forum_outlined,
                size: 16,
                color: aktiv ? AwTokens.orange : scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color:
                          aktiv ? AwTokens.orange : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(datum,
                      style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz,
                  size: 18,
                  color: scheme.onSurfaceVariant),
              tooltip: 'Aktionen',
              padding: EdgeInsets.zero,
              onSelected: onAktion,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'umbenennen',
                  child: Row(children: [
                    Icon(Icons.edit_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('Umbenennen'),
                  ]),
                ),
                PopupMenuItem(
                  value: 'kopieren_recherche',
                  child: Row(children: [
                    Icon(Icons.bookmark_add_outlined, size: 16),
                    SizedBox(width: 8),
                    Text('In Recherche-Ablage'),
                  ]),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'loeschen',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 16, color: AwTokens.red),
                    SizedBox(width: 8),
                    Text('Löschen', style: TextStyle(color: AwTokens.red)),
                  ]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LeererZustand extends StatelessWidget {
  const _LeererZustand();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined,
                size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Stelle eine Frage zu deinen Normen.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Die KI durchsucht die indexierten PDFs und antwortet mit den passenden Stellen.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatEintrag extends StatelessWidget {
  const _ChatEintrag({
    required this.nachricht,
    required this.onQuelleTap,
  });
  final NormChatNachricht nachricht;
  final void Function(NormChatQuelle) onQuelleTap;

  @override
  Widget build(BuildContext context) {
    final isUser = nachricht.rolle == 'user';
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            CircleAvatar(
              radius: 14,
              backgroundColor: AwTokens.orangeSoft,
              child: const Icon(Icons.auto_awesome,
                  size: 14, color: AwTokens.orange),
            ),
          if (!isUser) const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser
                        ? scheme.primaryContainer.withValues(alpha: 0.4)
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    nachricht.text,
                    style: const TextStyle(fontSize: 13.5, height: 1.45),
                  ),
                ),
                if (nachricht.quellen.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final q in nachricht.quellen)
                        ActionChip(
                          avatar: const Icon(Icons.menu_book_outlined,
                              size: 14),
                          label: Text(
                            '${q.nummer} · S. ${q.page}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          tooltip: q.snippet.length > 200
                              ? '${q.snippet.substring(0, 200)} …'
                              : q.snippet,
                          onPressed: () => onQuelleTap(q),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 10),
          if (isUser)
            CircleAvatar(
              radius: 14,
              backgroundColor: scheme.surfaceContainerHigh,
              child: Icon(Icons.person,
                  size: 14, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// Hilfsklasse: aggregierte Norm-Referenz aus einem Chat-Verlauf — eine
/// Norm kann mehrfach (auf verschiedenen Seiten) zitiert worden sein, wir
/// merken uns alle Seiten in einem Set.
class _NormReferenz {
  _NormReferenz({
    required this.normId,
    required this.nummer,
    required this.titel,
    required this.ausgabe,
    required this.beschreibung,
    required this.seiten,
  });
  final int normId;
  final String nummer;
  final String? titel;
  final String? ausgabe;
  final String? beschreibung;
  final Set<int> seiten;
}
