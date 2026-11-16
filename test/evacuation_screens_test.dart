import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:siaga_now_mobile/models/shelter_record.dart';
import 'package:siaga_now_mobile/screens/evacuation_screens.dart';
import 'package:siaga_now_mobile/services/routing_service.dart';

final class _UnavailableRouting implements RoutingService {
  @override
  Future<RouteResult?> route({
    required LatLng from,
    required LatLng to,
  }) async => null;
}

final _shelter = ShelterRecord(
  'Shelter Uji',
  'Jalan Kuranji, Padang',
  'Database SiagaNow',
  '2026-11-16T09:00:00+07:00',
  false,
  -0.9138,
  100.3974,
  capacity: 120,
  status: 'available',
);

void main() {
  testWidgets('shelter detail renders on 320 and 360 dp screens', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final size in const [Size(320, 640), Size(360, 740)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: const TextScaler.linear(1.5),
          ),
          child: MaterialApp(
            home: ShelterDetailPage(
              shelter: _shelter,
              userLocation: const LatLng(-0.91, 100.39),
              routingService: _UnavailableRouting(),
              loggedIn: false,
              onSendSafeStatus: () async => false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Informasi Shelter'), findsWidgets);
      expect(find.text('Foto belum tersedia'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  test('unverified and simulated shelter records are not official', () {
    final unverified = ShelterRecord(
      'Titik uji',
      'Padang',
      'Data belum diverifikasi',
      null,
      false,
      -0.9,
      100.4,
    );
    expect(unverified.isVerified, isFalse);
    expect(ShelterRecord.localSimulationFixtures.single.isVerified, isFalse);
    expect(ShelterRecord.localSimulationFixtures.single.simulation, isTrue);
    expect(_shelter.isVerified, isTrue);
  });

  testWidgets('unconfigured routing explains fallback without fake ETA', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EvacuationNavigationPage(
          shelter: _shelter,
          userLocation: const LatLng(-0.91, 100.39),
          routingService: _UnavailableRouting(),
          loggedIn: false,
          onSendSafeStatus: () async => false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Navigasi dalam aplikasi belum tersedia.'),
      findsOneWidget,
    );
    expect(find.text('Estimasi tiba belum tersedia'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'arrival safe status requires login and reports only API success',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ShelterArrivalPage(
            shelter: _shelter,
            userLocation: const LatLng(-0.91, 100.39),
            loggedIn: false,
            onSendSafeStatus: () async {
              calls++;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final signedOutButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Masuk untuk Kirim Status Aman'),
      );
      expect(signedOutButton.onPressed, isNull);
      expect(calls, 0);

      await tester.pumpWidget(
        MaterialApp(
          home: ShelterArrivalPage(
            shelter: _shelter,
            userLocation: const LatLng(-0.91, 100.39),
            loggedIn: true,
            onSendSafeStatus: () async {
              calls++;
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kirim Status Aman'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining('Status aman tersimpan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
