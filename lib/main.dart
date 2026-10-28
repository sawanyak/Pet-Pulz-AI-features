import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat/chat_controller.dart';
import 'chat/chat_history.dart';
import 'home/home_screen.dart';
import 'app_services.dart';
import 'profile/cat_profile_store.dart';
import 'theme/pet_pulz_theme.dart';
import 'package:pet_core/pet_core.dart';
import 'screener/photo_picker.dart';
import 'studio/photo_enhancer.dart';
import 'studio/share_service.dart';
import 'voice/flutter_tts_output.dart';
import 'voice/speech_io.dart';
import 'voice/speech_to_text_input.dart';

/// Every Flutter app starts at main(). runApp() puts the root widget on screen.
Future<void> main() async {
  // Needed because we do async work (loading .env) before runApp().
  WidgetsFlutterBinding.ensureInitialized();
  // Reads the .env file into memory. If it's missing we carry on with an
  // empty config, so the app starts in demo mode instead of crashing.
  await dotenv.load(isOptional: true);
  // Opens the phone's storage and reads any saved cat profile and chat.
  final profiles = await CatProfileStore.load();
  final chatStore = await PrefsChatStore.open();
  final prefs = await SharedPreferences.getInstance();

  final AppServices services;
  try {
    services = AppServices.fromConfig(prefs: prefs);
  } on FormatException catch (e) {
    // A wrong BACKEND_URL: say so, instead of a blank screen or a crash.
    runApp(_ConfigErrorApp(message: e.message));
    return;
  }
  runApp(
    PetCareApp(
      profileStore: profiles,
      chatStore: chatStore,
      services: services,
    ),
  );
}

/// Shown instead of the app when the settings are unusable.
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Configuration problem\n\n$message\n\nCheck your .env file.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class PetCareApp extends StatefulWidget {
  const PetCareApp({
    super.key,
    required this.profileStore,
    this.aiOverride,
    this.services,
    this.chatHistory,
    this.chatStore,
    this.speechInput,
    this.speechOutput,
    this.visionService,
    this.photoPicker,
    this.contentService,
    this.photoEnhancer,
    this.shareService,
  });

  final CatProfileStore profileStore;

  /// Where the chat is saved. Null (as in most tests) means not saved.
  final ChatHistory? chatHistory;

  /// Where ALL chats are saved (the app uses this). Wins over [chatHistory].
  final ChatStore? chatStore;

  /// Lets tests inject a fake microphone and speaker.
  final SpeechInput? speechInput;
  final SpeechOutput? speechOutput;

  /// Lets tests inject a fake photo analyser and photo source.
  final VisionService? visionService;
  final PhotoPicker? photoPicker;

  /// Lets tests inject fake caption writing, photo enhancing and sharing.
  final ContentService? contentService;
  final PhotoEnhancer? photoEnhancer;
  final ShareService? shareService;

  /// Lets tests inject a fake AI.
  final AiService? aiOverride;

  /// The AI services to use. Null means: decide from the settings.
  final AppServices? services;

  @override
  State<PetCareApp> createState() => _PetCareAppState();
}

class _PetCareAppState extends State<PetCareApp> {
  // How we reach the AI: the backend server, direct keys (development
  // only), or demo mode. Decided once from the settings (see AppServices).
  late final AppServices _services =
      widget.services ?? AppServices.fromConfig();

  // Created ONCE here (not in build) so the chat survives rebuilds.
  late final AiService _ai = widget.aiOverride ?? _services.chat;

  // Real voice plugins. Creating these does nothing until voice mode is
  // opened, so the app starts (and tests run) without touching the platform.
  final SpeechInput _defaultInput = SpeechToTextInput();
  final SpeechOutput _defaultOutput = FlutterTtsOutput();

  late final VisionService _vision = widget.visionService ?? _services.vision;
  final PhotoPicker _defaultPicker = ImagePickerPhotoPicker();

  late final ContentService _content =
      widget.contentService ?? _services.content;
  final PhotoEnhancer _defaultEnhancer = IsolatePhotoEnhancer();
  final ShareService _defaultShare = SharePlusShareService();

  late final ChatController _controller = ChatController(
    _ai,
    widget.profileStore,
    history: widget.chatHistory,
    store: widget.chatStore,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pet Pulz AI',
      debugShowCheckedModeBanner: false,
      theme: PetPulzTheme.themeData,
      home: HomeScreen(
        controller: _controller,
        profileStore: widget.profileStore,
        speechInput: widget.speechInput ?? _defaultInput,
        speechOutput: widget.speechOutput ?? _defaultOutput,
        visionService: _vision,
        photoPicker: widget.photoPicker ?? _defaultPicker,
        contentService: _content,
        photoEnhancer: widget.photoEnhancer ?? _defaultEnhancer,
        shareService: widget.shareService ?? _defaultShare,
        usingMock: _ai is MockAiService,
      ),
    );
  }
}
