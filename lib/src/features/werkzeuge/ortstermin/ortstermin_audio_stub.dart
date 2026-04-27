import 'dart:typed_data';

Future<Object> ortsterminAudioStart(void Function(Duration) onTick) async =>
    throw UnimplementedError(
        'Audio-Aufnahme erfordert einen modernen Browser mit Mikrofon-Zugriff.');

void ortsterminAudioPause(Object handle) {}
void ortsterminAudioResume(Object handle) {}
Future<(Uint8List, String)?> ortsterminAudioStop(Object handle) async => null;
