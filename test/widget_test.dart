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

  testWidgets('halaman sukses laporan menampilkan CTA yang berfungsi', (
    tester,
  ) async {
    var returnedHome = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ReportSuccessPage(onReturnHome: () => returnedHome = true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Laporan Tersimpan'), findsOneWidget);
    expect(
      find.text(
        'Laporan berhasil dikirim dan sedang diproses oleh tim terkait.',
      ),
      findsOneWidget,
    );
    expect(find.text('Shelter Kuranji'), findsNothing);

    await tester.tap(find.text('Kembali Ke Beranda'));
    await tester.pump();
    expect(returnedHome, isTrue);
    expect(tester.takeException(), isNull);
  });
}
