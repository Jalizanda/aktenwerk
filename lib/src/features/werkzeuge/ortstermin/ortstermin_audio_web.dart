import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class _Recorder {
  final web.MediaRecorder mr;
  final web.MediaStream stream;
  final List<web.Blob> chunks = [];
  final Completer<(Uint8List, String)?> done = Completer();
  Timer? ticker;
  Duration elapsed = Duration.zero;

  _Recorder(this.mr, this.stream);
}

/// Konvertiert den aufgenommenen Blob zu Dart-Bytes (läuft außerhalb des
/// JS-Event-Handlers, da async-Callbacks via toJS nicht erlaubt sind).
void _finalize(_Recorder rec, web.MediaRecorder mr, web.MediaStream stream) {
  for (final t in stream.getTracks().toDart) {
    t.stop();
  }
  if (rec.chunks.isEmpty) {
    if (!rec.done.isCompleted) rec.done.complete(null);
    return;
  }
  final mime = mr.mimeType.isNotEmpty ? mr.mimeType : 'audio/webm';
  final blobParts = rec.chunks.map((b) => b as JSAny).toList().toJS;
  final blob = web.Blob(blobParts, web.BlobPropertyBag(type: mime));

  web.Response(blob).arrayBuffer().toDart.then((ab) {
    final bytes = JSUint8Array(ab).toDart;
    if (!rec.done.isCompleted) rec.done.complete((bytes, mime));
  }).catchError((Object e) {
    if (!rec.done.isCompleted) rec.done.completeError(e);
  });
}

Future<Object> ortsterminAudioStart(void Function(Duration) onTick) async {
  final stream = await web.window.navigator.mediaDevices
      .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
      .toDart;

  final mr = web.MediaRecorder(stream);
  final rec = _Recorder(mr, stream);

  mr.addEventListener(
    'dataavailable',
    ((web.BlobEvent e) {
      if (e.data.size > 0) rec.chunks.add(e.data);
    }).toJS,
  );

  mr.addEventListener(
    'stop',
    ((web.Event _) {
      _finalize(rec, mr, stream);
    }).toJS,
  );

  rec.ticker = Timer.periodic(const Duration(seconds: 1), (_) {
    rec.elapsed += const Duration(seconds: 1);
    onTick(rec.elapsed);
  });

  mr.start(100);
  return rec;
}

void ortsterminAudioPause(Object handle) {
  final rec = handle as _Recorder;
  if (rec.mr.state == 'recording') rec.mr.pause();
}

void ortsterminAudioResume(Object handle) {
  final rec = handle as _Recorder;
  if (rec.mr.state == 'paused') rec.mr.resume();
}

Future<(Uint8List, String)?> ortsterminAudioStop(Object handle) async {
  final rec = handle as _Recorder;
  rec.ticker?.cancel();
  if (rec.mr.state != 'inactive') rec.mr.stop();
  return rec.done.future.timeout(
    const Duration(seconds: 15),
    onTimeout: () => null,
  );
}
