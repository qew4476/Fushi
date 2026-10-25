import 'package:flutter_test/flutter_test.dart';
import 'package:fushi/i18n/strings.g.dart';
import 'package:fushi/src/shortcuts/shortcut_action.dart';
import 'package:fushi/src/shortcuts/shortcut_labels.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'copy actions have complete localized names for each subtitle track',
    () {
      final AppLocale original = LocaleSettings.currentLocale;
      addTearDown(() => LocaleSettings.setLocale(original));
      LocaleSettings.setLocale(AppLocale.zhHk);
      expect(ShortcutAction.videoCopySubtitle.label, '複製主字幕');
      expect(ShortcutAction.videoCopySecondarySubtitle.label, '複製副字幕');
      LocaleSettings.setLocale(AppLocale.en);
      expect(ShortcutAction.videoCopySubtitle.label, 'Copy primary subtitle');
      expect(
        ShortcutAction.videoCopySecondarySubtitle.label,
        'Copy secondary subtitle',
      );
    },
  );
}
