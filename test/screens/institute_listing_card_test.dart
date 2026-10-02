import 'package:career_path/models/institute_accreditation.dart';
import 'package:career_path/l10n/app_localizations.dart';
import 'package:career_path/models/institute_campus.dart';
import 'package:career_path/models/institute_classification.dart';
import 'package:career_path/models/institute_catalog.dart';
import 'package:career_path/services/institute_catalog_service.dart';
import 'package:career_path/screens/institute_ladder_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('card shows mapped location, rank, highlights and UGC status', (
    tester,
  ) async {
    final listing = InstituteListing(
      instituteId: 1,
      name: 'IIT Bombay',
      campuses: const [
        InstituteCampus(
          id: 1,
          instituteId: 1,
          placeId: 10,
          placeName: 'Mumbai',
          districtName: 'Mumbai Suburban',
          districtLgd: 1,
          stateCode: 'IN-MH',
          stateName: 'Maharashtra',
          isMain: true,
        ),
      ],
      classification: const InstituteClassification(
        instituteId: 1,
        groupCode: 'G1',
        familySlug: 'iit',
        ownership: 'central_govt',
        confidence: 'high',
      ),
      familyName: 'Indian Institutes of Technology',
      groupName: 'National flagship',
      tier: 1,
      ranking: const InstituteRanking(
        system: 'NIRF',
        year: 2025,
        category: 'Engineering',
        rank: 3,
      ),
      naacGrade: 'A++',
      highlight: RankHighlight.top10,
      ugcBadge: UgcBadge.notApplicable,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: InstituteListingCard(listing: listing)),
      ),
    );

    expect(find.text('IIT Bombay'), findsOneWidget);
    expect(find.text('Mumbai, Maharashtra'), findsOneWidget);
    expect(
      find.text(
        'Mapped from existing institute records; not independently verified.',
      ),
      findsOneWidget,
    );
    expect(find.text('NIRF 2025 Engineering #3'), findsOneWidget);
    expect(find.text('NAAC A++'), findsNothing);
    expect(find.text('Top 10 · NIRF 2025 Engineering'), findsOneWidget);
    expect(find.text('UGC verified ✓'), findsNothing);
  });

  testWidgets('private card distinguishes ranking from accreditations', (
    tester,
  ) async {
    final listing = InstituteListing(
      instituteId: 2,
      name: 'Private Law College',
      classification: const InstituteClassification(
        instituteId: 2,
        groupCode: 'G8',
        ownership: 'private',
        ugcVerified: false,
      ),
      accreditations: const [
        InstituteAccreditation(
          instituteId: 2,
          body: 'NAAC',
          grade: 'A',
          sourceUrl: 'https://naac.gov.in/',
        ),
        InstituteAccreditation(
          instituteId: 2,
          body: 'NBA',
          programme: 'LLB',
          status: 'accredited',
          sourceUrl: 'https://www.nbaind.org/',
        ),
      ],
      naacGrade: 'A',
      ugcBadge: UgcBadge.notVerified,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: InstituteListingCard(listing: listing)),
      ),
    );

    expect(find.text('Not ranked'), findsNothing);
    expect(find.text('NAAC A'), findsOneWidget);
    expect(find.text('NBA · LLB · accredited'), findsOneWidget);
    expect(find.text('Not UGC verified'), findsOneWidget);
  });

  testWidgets('private card shows unknown UGC status as pending', (
    tester,
  ) async {
    final listing = InstituteListing(
      instituteId: 3,
      name: 'Private Institute',
      classification: const InstituteClassification(
        instituteId: 3,
        groupCode: 'G8',
        ownership: 'private',
      ),
      ugcBadge: UgcBadge.pending,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: InstituteListingCard(listing: listing)),
      ),
    );

    expect(find.text('UGC verification pending'), findsOneWidget);
    expect(find.text('Not UGC verified'), findsNothing);
  });

  testWidgets('card makes missing location data explicit', (tester) async {
    const listing = InstituteListing(
      instituteId: 4,
      name: 'Unmapped Institute',
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: InstituteListingCard(listing: listing)),
      ),
    );

    expect(find.text('Location data is unavailable.'), findsOneWidget);
  });
}
