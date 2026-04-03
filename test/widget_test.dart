import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:career_path/data/profile_repository.dart';
import 'package:career_path/main.dart';
import 'package:career_path/services/api_client.dart';
import 'package:career_path/services/career_data_service.dart';
import 'package:career_path/services/network_service.dart';
import 'package:career_path/services/profile_service.dart';

void main() {
  testWidgets('App launches and shows ProfileScreen when no profile',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final profileService = ProfileService(ProfileRepository(prefs));
    final careerDataService = CareerDataService(ApiClient());
    final networkService = NetworkService();

    await tester.pumpWidget(CareerPathApp(
      profileService: profileService,
      careerDataService: careerDataService,
      networkService: networkService,
      hasProfile: false,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Welcome!'), findsOneWidget);
  });
}
