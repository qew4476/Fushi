// Opt-in real-file regression, always using the runner's isolated database.
// run_windows_itest.ps1 -Visible -DartDefine FUSHI_PROBE_VIDEO=<mkv>,
// FUSHI_PROBE_PRIMARY=<srt>,FUSHI_PROBE_SECONDARY=10,FUSHI_PROBE_RESUME_MS=1210083
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fushi/src/media/video/video_player_controller.dart';
import 'package:fushi/src/media/video/video_subtitle_overlay.dart';
import 'package:fushi/src/models/app_model.dart';
import 'package:fushi/src/pages/implementations/video_fushi_page.dart';
import 'package:fushi_core/fushi_core.dart' show VideoBooksCompanion;
import 'package:fushi_engine/media/video/video_book_repository.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' show MaterialPageRoute;

import 'helpers/library_fixture.dart' show readyAppModel;
import 'helpers/observe_capture.dart';
import 'support/test_app_launcher.dart';
import 'test_helpers.dart';

const String _root = String.fromEnvironment('FUSHI_TEST_ROOT');
const String _video = String.fromEnvironment('FUSHI_PROBE_VIDEO');
const String _primary = String.fromEnvironment('FUSHI_PROBE_PRIMARY');
const int _secondary = int.fromEnvironment(
  'FUSHI_PROBE_SECONDARY',
  defaultValue: 0,
);
const int _resumeMs = int.fromEnvironment(
  'FUSHI_PROBE_RESUME_MS',
  defaultValue: 45000,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'local embedded secondary subtitles survive reopening at resume',
    (WidgetTester tester) async {
      expect(_root, isNotEmpty, reason: 'Run with the isolated Windows runner');
      expect(
        File(_video).existsSync(),
        isTrue,
        reason: 'Provide FUSHI_PROBE_VIDEO',
      );
      expect(
        File(_primary).existsSync(),
        isTrue,
        reason: 'Provide FUSHI_PROBE_PRIMARY',
      );
      await launchFushiTestApp();
      expect(await waitForHome(tester), isTrue);
      final AppModel model = await readyAppModel(tester);
      final VideoBookRepository repo = VideoBookRepository(model.database);
      const String uid = 'video/itest-local-secondary-resume';
      final File primaryCopy = await File(_primary).copy('$_root/primary.srt');
      await repo.saveVideoBook(
        VideoBooksCompanion(
          bookUid: const Value(uid),
          title: const Value('Local secondary resume regression'),
          videoPath: const Value(_video),
          subtitleSource: Value(primaryCopy.path),
          secondarySubtitleSource: Value('embedded:$_secondary'),
          lastPositionMs: const Value(_resumeMs),
        ),
      );
      final NavigatorState navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      final List<Map<String, Object?>> evidence = <Map<String, Object?>>[];
      VideoPlayerController? previousController;
      for (int opening = 0; opening < 2; opening++) {
        unawaited(
          navigator.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => VideoFushiPage(bookUid: uid, repo: repo),
            ),
          ),
        );
        VideoPlayerController? controller;
        final Stopwatch wait = Stopwatch()..start();
        while (wait.elapsed < const Duration(seconds: 60)) {
          await tester.pump(const Duration(milliseconds: 100));
          final Finder overlays = find.byType(VideoSubtitleOverlay);
          if (overlays.evaluate().isEmpty) continue;
          controller = tester
              .widget<VideoSubtitleOverlay>(overlays.first)
              .controller;
          if (controller.cues.isNotEmpty &&
              controller.secondaryCues.isNotEmpty &&
              (controller.positionMs ?? 0) >= _resumeMs - 2000) {
            break;
          }
        }
        expect(controller, isNotNull);
        final VideoPlayerController c = controller!;
        expect(identical(c, previousController), isFalse);
        previousController = c;
        await c.pause();
        await c.setVolume(0);
        expect(c.positionMs, greaterThanOrEqualTo(_resumeMs - 2000));
        expect(c.positionMs, lessThan(_resumeMs + 60000));
        expect(c.cues, isNotEmpty, reason: 'Primary subtitle must restore');
        expect(
          c.secondaryCues,
          isNotEmpty,
          reason:
              'The persisted embedded track must retain its codec and restore',
        );
        int? visibleAt;
        for (final secondary in c.secondaryCues) {
          if (secondary.endMs <= _resumeMs) continue;
          for (final primary in c.cues) {
            final int start = secondary.startMs > primary.startMs
                ? secondary.startMs
                : primary.startMs;
            final int end = secondary.endMs < primary.endMs
                ? secondary.endMs
                : primary.endMs;
            if (start >= _resumeMs && end - start >= 500) {
              visibleAt = start + (end - start) ~/ 2;
              break;
            }
          }
          if (visibleAt != null) break;
        }
        expect(
          visibleAt,
          isNotNull,
          reason: 'Find real overlapping primary/secondary dialogue',
        );
        await c.seekMs(visibleAt!);
        for (int i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (((c.positionMs ?? 0) - visibleAt).abs() < 250 &&
              c.activeCues.isNotEmpty &&
              c.secondaryActiveCues.isNotEmpty) {
            break;
          }
        }
        expect(c.activeCues, isNotEmpty);
        expect(c.secondaryActiveCues, isNotEmpty);
        expect(c.positionMs, closeTo(visibleAt, 250));
        evidence.add(<String, Object?>{
          'opening': opening,
          'positionMs': c.positionMs,
          'primaryCount': c.cues.length,
          'secondaryCount': c.secondaryCues.length,
          'primary': c.activeCues.map((cue) => cue.text).toList(),
          'secondary': c.secondaryActiveCues.map((cue) => cue.text).toList(),
        });
        final ObserveShot shot = await captureFlutterFrame(
          tester,
          'local-secondary-resume-$opening',
        );
        expect(shot.saved, isTrue);
        expect(await navigator.maybePop(), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(VideoFushiPage), findsNothing);
        await repo.updatePosition(uid, _resumeMs);
      }
      await File(
        '${observeScreenshotDir().path}/local-secondary-resume.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(evidence));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
