import 'package:flutter_test/flutter_test.dart';
import 'package:siaga_now_mobile/main.dart';

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
}
