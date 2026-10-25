import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fushi_engine/media/video/video_subtitle_source.dart';

import '../helpers/source_guard.dart';

void main() {
  test('ASS downloaded for resume requires its original extension', () async {
    final Directory temp = await Directory.systemTemp.createTemp('sub-resume-');
    addTearDown(() => temp.delete(recursive: true));
    const String content =
        '[Script Info]\n'
        'ScriptType: v4.00+\n'
        '[Events]\n'
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
        'Dialogue: 0,0:10:00.00,0:10:03.00,Default,,0,0,0,,副字幕\n';
    final File original = await File(
      '${temp.path}/track.ass',
    ).writeAsString(content);
    final File mislabeled = await File(
      '${temp.path}/track.srt',
    ).writeAsString(content);
    final SubtitleCueLoadResult restored = await loadExternalSubtitleCueResult(
      original.path,
      'resume',
    );
    final SubtitleCueLoadResult oldRestore =
        await loadExternalSubtitleCueResult(mislabeled.path, 'resume');
    expect(restored.cues.single.text, '副字幕');
    expect(restored.cues.single.startMs, 600000);
    expect(oldRestore.cues, isEmpty);
  });

  test('remote secondary restore retains the selected track format', () {
    final String source = File(
      'lib/src/pages/implementations/video_fushi/subtitle.part.dart',
    ).readAsStringSync();
    final String body = methodBody(
      source,
      'Future<void> _restoreRemoteSecondarySubtitle(',
    );
    expect(
      containsIdentifierCall(body, '_remoteEmbeddedTrackByStreamIndex'),
      isTrue,
    );
    expect(
      containsCodeLine(
        body,
        "track?.fileName ?? 'embedded_\$streamIndex.srt',",
      ),
      isTrue,
      reason:
          'The server downloads original ASS/VTT bytes; restore must use '
          'the same extension as manual selection to choose the parser.',
    );
  });
}
