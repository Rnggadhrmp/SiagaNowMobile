import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siaga_now_mobile/main.dart';

final class _TestPlatformFile extends PlatformFile {
  _TestPlatformFile(this.name, this.bytes);

  @override
  final String name;
  final Uint8List bytes;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('API response models', () {
    test('parses an authenticated user profile', () {
      final user = UserProfile.fromJson({
        'id': 42,
        'name': 'Ayu',
        'email': 'ayu@example.test',
      });
      expect(user.id, 42);
      expect(user.name, 'Ayu');
      expect(user.email, 'ayu@example.test');
    });

    test('preserves shelter source and simulation status', () {
      final shelter = ShelterRecord.fromJson({
        'name': 'Titik contoh',
        'address': 'Padang',
        'source': 'Data Simulasi',
        'verified_at': null,
      }, simulation: true);
      expect(shelter.name, 'Titik contoh');
      expect(shelter.source, 'Data Simulasi');
      expect(shelter.verifiedAt, isNull);
      expect(shelter.simulation, isTrue);
    });

    test('accepts valid shelter coordinates and rejects invalid values', () {
      final valid = ShelterRecord.fromJson({
        'name': 'Shelter nyata',
        'latitude': '-0.95',
        'longitude': 100.4,
      });
      expect(valid.hasValidCoordinates, isTrue);
      expect(valid.latitude, -0.95);
      expect(valid.longitude, 100.4);

      final invalid = ShelterRecord.fromJson({
        'latitude': 91,
        'longitude': 'unknown',
      });
      expect(invalid.hasValidCoordinates, isFalse);
    });

    test('parses the report identifier and actual status', () {
      final receipt = ReportReceipt.fromJson({'id': 17, 'status': 'submitted'});
      expect(receipt.id, 17);
      expect(receipt.status, 'submitted');
      expect(receipt.message, contains('#17'));
    });

    test('parses BMKG forecast fields without assuming missing values', () {
      final forecast = WeatherPeriod.fromJson({
        'local_datetime': '2026-10-30T12:00:00+07:00',
        'temperature': 27.5,
        'condition': 'Cerah berawan',
        'humidity': 78,
      });
      expect(forecast.temperature, 27.5);
      expect(forecast.condition, 'Cerah berawan');
      expect(forecast.humidity, 78);
      expect(WeatherPeriod.fromJson({}).temperature, isNull);
    });
  });

  test(
    'sends report fields and evidence through the existing multipart API',
    () async {
      http.BaseRequest? captured;
      final api = ApiService(
        const FlutterSecureStorage(),
        client: MockClient((request) async {
          captured = request;
          return http.Response('{"data":{"id":7,"status":"submitted"}}', 201);
        }),
        tokenReader: () async => 'test-token',
      );

      final result = await api.uploadReport(
        {
          'title': 'QA contract payload',
          'latitude': -0.95,
          'longitude': 100.4,
          'event_date': '2026-11-02',
          'event_time': '10:00',
          'event_type': 'Banjir',
          'damage_level': 'Rendah',
          'description': 'Synthetic payload stays inside this mocked test.',
          'injured': 0,
        },
        [
          _TestPlatformFile('evidence.jpg', Uint8List.fromList([1, 2, 3])),
        ],
      );

      expect(result['data']['id'], 7);
      expect(captured, isA<http.Request>());
      final request = captured! as http.Request;
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data; boundary='),
      );
      expect(request.body, contains('name="title"'));
      expect(request.body, contains('QA contract payload'));
      expect(request.body, contains('name="latitude"'));
      expect(request.body, contains('-0.95'));
      expect(request.body, contains('name="injured"'));
      expect(
        request.body,
        contains('name="evidence[]"; filename="evidence.jpg"'),
      );
    },
  );
}
