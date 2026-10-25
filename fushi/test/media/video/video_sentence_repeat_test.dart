import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fushi/src/media/video/video_player_controller.dart';
import 'package:fushi_audio/fushi_audio.dart';

AudioCue _cue(int start, int end) => AudioCue()
  ..bookKey = 'video'
  ..chapterHref = 'video://default'
  ..sentenceIndex = start
  ..textFragmentId = ''
  ..text = 'sentence'
  ..startMs = start
  ..endMs = end
  ..audioFileIndex = 0;

void main() {
  late VideoPlayerController controller;
  late List<int> seeks;
  late int plays;

  setUp(() {
    controller = VideoPlayerController();
    seeks = <int>[];
    plays = 0;
    controller.setCues(<AudioCue>[_cue(1000, 2000), _cue(3000, 4000)]);
    controller.applyExternalPlaybackState(positionMs: 1500, playing: true);
  });
  tearDown(() => controller.dispose());

  Future<bool> toggle() => controller.toggleSentenceRepeat(
    seek: (int ms) async => seeks.add(ms),
    play: () async => plays++,
  );

  Future<void> tick(int ms, {bool playing = true}) async {
    controller.applyExternalPlaybackState(positionMs: ms, playing: playing);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'locks the same sentence across multiple loops until toggled off',
    () async {
      expect(await toggle(), isTrue);
      expect(plays, 1);
      expect(seeks, <int>[1000]);
      await tick(1000);
      await tick(2000);
      expect(seeks, <int>[1000, 1000]);
      await tick(1000);
      await tick(2125);
      expect(seeks, <int>[1000, 1000, 1000]);
      expect(await toggle(), isFalse);
      await tick(1000);
      await tick(3500);
      expect(controller.currentCueIndex, 1);
      expect(seeks, hasLength(3));
      expect(plays, 1, reason: 'disabling does not pause or restart playback');
    },
  );

  test('paused playback does not seek at the sentence end', () async {
    await toggle();
    await tick(1000);
    await tick(2200, playing: false);
    expect(seeks, <int>[1000]);
    expect(controller.isRepeatingSentence, isTrue);
  });

  test('uses subtitle delay for both start and end', () async {
    controller.setDelayMs(500);
    await tick(1800);
    await toggle();
    expect(seeks, <int>[1500]);
    await tick(1500);
    await tick(2400);
    expect(seeks, hasLength(1));
    await tick(2500);
    expect(seeks, <int>[1500, 1500]);
  });

  test(
    'stale ticks while seek is pending cannot issue duplicate seeks',
    () async {
      final Completer<void> pending = Completer<void>();
      final Future<bool> started = controller.toggleSentenceRepeat(
        seek: (int ms) {
          seeks.add(ms);
          return pending.future;
        },
        play: () async => plays++,
      );
      await tick(2100);
      await tick(2200);
      expect(seeks, <int>[1000]);
      controller.stopSentenceRepeat();
      pending.complete();
      expect(await started, isFalse);
      expect(
        plays,
        0,
        reason: 'a disabled request cannot start playback later',
      );
    },
  );

  test('changing subtitles cancels repeat and a pending start', () async {
    final Completer<void> pending = Completer<void>();
    final Future<bool> started = controller.toggleSentenceRepeat(
      seek: (int ms) => pending.future,
      play: () async => plays++,
    );
    controller.setCues(<AudioCue>[_cue(5000, 6000)]);
    pending.complete();
    expect(await started, isFalse);
    expect(controller.isRepeatingSentence, isFalse);
    expect(plays, 0);
  });

  test('no current sentence is a safe no-op', () async {
    await tick(2500);
    expect(await toggle(), isFalse);
    expect(seeks, isEmpty);
    expect(plays, 0);
  });

  test(
    'same-track live subtitle additions preserve the locked sentence',
    () async {
      await toggle();
      controller.setCues(<AudioCue>[
        _cue(1000, 2000),
        _cue(3000, 4000),
        _cue(5000, 6000),
      ], preserveSentenceRepeat: true);
      expect(controller.isRepeatingSentence, isTrue);
      await tick(1000);
      await tick(2100);
      expect(seeks, <int>[1000, 1000]);
    },
  );

  test('EOF restarts the sentence instead of completing the episode', () async {
    await toggle();
    await tick(1000);
    controller.debugHandleCompletedForTesting(true);
    await Future<void>.delayed(Duration.zero);
    expect(seeks, <int>[1000, 1000]);
    expect(plays, 2);
    expect(controller.isRepeatingSentence, isTrue);
  });

  test('a pause during the initial seek prevents delayed auto-play', () async {
    final Completer<void> pending = Completer<void>();
    final Future<bool> started = controller.toggleSentenceRepeat(
      seek: (int ms) => pending.future,
      play: () async => plays++,
    );
    await controller.pause();
    pending.complete();
    await started;
    expect(plays, 0);
  });

  test('EOF during an in-flight loop seek resumes after that seek', () async {
    final Completer<void> pending = Completer<void>();
    await controller.toggleSentenceRepeat(
      seek: (int ms) {
        seeks.add(ms);
        return seeks.length == 1 ? Future<void>.value() : pending.future;
      },
      play: () async => plays++,
    );
    await tick(1000);
    await tick(2000);
    controller.debugHandleCompletedForTesting(true);
    expect(seeks, <int>[1000, 1000]);
    pending.complete();
    await Future<void>.delayed(Duration.zero);
    expect(plays, 2);
  });
}
