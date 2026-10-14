import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ai/norm_rag_service.dart';
import '../../../core/theme/aw_tokens.dart';
import '../../../core/web/web_compat.dart' as web_compat;
import '../../../data/database/app_database.dart';
import '../recherche_ablage/recherche_ablage_repository.dart';
import 'norm_chat_history_repository.dart';
import 'normen_repository.dart';

/// RAG-basiertes Chat-UI mit links liegender Verlaufs-Sidebar (wie ChatGPT).
class NormenRagChatDialog extends ConsumerStatefulWidget {
  const NormenRagChatDialog({
    super.key,
    this.embedded = false,
    this.initialChatId,
  });

  final bool embedded;
  final int? initialChatId;

  @override
  ConsumerState<NormenRagChatDialog> createState() =>
      _NormenRagChatDialogState();
}

class _NormenRagChatDialogState extends ConsumerState<NormenRagChatDialog> {
  final _eingabeCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  final List<NormChatNachricht> _historie = [];
  int? _aktiveChatId;
  bool _laedt = false;
  bool _fastMode = true;
  String? _fehler;
  final bool _autoSpeichern = true;
  double _webKeyboardInset = 0.0;
  StreamSubscription<double>? _keyboardSub;

  @override
  void initState() {
    super.initState();
    _keyboardSub = web_compat.visualViewportKeyboardStream.listen((inset) {
      if (mounted && (inset - _webKeyboardInset).abs() > 1.0) {
        setState(() {
          _webKeyboardInset = inset;
        });
        if (_focusNode.hasFocus) {
          _zumEnde();
        }
      }
    });

    _focusNode.addListener(() {
      _handleFocusChange(_focusNode.hasFocus);
    });

    final startId = widget.initialChatId ??
        int.tryParse(Uri.base.queryParameters['id'] ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final repo = ref.read(normChatHistoryRepositoryProvider);
      if (startId != null) {
        final chat = await repo.byId(startId);
        if (chat != null && mounted) {
          _ladeChat(chat);
          return;
        }
      }
      // Automatisch den neuesten Verlauf laden, falls vorhanden
      final chats = await repo.watchAll().first;
      if (chats.isNotEmpty && _aktiveChatId == null && _historie.isEmpty && mounted) {
        _ladeChat(chats.first);
      }
    });
  }

  void _handleFocusChange(bool hasFocus) {
    _updateKeyboardInset();
    if (hasFocus) {
      web_compat.resetWindowScroll();
    }
    // Safari auf iPadOS/iOS schiebt die Tastatur mit einer Animation ein (ca. 300-500ms).
    for (final ms in [50, 150, 250, 400, 600]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (!mounted) return;
        _updateKeyboardInset();
        if (hasFocus) {
          web_compat.resetWindowScroll();
          _zumEnde();
        }
      });
    }
  }

  void _updateKeyboardInset() {
    final inset = web_compat.visualViewportKeyboardInset;
    if ((inset - _webKeyboardInset).abs() > 1.0) {
      if (mounted) {
        setState(() {
          _webKeyboardInset = inset;
        });
      }
    }
  }

  @override
  void dispose() {
    _keyboardSub?.cancel();
    _focusNode.dispose();
    _eingabeCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  final List<NormChatAnhang> _entwurfAnhaenge = [];

  Future<void> _fotoAufnehmen() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      final b64 = base64Encode(bytes);
      final mime = photo.mimeType ?? 'image/jpeg';
      setState(() {
        _entwurfAnhaenge.add(NormChatAnhang(
          dateiname: photo.name.isNotEmpty ? photo.name : 'Foto.jpg',
          mimeType: mime,
          base64Data: b64,
        ));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kamera konnte nicht geöffnet werden: $e')),
        );
      }
    }
  }

  Future<void> _dokumentWaehlen() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'txt'],
        allowMultiple: true,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final neueAnhaenge = <NormChatAnhang>[];
      for (final file in res.files) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        final ext = file.extension?.toLowerCase() ?? '';
        String mime = 'application/octet-stream';
        if (ext == 'pdf') mime = 'application/pdf';
        else if (ext == 'jpg' || ext == 'jpeg') mime = 'image/jpeg';
        else if (ext == 'png') mime = 'image/png';
        else if (ext == 'webp') mime = 'image/webp';
        else if (ext == 'txt') mime = 'text/plain';

        neueAnhaenge.add(NormChatAnhang(
          dateiname: file.name,
          mimeType: mime,
          base64Data: base64Encode(bytes),
        ));
      }
      if (neueAnhaenge.isNotEmpty && mounted) {
        setState(() {
          _entwurfAnhaenge.addAll(neueAnhaenge);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler bei der Dateiauswahl: $e')),
        );
      }
    }
  }

  Future<void> _senden() async {
    final text = _eingabeCtrl.text.trim();
    if ((text.isEmpty && _entwurfAnhaenge.isEmpty) || _laedt) return;
    final anhaenge = List<NormChatAnhang>.from(_entwurfAnhaenge);
    _eingabeCtrl.clear();
    setState(() {
      _entwurfAnhaenge.clear();
      _laedt = true;
      _fehler = null;
      _historie.add(NormChatNachricht(
        rolle: 'user',
        text: text.isEmpty
            ? (anhaenge.length == 1
                ? 'Anhang: ${anhaenge.first.dateiname}'
                : '${anhaenge.length} Anhänge gesendet')
            : text,
        anhaenge: anhaenge,
        zeit: DateTime.now(),
      ));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _zumEnde());
    try {
      final service = ref.read(normRagServiceProvider);
      final me = _historie.lastWhere((m) => m.rolle == 'user');
      final frageText = text.isEmpty
          ? 'Analysiere das angehängte Foto / Dokument.'
          : text;
      final antwort = await service.frage(
        frage: frageText,
        historie: _historie.take(_historie.length - 1).toList(),
        anhaenge: me.anhaenge,
        fastMode: _fastMode,
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
      case 'direktlink':
        await _kopiereDirektlink(chat);
        break;
    }
  }

  Future<void> _kopiereDirektlink(NormChat chat) async {
    final url = 'https://chat.aktenwerk.app/#/chat?id=${chat.id}';
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Direktlink kopiert: $url')),
    );
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, ctrl.text),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    ctrl.dispose();
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
        content: Text('Möchtest Du „${chat.titel}“ wirklich unwiderruflich löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogCtx).colorScheme.error),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Löschen'),
          ),
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
          referenzen
              .firstWhere((r) => r.normId == q.normId)
              .seiten
              .add(q.page);
        }
      }
    }

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
    final width = MediaQuery.sizeOf(context).width;
    final isMobileOrTablet = width < 1100 || web_compat.isIOSorIPad;

    final chatsAsync = ref.watch(normChatHistoryListProvider);
    final chats = chatsAsync.valueOrNull ?? const <NormChat>[];

    NormChat? aktiverChat;
    if (_aktiveChatId != null) {
      aktiverChat = chats.where((c) => c.id == _aktiveChatId).firstOrNull;
    }
    final aktiverTitel = aktiverChat?.titel ?? (_aktiveChatId == null ? 'Neuer Chat' : 'Normen-Chat');

    final mainColumn = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(
            children: [
              // 1. Oben Links: Dropdown zur Chat-Auswahl
              _buildMobileChatDropdown(context, scheme, chats, aktiverTitel),
              const SizedBox(width: 6),
              // 2. Daneben: Button um einen neuen Chat anzulegen
              Tooltip(
                message: 'Neuen Chat anlegen',
                child: InkWell(
                  onTap: _neuerChat,
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: AwTokens.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: AwTokens.orange.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.add, size: 16, color: AwTokens.orange),
                        SizedBox(width: 3),
                        Text(
                          'Neu',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AwTokens.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // 3. FAST-Modus Schieberegler / Switch (kompakt)
              Tooltip(
                message: _fastMode
                    ? 'FAST-Modus AKTIV: Sehr schnelle, prägnante Antworten.'
                    : 'Standard-Modus: Ausführliche Antworten.',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: _fastMode ? AwTokens.orange.withValues(alpha: 0.15) : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _fastMode ? AwTokens.orange : scheme.outlineVariant,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bolt,
                        size: 14,
                        color: _fastMode ? AwTokens.orange : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 1),
                      Text(
                        'FAST',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _fastMode ? AwTokens.orange : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 2),
                      SizedBox(
                        height: 20,
                        width: 32,
                        child: Transform.scale(
                          scale: 0.72,
                          child: Switch(
                            value: _fastMode,
                            onChanged: (val) => setState(() => _fastMode = val),
                            activeThumbColor: AwTokens.orange,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 4. Link zur Normendatenbank (kompakt)
              Tooltip(
                message: 'Normen-Bibliothek in neuem Tab öffnen',
                child: IconButton(
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(5),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.library_books_outlined, size: 18),
                  onPressed: () async {
                    final uri = Uri.parse('https://app.aktenwerk.app/#/normen');
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
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
                Icon(Icons.error_outline, color: scheme.error, size: 18),
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
        _buildEingabeLeiste(scheme),
      ],
    );

    final body = isMobileOrTablet
        // Mobile & Tablet: nur Chat, keine Sidebar
        ? mainColumn
        // Desktop: Sidebar + Chat
        : Row(

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
                    const SizedBox(width: 12),
                    // FAST-Modus Schieberegler / Switch
                    Tooltip(
                      message: _fastMode
                          ? 'FAST-Modus AKTIV: Sehr schnelle, prägnante Antworten. Bei Multiple-Choice nur Lösungsnummer + 1 Satz Begründung.'
                          : 'Standard-Modus: Ausführliche, detaillierte Antworten.',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _fastMode ? AwTokens.orange.withValues(alpha: 0.15) : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _fastMode ? AwTokens.orange : scheme.outlineVariant,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bolt,
                              size: 18,
                              color: _fastMode ? AwTokens.orange : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'FAST',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _fastMode ? AwTokens.orange : scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Switch(
                              value: _fastMode,
                              onChanged: (val) => setState(() => _fastMode = val),
                              activeThumbColor: AwTokens.orange,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ],
                        ),
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
              _buildEingabeLeiste(scheme),
            ],
          ),
        ),
      ],
    ); // end desktop Row

    if (widget.embedded) return body;
    final isSmallScreen = MediaQuery.sizeOf(context).width < 600;
    return Dialog(
      insetPadding: isSmallScreen ? const EdgeInsets.all(8) : const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 800),
        child: body,
      ),
    );
  }

  Widget _buildMobileChatDropdown(
    BuildContext context,
    ColorScheme scheme,
    List<NormChat> chats,
    String aktiverTitel,
  ) {
    final df = DateFormat('dd.MM. HH:mm', 'de');
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxTitleWidth = screenWidth > 600 ? 280.0 : 125.0;
    return PopupMenuButton<dynamic>(
      tooltip: 'Chats auswählen',
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      elevation: 6,
      color: scheme.surfaceContainerHighest,
      constraints: const BoxConstraints(maxHeight: 460, minWidth: 260, maxWidth: 320),
      onSelected: (selected) {
        if (selected == null) {
          _neuerChat();
        } else if (selected == '__manage__') {
          _zeigeVerlaufModal(context);
        } else if (selected is NormChat) {
          _ladeChat(selected);
        }
      },
      itemBuilder: (context) {
        return [
          PopupMenuItem<dynamic>(
            value: null,
            height: 40,
            child: Row(
              children: [
                const Icon(Icons.add_circle_outline, size: 16, color: AwTokens.orange),
                const SizedBox(width: 8),
                Text(
                  'Neuer Chat',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: _aktiveChatId == null ? FontWeight.bold : FontWeight.w600,
                    color: _aktiveChatId == null ? AwTokens.orange : scheme.onSurface,
                  ),
                ),
                if (_aktiveChatId == null) ...[
                  const Spacer(),
                  const Icon(Icons.check, size: 16, color: AwTokens.orange),
                ],
              ],
            ),
          ),
          if (chats.isNotEmpty) const PopupMenuDivider(height: 1),
          ...chats.map((c) {
            final aktiv = c.id == _aktiveChatId;
            return PopupMenuItem<dynamic>(
              value: c,
              height: 48,
              child: Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 15,
                    color: aktiv ? AwTokens.orange : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.titel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: aktiv ? FontWeight.bold : FontWeight.normal,
                            color: aktiv ? AwTokens.orange : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          df.format(c.updatedAt),
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (aktiv) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.check, size: 16, color: AwTokens.orange),
                  ],
                ],
              ),
            );
          }),
          if (chats.isNotEmpty) ...[
            const PopupMenuDivider(height: 1),
            PopupMenuItem<dynamic>(
              value: '__manage__',
              height: 38,
              child: Row(
                children: [
                  Icon(Icons.tune, size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    'Verlauf verwalten...',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ];
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline, size: 14, color: AwTokens.orange),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxTitleWidth),
              child: Text(
                aktiverTitel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _zeigeVerlaufModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.8,
        child: _ChatSidebar(
          aktiveChatId: _aktiveChatId,
          onChatTap: (c) {
            Navigator.pop(ctx);
            _ladeChat(c);
          },
          onNeuerChat: () {
            Navigator.pop(ctx);
            _neuerChat();
          },
          onAktion: (c, a) async {
            await _chatAktion(c, a);
            if (ctx.mounted && Navigator.canPop(ctx)) {
              Navigator.pop(ctx);
            }
          },
        ),
      ),
    );
  }

  Widget _buildEingabeLeiste(ColorScheme scheme) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final effectiveBottom = math.max(bottomInset, _webKeyboardInset);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final extraBottom = math.max(safeBottom, effectiveBottom);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        12 + (widget.embedded ? extraBottom : (effectiveBottom > 0 ? effectiveBottom : 0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_entwurfAnhaenge.isNotEmpty) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < _entwurfAnhaenge.length; i++) ...[
                    Builder(builder: (context) {
                      final a = _entwurfAnhaenge[i];
                      return Container(
                        margin: const EdgeInsets.only(right: 8, bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              a.istBild
                                  ? Icons.image_outlined
                                  : (a.istPdf
                                      ? Icons.picture_as_pdf
                                      : Icons.insert_drive_file),
                              size: 16,
                              color: a.istBild ? AwTokens.orange : scheme.primary,
                            ),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                a.dateiname,
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => setState(() => _entwurfAnhaenge.removeAt(i)),
                              child: const Padding(
                                padding: EdgeInsets.all(2.0),
                                child: Icon(Icons.close, size: 14, color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
          Builder(builder: (context) {
            final isNarrow = MediaQuery.sizeOf(context).width < 500;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Tooltip(
                  message: 'Foto direkt aufnehmen (Kamera)',
                  child: IconButton(
                    padding: isNarrow ? const EdgeInsets.all(6) : const EdgeInsets.all(8),
                    constraints: isNarrow ? const BoxConstraints() : null,
                    icon: const Icon(Icons.photo_camera_outlined),
                    onPressed: _laedt ? null : _fotoAufnehmen,
                    color: scheme.primary,
                  ),
                ),
                Tooltip(
                  message: 'Foto oder Dokument (PDF, Bild, Text) hochladen',
                  child: IconButton(
                    padding: isNarrow ? const EdgeInsets.all(6) : const EdgeInsets.all(8),
                    constraints: isNarrow ? const BoxConstraints() : null,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    onPressed: _laedt ? null : _dokumentWaehlen,
                    color: scheme.primary,
                  ),
                ),
                SizedBox(width: isNarrow ? 2 : 4),
                Expanded(
                  child: TextField(
                    controller: _eingabeCtrl,
                    focusNode: _focusNode,
                    enabled: !_laedt,
                    minLines: 1,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.send,
                    autocorrect: true,
                    enableSuggestions: true,
                    scrollPadding: const EdgeInsets.all(80),
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 14,
                    ),
                    cursorColor: scheme.primary,
                    decoration: InputDecoration(
                      hintText: isNarrow
                          ? 'Frage oder Foto/Dokument …'
                          : 'Frage zur Normen-Bibliothek oder Foto/Dokument …',
                      isDense: true,
                      contentPadding: isNarrow
                          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                          : null,
                    ),
                    onChanged: (_) {
                      if (_webKeyboardInset == 0.0) {
                        _updateKeyboardInset();
                      }
                    },
                    onSubmitted: (_) => _senden(),
                  ),
                ),
                SizedBox(width: isNarrow ? 4 : 8),
                if (isNarrow)
                  IconButton.filled(

                    onPressed: _laedt ? null : _senden,
                    icon: _laedt
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send, size: 18),
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.primary,
                    ),
                  )
                else
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
            );
          }),
        ],
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
                PopupMenuItem(
                  value: 'direktlink',
                  child: Row(children: [
                    Icon(Icons.link, size: 16),
                    SizedBox(width: 8),
                    Text('Direktlink kopieren'),
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
                if (nachricht.anhaenge.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final a in nachricht.anhaenge)
                          if (a.istBild && a.base64Data.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                showDialog<void>(
                                  context: context,
                                  builder: (_) => Dialog(
                                    insetPadding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AppBar(
                                          title: Text(a.dateiname, style: const TextStyle(fontSize: 14)),
                                          automaticallyImplyLeading: false,
                                          actions: [
                                            IconButton(
                                              icon: const Icon(Icons.close),
                                              onPressed: () => Navigator.of(context).pop(),
                                            ),
                                          ],
                                        ),
                                        Flexible(
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Image.memory(
                                              base64Decode(a.base64Data),
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: scheme.outlineVariant),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Image.memory(
                                    base64Decode(a.base64Data),
                                    width: 140,
                                    height: 100,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                                  ),
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: scheme.outlineVariant),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    a.istPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                                    size: 18,
                                    color: a.istPdf ? Colors.red : scheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 160),
                                    child: Text(
                                      a.dateiname,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
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
