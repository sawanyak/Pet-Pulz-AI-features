import '../models/cat_profile.dart';
import '../models/health_screening.dart';
import 'vision_service.dart';

/// Fake photo check for demo mode and tests: no internet, no cost.
/// It always returns the same example so you can see the result screen.
class MockVisionService implements VisionService {
  MockVisionService({this.delay = const Duration(milliseconds: 1500)});

  final Duration delay;

  @override
  Future<HealthScreening> screen({
    required List<ScreenerPhoto> photos,
    required String concern,
    required String? duration,
    required CatProfile? cat,
  }) async {
    await Future<void>.delayed(delay);
    return const HealthScreening(
      urgency: Urgency.seeVetSoon,
      summary:
          'There is some redness and mild crusting near the eye. '
          '(Demo result - add an API key for a real check.)',
      observations: ['Redness around the left eye', 'Light crusting'],
      possibleCauses: [
        'Irritation or a minor infection',
        'An allergy or a small scratch',
      ],
      homeCare: [
        'Keep the area clean and dry',
        'Stop your cat from rubbing it if you can',
      ],
      seeVetIf: [
        'The eye is held shut or looks cloudy',
        'There is thick yellow or green discharge',
        'It is not better in 1-2 days',
      ],
      photoNote: 'A closer photo in daylight would help.',
    );
  }
}
