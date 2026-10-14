import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../../core/ai/ki_modelle.dart';
import '../../system/einstellungen/einstellungen_repository.dart';
import 'beweisfragen.dart';

class BeweisfragenChatDialog extends ConsumerStatefulWidget {
  const BeweisfragenChatDialog({super.key, required this.fragen});
  final List<Beweisfrage> fragen;

  @override
  ConsumerState<BeweisfragenChatDialog> createState() =>
      _BeweisfragenChatDialogState();
}

class _BeweisfragenChatDialogState extends ConsumerState<BeweisfragenChatDialog> {
  final _eingabeCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  
  ChatSession? _chat;
  final List<Map<String, dynamic>> _historie = [];
  bool _laedt = false;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    setState(() => _laedt = true);
    try {
      final repo = ref.read(einstellungenRepositoryProvider);
      final sachgebiet = await repo.getOr(SettingsKeys.svSachgebiet, 'Allgemein');
      final modellId = await getKiModell(repo, KiAufgabe.juristisch);

      final model = getVertexGenerativeModel(
        modelId: modellId,
        systemInstruction: Content.system(
          'Du bist ein Assistent für Gerichtssachverständige. Dein Sachgebiet ist: "$sachgebiet".\n'
          'Du diskutierst mit dem Sachverständigen über die folgenden Beweisfragen:\n' +
          widget.fragen.map((f) => 'Frage ${f.nr}: ${f.frage}\nEinschätzung: ${f.einschaetzung}').join('\n') +
          '\n\nHilf dem Sachverständigen dabei zu beurteilen, ob die Fragen zulässig sind, '
          'ob sie rechtliche statt tatsächliche Würdigungen verlangen, oder ob sie '
          'außerhalb seines Fachgebiets liegen. Formuliere bei Bedarf Nachfragen an das Gericht '
          'oder schlage Umformulierungen vor.'
        ),
      );
      
      _chat = model.startChat();
      
      // Initiale KI-Nachricht
      _historie.add({
        'rolle': 'model',
        'inhalt': 'Hallo! Ich habe mir die Beweisfragen und deren erste Einschätzung angesehen. '
                  'Hast du Fragen dazu, oder möchtest du Nachfragen an das Gericht formulieren?'
      });
      
    } catch (e) {
      _fehler = e.toString();
    } finally {
      if (mounted) setState(() => _laedt = false);
    }
  }

  @override
  void dispose() {
    _eingabeCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _senden() async {
    final text = _eingabeCtrl.text.trim();
    if (text.isEmpty || _laedt || _chat == null) return;
    
    setState(() {
      _laedt = true;
      _fehler = null;
      _historie.add({'rolle': 'user', 'inhalt': text});
    });
    _eingabeCtrl.clear();
    
    WidgetsBinding.instance.addPostFrameCallback((_) => _zumEnde());
    
    try {
      final res = await _chat!.sendMessage(Content.text(text));
      final ans = res.text ?? '(Keine Antwort erhalten)';
      if (mounted) {
        setState(() {
          _historie.add({'rolle': 'model', 'inhalt': ans});
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fehler = e.toString();
          _eingabeCtrl.text = text;
          if (_historie.isNotEmpty) _historie.removeLast();
        });
      }
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
    final scheme = Theme.of(context).colorScheme;
    
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(scheme),
            const Divider(height: 1),
            Expanded(
              child: _buildVerlauf(scheme),
            ),
            if (_fehler != null) _buildFehler(scheme),
            if (_laedt) _buildLadeIndikator(scheme),
            const Divider(height: 1),
            _buildEingabe(scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Icon(Icons.chat_bubble_outline, color: scheme.primary, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Diskussion der Beweisfragen',
                    style: Theme.of(context).textTheme.titleLarge),
                Text(
                  '${widget.fragen.length} Beweisfragen im Kontext',
                  style: TextStyle(
                      fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildVerlauf(ColorScheme scheme) {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(16),
      itemCount: _historie.length,
      itemBuilder: (_, i) => _buildNachricht(_historie[i], scheme),
    );
  }

  Widget _buildNachricht(Map<String, dynamic> n, ColorScheme scheme) {
    final istUser = n['rolle'] == 'user';
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
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: istUser
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                n['inhalt']?.toString() ?? '',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: istUser ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
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
          if (_chat == null)
            TextButton(
              onPressed: () {
                setState(() => _fehler = null);
                _initChat();
              },
              style: TextButton.styleFrom(
                  foregroundColor: scheme.onErrorContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Erneut versuchen'),
            )
          else
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
          Text(_chat == null ? 'Chat wird initialisiert …' : 'KI antwortet …',
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
              enabled: !_laedt && _chat != null,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Nachricht …',
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
            onPressed: (_laedt || _chat == null) ? null : _senden,
          ),
        ],
      ),
    );
  }
}
