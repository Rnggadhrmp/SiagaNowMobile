import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:siaga_now_mobile/screens/emergency_contacts_page.dart';
import 'package:siaga_now_mobile/services/emergency_contacts_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'emergency contact numbers persist locally and can be cleared',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = EmergencyContactsStore();

      final defaults = await store.load();
      expect(
        defaults.singleWhere((contact) => contact.id == 'pcc112').phone,
        '112',
      );
      expect(
        defaults.singleWhere((contact) => contact.id == 'bpbd').phone,
        isEmpty,
      );

      await store.savePhone('family', '+628123456789');
      final saved = await store.load();
      expect(
        saved.singleWhere((contact) => contact.id == 'family').phone,
        '+628123456789',
      );

      await store.savePhone('family', '');
      final cleared = await store.load();
      expect(
        cleared.singleWhere((contact) => contact.id == 'family').phone,
        isEmpty,
      );
    },
  );

  testWidgets(
    'contacts fit compact screens at large text scale and dialer opens',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Uri? launched;

      for (final size in [const Size(320, 640), const Size(360, 740)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(size),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: EmergencyContactsPage(
              store: EmergencyContactsStore(),
              dialer: (uri) async {
                launched = uri;
                return true;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (final name in [
          'BPBD',
          'Basarnas',
          'Polisi',
          'Pemadam Kebakaran',
          'Rumah Sakit Terdekat',
          'Orang Tua / Kerabat',
        ]) {
          await tester.scrollUntilVisible(
            find.text(name),
            140,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(find.text(name), findsOneWidget);
        }
        expect(find.text('Belum tersedia'), findsOneWidget);
        expect(tester.takeException(), isNull);

        final dial = find.byTooltip(
          'Buka dialer untuk Pusat Panggilan Darurat 112 · Kota Padang',
        );
        await tester.drag(find.byType(ListView).first, const Offset(0, 2000));
        await tester.pumpAndSettle();
        await tester.tap(dial);
        await tester.pumpAndSettle();
        expect(launched?.scheme, 'tel');
        expect(launched?.path, '112');
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('editing an institution contact saves its number on device', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(402, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = EmergencyContactsStore();

    await tester.pumpWidget(
      MaterialApp(home: EmergencyContactsPage(store: store)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit / Tambah Kontak').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('BPBD'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '+628111222333');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(find.text('+628111222333'), findsOneWidget);
    expect(find.text('Kontak tersimpan di perangkat ini.'), findsOneWidget);
    expect(
      (await store.load()).singleWhere((contact) => contact.id == 'bpbd').phone,
      '+628111222333',
    );
    expect(tester.takeException(), isNull);
  });
}
