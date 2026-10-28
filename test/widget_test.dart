import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:pet_care_ai/main.dart';
import 'package:pet_care_ai/profile/cat_profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pet_core/pet_core.dart';

void main() {
  setUpAll(() => dotenv.loadFromString(envString: '', isOptional: true));

  testWidgets('user message appears, then assistant reply', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await CatProfileStore.load();
    await tester.pumpWidget(
      PetCareApp(
        profileStore: store,
        aiOverride: MockAiService(
          delay: const Duration(milliseconds: 10),
          wordDelay: const Duration(milliseconds: 1),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Chat with Pet Pulz AI'));
    await tester.pumpAndSettle();

    expect(find.text('Hi, I\'m Whiskers!'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Any games to play?');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(find.text('Any games to play?'), findsOneWidget);

    // Advance fake time so every streamed word has arrived.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('Wand toy', findRichText: true), findsOneWidget);
  });
}
