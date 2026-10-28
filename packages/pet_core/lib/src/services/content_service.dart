import '../models/cat_profile.dart';
import '../models/content_suggestion.dart';
import 'content_prompt.dart';
import 'structured_vision.dart';
import 'vision_service.dart';

/// Looks at a photo and suggests mood, focus point, captions and hashtags.
abstract class ContentService {
  Future<ContentSuggestion> suggest({
    required ScreenerPhoto photo,
    required String note,
    required CatProfile? cat,
  });
}

/// The real implementation, independent of the AI provider.
class AiContentService implements ContentService {
  AiContentService(this._vision);

  final StructuredVision _vision;

  @override
  Future<ContentSuggestion> suggest({
    required ScreenerPhoto photo,
    required String note,
    required CatProfile? cat,
  }) async {
    final json = await _vision.run(
      system: buildContentSystemPrompt(cat),
      userText: buildContentUserText(note),
      photos: [photo],
      schema: contentSchema,
      toolName: 'suggest_post',
      toolDescription:
          'Report the mood, focus point, captions and hashtags '
          'for the Instagram post.',
      maxTokens: 1500,
    );
    return ContentSuggestion.fromJson(json);
  }
}

/// Fake suggestions for demo mode and tests (no internet, no cost).
class MockContentService implements ContentService {
  MockContentService({this.delay = const Duration(milliseconds: 1200)});

  final Duration delay;

  @override
  Future<ContentSuggestion> suggest({
    required ScreenerPhoto photo,
    required String note,
    required CatProfile? cat,
  }) async {
    await Future<void>.delayed(delay);
    final name = cat?.name ?? 'My cat';
    return ContentSuggestion(
      mood: PetMood.sleepy,
      subject: 'a cat resting',
      captions: [
        CaptionOption(
          tone: 'funny',
          text: '$name is currently not accepting visitors. \u{1F634}',
        ),
        CaptionOption(
          tone: 'sweet',
          text: 'Sweet dreams, little one. \u{1F90D}',
        ),
        CaptionOption(
          tone: 'witty',
          text: 'Nap now, plan world domination later.',
        ),
      ],
      hashtags: const [
        'catsofinstagram',
        'lazysunday',
        'catnap',
        'sleepycat',
        'catlife',
        'instacat',
        'cutecats',
        'catlovers',
      ],
    );
  }
}
