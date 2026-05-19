import 'dart:io';

/// Automated Release Documentation Agent
/// 
/// Dieses Skript agiert als autonomer Agent für das Release-Management.
/// Es liest die letzten Git-Commits seit dem letzten Tag aus und fügt diese 
/// sinnvoll gruppiert in die CHANGELOG.md ein.
/// 
/// Aufruf z. B. als Git-Hook (post-commit oder pre-push) oder manuell 
/// vor dem Release.
void main(List<String> args) async {
  print('🤖 Release Agent gestartet...');
  
  final changelogFile = File('CHANGELOG.md');
  if (!await changelogFile.exists()) {
    print('Fehler: CHANGELOG.md nicht gefunden.');
    exit(1);
  }

  // Hole Commits der letzten 24 Stunden (oder seit letztem Tag)
  final result = await Process.run('git', ['log', '--since="24 hours ago"', '--pretty=format:%s', '--no-merges']);
  if (result.exitCode != 0) {
    print('Git Log konnte nicht gelesen werden: ${result.stderr}');
    exit(1);
  }

  final commits = (result.stdout as String).split('\n').where((s) => s.trim().isNotEmpty).toList();
  if (commits.isEmpty) {
    print('🤖 Keine neuen Commits gefunden. Nichts zu tun.');
    return;
  }

  final today = DateTime.now();
  final dateString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  
  // Lese Inhalt und suche nach der letzten Version
  String content = await changelogFile.readAsString();
  
  // Wenn heute bereits ein Release eingetragen wurde, hängen wir es nicht nochmal als neuen Block an.
  // Einfache Prüfung für den Agenten:
  if (content.contains('## [Unreleased] - $dateString')) {
    print('🤖 Heute wurde bereits dokumentiert. Überspringe autom. Ergänzung.');
    return;
  }

  print('🤖 Analysiere ${commits.length} neue Commits...');

  final additions = <String>[];
  final fixes = <String>[];
  final others = <String>[];

  for (final c in commits) {
    final lower = c.toLowerCase();
    if (lower.startsWith('feat') || lower.startsWith('add')) {
      additions.add('- $c');
    } else if (lower.startsWith('fix') || lower.startsWith('bug')) {
      fixes.add('- $c');
    } else {
      others.add('- $c');
    }
  }

  final buffer = StringBuffer();
  buffer.writeln('## [Unreleased] - $dateString');
  if (additions.isNotEmpty) {
    buffer.writeln('### Hinzugefügt');
    additions.forEach(buffer.writeln);
  }
  if (fixes.isNotEmpty) {
    buffer.writeln('### Behoben');
    fixes.forEach(buffer.writeln);
  }
  if (others.isNotEmpty) {
    buffer.writeln('### Geändert / Sonstiges');
    others.forEach(buffer.writeln);
  }
  buffer.writeln();

  // Einfügen nach dem Header (Zeile mit "## [")
  final lines = content.split('\n');
  int insertIndex = lines.indexWhere((l) => l.startsWith('## ['));
  if (insertIndex == -1) {
    insertIndex = lines.length;
  }

  lines.insert(insertIndex, buffer.toString());
  
  await changelogFile.writeAsString(lines.join('\n'));
  print('🤖 CHANGELOG.md wurde erfolgreich um die neuesten Änderungen ergänzt.');
}
