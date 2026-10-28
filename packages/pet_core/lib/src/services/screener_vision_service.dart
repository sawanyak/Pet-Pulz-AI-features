import '../models/cat_profile.dart';
import '../models/health_screening.dart';
import 'screener_prompt.dart';
import 'structured_vision.dart';
import 'vision_service.dart';

/// The photo health check, independent of which AI provider is used:
/// it supplies the health-check instructions and turns the returned JSON
/// into a [HealthScreening].
class ScreenerVisionService implements VisionService {
  ScreenerVisionService(this._vision);

  final StructuredVision _vision;

  @override
  Future<HealthScreening> screen({
    required List<ScreenerPhoto> photos,
    required String concern,
    required String? duration,
    required CatProfile? cat,
  }) async {
    final json = await _vision.run(
      system: buildScreenerSystemPrompt(cat),
      userText: buildScreenerUserText(
        concern: concern,
        duration: duration,
        photoCount: photos.length,
      ),
      photos: photos,
      schema: screeningSchema,
      toolName: 'report_screening',
      toolDescription: 'Report the result of the cat photo health check.',
      maxTokens: 1500,
    );
    return HealthScreening.fromJson(json);
  }
}
