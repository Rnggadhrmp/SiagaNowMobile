import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:siaga_now_mobile/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onboarding completion persists through SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final progress = SharedPreferencesOnboardingStore();

    expect(await progress.isComplete(), isFalse);
    await progress.markComplete();
    expect(await progress.isComplete(), isTrue);
  });

  testWidgets('Skip menyelesaikan onboarding', (tester) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SiagaNowIntro(
          onFinished: () async {
            finished = true;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Kenali Risiko di Sekitarmu'), findsOneWidget);
    await tester.tap(find.text('Lewati'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  testWidgets('Selanjutnya membuka tiga intro dan Mulai Sekarang selesai', (
    tester,
  ) async {
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SiagaNowIntro(
          onFinished: () async {
            finished = true;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Kenali Risiko di Sekitarmu'), findsOneWidget);
    await tester.tap(find.text('Selanjutnya'));
    await tester.pumpAndSettle();
    expect(find.text('Informasi dan Peta Bencana'), findsOneWidget);

    await tester.tap(find.text('Selanjutnya'));
    await tester.pumpAndSettle();
    expect(find.text('Keluarga Siaga'), findsOneWidget);
    expect(find.text('Mulai Sekarang'), findsOneWidget);

    await tester.tap(find.text('Mulai Sekarang'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });
}
