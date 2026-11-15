import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:siaga_now_mobile/location_warning.dart';
import 'package:siaga_now_mobile/main.dart';

class _FakeLocationProvider implements WarningLocationProvider {
  _FakeLocationProvider(this.result);

  final Future<LocationCoordinates> Function() result;
  int calls = 0;

  @override
  Future<LocationCoordinates> currentCoordinates() {
    calls++;
    return result();
  }
}

Position _position({double latitude = -0.95, double longitude = 100.4}) =>
    Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.utc(2026, 11, 15),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 1,
      isMocked: false,
    );

void main() {
  group('GeolocatorWarningLocationProvider', () {
    test(
      'reports disabled location services without requesting coordinates',
      () async {
        var positionRequests = 0;
        final provider = GeolocatorWarningLocationProvider(
          serviceEnabled: () async => false,
          checkPermission: () async => LocationPermission.whileInUse,
          requestPermission: () async => LocationPermission.whileInUse,
          currentPosition: () async {
            positionRequests++;
            return _position();
          },
        );

        await expectLater(
          provider.currentCoordinates(),
          throwsA(
            isA<LocationAccessException>().having(
              (error) => error.issue,
              'issue',
              LocationAccessIssue.serviceDisabled,
            ),
          ),
        );
        expect(positionRequests, 0);
      },
    );

    test(
      'requests permission after a normal denial and preserves denial state',
      () async {
        var permissionRequests = 0;
        final provider = GeolocatorWarningLocationProvider(
          serviceEnabled: () async => true,
          checkPermission: () async => LocationPermission.denied,
          requestPermission: () async {
            permissionRequests++;
            return LocationPermission.denied;
          },
          currentPosition: () async => _position(),
        );

        await expectLater(
          provider.currentCoordinates(),
          throwsA(
            isA<LocationAccessException>().having(
              (error) => error.issue,
              'issue',
              LocationAccessIssue.permissionDenied,
            ),
          ),
        );
        expect(permissionRequests, 1);
      },
    );

    test(
      'does not request again after permission was denied permanently',
      () async {
        var permissionRequests = 0;
        final provider = GeolocatorWarningLocationProvider(
          serviceEnabled: () async => true,
          checkPermission: () async => LocationPermission.deniedForever,
          requestPermission: () async {
            permissionRequests++;
            return LocationPermission.whileInUse;
          },
          currentPosition: () async => _position(),
        );

        await expectLater(
          provider.currentCoordinates(),
          throwsA(
            isA<LocationAccessException>().having(
              (error) => error.issue,
              'issue',
              LocationAccessIssue.permissionDeniedForever,
            ),
          ),
        );
        expect(permissionRequests, 0);
      },
    );

    test(
      'maps GPS timeout to unavailable and accepts valid coordinates',
      () async {
        final timedOut = GeolocatorWarningLocationProvider(
          serviceEnabled: () async => true,
          checkPermission: () async => LocationPermission.whileInUse,
          currentPosition: () => Future.error(TimeoutException('GPS timeout')),
        );
        await expectLater(
          timedOut.currentCoordinates(),
          throwsA(
            isA<LocationAccessException>().having(
              (error) => error.issue,
              'issue',
              LocationAccessIssue.unavailable,
            ),
          ),
        );

        final available = GeolocatorWarningLocationProvider(
          serviceEnabled: () async => true,
          checkPermission: () async => LocationPermission.whileInUse,
          currentPosition: () async => _position(),
        );
        final coordinates = await available.currentCoordinates();
        expect(coordinates.latitude, -0.95);
        expect(coordinates.longitude, 100.4);
        expect(coordinates.isValid, isTrue);
      },
    );

    test('rejects invalid coordinates from the location provider', () async {
      final provider = GeolocatorWarningLocationProvider(
        serviceEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        currentPosition: () async => _position(latitude: 91),
      );

      await expectLater(
        provider.currentCoordinates(),
        throwsA(isA<LocationAccessException>()),
      );
    });
  });

  group('Home location warning check', () {
    Future<void> openHome(
      WidgetTester tester, {
      required WarningLocationProvider provider,
      required http.Client client,
    }) async {
      final api = ApiService(
        const FlutterSecureStorage(),
        client: client,
        tokenReader: () async => null,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            api: api,
            locationProvider: provider,
            onSelectTab: (_) {},
            onOpenFamily: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text('Periksa peringatan di lokasi saya'),
      );
      await tester.pumpAndSettle();
    }

    http.Response homeResponse(http.Request request) {
      if (request.url.path == '/api/home') {
        return http.Response(
          jsonEncode({
            'data_type': 'unavailable',
            'weather': <String, dynamic>{},
            'statistics': <String, dynamic>{},
            'warning': {
              'status': 'unknown',
              'active': false,
              'message': 'Peringatan belum diperiksa untuk lokasi Anda.',
            },
            'flood_detection': {
              'service_status': 'not_configured',
              'status': 'unknown',
              'message': 'Layanan AI belum dikonfigurasi pada server.',
              'source': 'SiagaNow AI Flood Detection',
              'latest_observation': null,
            },
          }),
          200,
        );
      }
      if (request.url.path == '/api/news') {
        return http.Response(
          jsonEncode({'data': <Object>[], 'data_type': 'unavailable'}),
          200,
        );
      }
      return http.Response(jsonEncode({'message': 'Unexpected request'}), 404);
    }

    testWidgets('asks for consent before requesting location or API', (
      tester,
    ) async {
      final provider = _FakeLocationProvider(
        () async =>
            const LocationCoordinates(latitude: -0.95, longitude: 100.4),
      );
      var warningRequests = 0;
      await openHome(
        tester,
        provider: provider,
        client: MockClient((request) async {
          if (request.url.path == '/api/weather-warning') warningRequests++;
          return homeResponse(request);
        }),
      );

      await tester.tap(find.text('Periksa peringatan di lokasi saya'));
      await tester.pumpAndSettle();
      expect(find.textContaining('satu kali pemeriksaan'), findsOneWidget);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      expect(provider.calls, 0);
      expect(warningRequests, 0);
      expect(find.text('Status peringatan belum diketahui'), findsOneWidget);
    });

    testWidgets('renders AI flood status from the shared Laravel home API', (
      tester,
    ) async {
      final provider = _FakeLocationProvider(
        () async =>
            const LocationCoordinates(latitude: -0.95, longitude: 100.4),
      );
      await openHome(
        tester,
        provider: provider,
        client: MockClient((request) async => homeResponse(request)),
      );

      await tester.ensureVisible(find.text('AI Flood Detection'));
      await tester.pumpAndSettle();
      expect(find.text('AI Flood Detection'), findsOneWidget);
      expect(find.text('Unknown'), findsOneWidget);
      expect(
        find.textContaining('belum dikonfigurasi pada server'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Hasil model bukan peringatan resmi'),
        findsOneWidget,
      );
    });

    testWidgets(
      'sends lat and lng after consent and renders the server warning',
      (tester) async {
        final provider = _FakeLocationProvider(
          () async =>
              const LocationCoordinates(latitude: -0.95, longitude: 100.4),
        );
        Uri? warningUri;
        await openHome(
          tester,
          provider: provider,
          client: MockClient((request) async {
            if (request.url.path == '/api/weather-warning') {
              warningUri = request.url;
              return http.Response(
                jsonEncode({
                  'status': 'warning_found',
                  'message':
                      'Poligon peringatan mencakup titik yang diperiksa.',
                  'location': {'lat': -0.95, 'lng': 100.4},
                  'warnings': [
                    {'title': 'Peringatan hujan lebat', 'area': 'Kota Padang'},
                  ],
                  'source': 'BMKG',
                  'source_url': 'https://www.bmkg.go.id/alerts/nowcast/id',
                  'checked_at': '2026-11-15T10:00:00+07:00',
                }),
                200,
              );
            }
            return homeResponse(request);
          }),
        );

        await tester.tap(find.text('Periksa peringatan di lokasi saya'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lanjutkan'));
        await tester.pumpAndSettle();

        expect(provider.calls, 1);
        expect(warningUri?.path, '/api/weather-warning');
        expect(warningUri?.queryParameters, {'lat': '-0.95', 'lng': '100.4'});
        expect(find.text('Peringatan aktif'), findsOneWidget);
        expect(
          find.text('Peringatan hujan lebat · Kota Padang'),
          findsOneWidget,
        );
        expect(find.textContaining('Sumber: BMKG'), findsOneWidget);
        expect(find.textContaining('Diperiksa 2026-11-15'), findsOneWidget);
      },
    );

    testWidgets(
      'location failure leaves warning unknown and does not call API',
      (tester) async {
        final provider = _FakeLocationProvider(
          () => Future.error(
            const LocationAccessException(
              LocationAccessIssue.permissionDenied,
              'Izin lokasi ditolak.',
            ),
          ),
        );
        var warningRequests = 0;
        await openHome(
          tester,
          provider: provider,
          client: MockClient((request) async {
            if (request.url.path == '/api/weather-warning') warningRequests++;
            return homeResponse(request);
          }),
        );

        await tester.tap(find.text('Periksa peringatan di lokasi saya'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lanjutkan'));
        await tester.pumpAndSettle();

        expect(find.text('Status peringatan belum diketahui'), findsOneWidget);
        expect(find.textContaining('Izin lokasi ditolak.'), findsOneWidget);
        expect(warningRequests, 0);
      },
    );

    testWidgets('renders no-warning status and the server safety caveat', (
      tester,
    ) async {
      final provider = _FakeLocationProvider(
        () async =>
            const LocationCoordinates(latitude: -0.95, longitude: 100.4),
      );
      await openHome(
        tester,
        provider: provider,
        client: MockClient((request) async {
          if (request.url.path == '/api/weather-warning') {
            return http.Response(
              jsonEncode({
                'status': 'no_warning_found',
                'message': 'Tidak ditemukan poligon peringatan yang mencakup titik ini. Ini bukan jaminan lokasi aman.',
                'location': {'lat': -0.95, 'lng': 100.4},
                'warnings': <Object>[],
                'source': 'BMKG',
                'source_url': 'https://www.bmkg.go.id/alerts/nowcast/id',
                'checked_at': '2026-11-15T10:00:00+07:00',
              }),
              200,
            );
          }
          return homeResponse(request);
        }),
      );

      await tester.tap(find.text('Periksa peringatan di lokasi saya'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();

      expect(find.text('Tidak ada peringatan aktif'), findsOneWidget);
      expect(
        find.textContaining('Ini bukan jaminan lokasi aman.'),
        findsOneWidget,
      );
      expect(find.textContaining('Sumber: BMKG'), findsOneWidget);
    });

    testWidgets('keeps status unknown when API response is malformed', (
      tester,
    ) async {
      final provider = _FakeLocationProvider(
        () async =>
            const LocationCoordinates(latitude: -0.95, longitude: 100.4),
      );
      await openHome(
        tester,
        provider: provider,
        client: MockClient((request) async {
          if (request.url.path == '/api/weather-warning') {
            return http.Response(
              jsonEncode({'message': 'Missing status'}),
              200,
            );
          }
          return homeResponse(request);
        }),
      );

      await tester.tap(find.text('Periksa peringatan di lokasi saya'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lanjutkan'));
      await tester.pumpAndSettle();

      expect(find.text('Status peringatan belum diketahui'), findsOneWidget);
      expect(
        find.textContaining('Respons status peringatan tidak lengkap'),
        findsOneWidget,
      );
    });

    testWidgets('API unavailable response remains unknown and can be retried', (
      tester,
    ) async {
      final provider = _FakeLocationProvider(
        () async =>
            const LocationCoordinates(latitude: -0.95, longitude: 100.4),
      );
      var warningRequests = 0;
      await openHome(
        tester,
        provider: provider,
        client: MockClient((request) async {
          if (request.url.path == '/api/weather-warning') {
            warningRequests++;
            return http.Response(
              jsonEncode({
                'status': 'unknown',
                'message': 'Detail peringatan belum dapat diverifikasi.',
                'warnings': <Object>[],
                'source': 'BMKG',
                'source_url': 'https://www.bmkg.go.id/alerts/nowcast/id',
              }),
              503,
            );
          }
          return homeResponse(request);
        }),
      );

      Future<void> submitCheck() async {
        await tester.tap(find.text('Periksa peringatan di lokasi saya'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lanjutkan'));
        await tester.pumpAndSettle();
      }

      await submitCheck();
      expect(find.text('Status peringatan belum diketahui'), findsOneWidget);
      expect(
        find.textContaining('Detail peringatan belum dapat diverifikasi.'),
        findsOneWidget,
      );
      await submitCheck();
      expect(warningRequests, 2);
    });
  });
}
