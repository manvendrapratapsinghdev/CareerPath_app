import 'package:career_path/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'institute ladder and location labels are translated for every locale',
    () async {
      final english = await AppLocalizations.delegate.load(const Locale('en'));

      for (final locale in AppLocalizations.supportedLocales) {
        if (locale.languageCode == 'en') continue;
        final localized = await AppLocalizations.delegate.load(locale);

        expect(
          localized.institute_ladderTitle,
          isNot(english.institute_ladderTitle),
          reason: '${locale.languageCode} should translate the ladder title',
        );
        expect(
          localized.institute_applyLocation,
          isNot(english.institute_applyLocation),
          reason: '${locale.languageCode} should translate the apply action',
        );
        expect(
          localized.institute_collegeLadderSubtitle(3),
          isNot(english.institute_collegeLadderSubtitle(3)),
          reason:
              '${locale.languageCode} should translate ladder coverage copy',
        );
        expect(
          localized.institute_entryRoutesSummary,
          isNot(english.institute_entryRoutesSummary),
          reason: '${locale.languageCode} should translate route card copy',
        );
      }
    },
  );
}
