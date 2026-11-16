import 'package:latlong2/latlong.dart';

class ShelterRecord {
  const ShelterRecord(
    this.name,
    this.address,
    this.source,
    this.verifiedAt,
    this.simulation,
    this.latitude,
    this.longitude, {
    this.id,
    this.capacity,
    this.status,
  });

  static const localSimulationFixtures = <ShelterRecord>[
    ShelterRecord(
      'Shelter Simulasi SiagaNow',
      'Area Kuranji, Padang, Sumatera Barat',
      'Fixture lokal SiagaNow',
      null,
      true,
      -0.9138,
      100.3974,
      id: 'siaganow-sim-kuranji-001',
    ),
  ];

  final String? id;
  final String name;
  final String address;
  final String? source;
  final String? verifiedAt;
  final bool simulation;
  final double? latitude;
  final double? longitude;
  final int? capacity;
  final String? status;

  bool get hasValidCoordinates => latitude != null && longitude != null;
  bool get isVerified => !simulation && verifiedAt?.isNotEmpty == true;

  factory ShelterRecord.fromJson(
    Map<String, dynamic> json, {
    bool simulation = false,
  }) => ShelterRecord(
    (json['name'] ?? json['title'] ?? 'Titik informasi').toString(),
    (json['address'] ?? json['description'] ?? 'Lokasi belum dijelaskan')
        .toString(),
    json['source']?.toString(),
    json['verified_at']?.toString(),
    simulation ||
        json['simulation'] == true ||
        json['is_simulated'] == true ||
        const {
          'simulation',
          'simulated',
        }.contains(json['data_type']?.toString().toLowerCase()),
    _coordinate(json['latitude'] ?? json['lat'], -90, 90),
    _coordinate(json['longitude'] ?? json['lng'] ?? json['lon'], -180, 180),
    id: json['id']?.toString(),
    capacity: int.tryParse('${json['capacity']}'),
    status: json['status']?.toString(),
  );

  double? distanceFrom(LatLng? location) {
    if (!hasValidCoordinates || location == null) return null;
    return const Distance().as(
      LengthUnit.Kilometer,
      location,
      LatLng(latitude!, longitude!),
    );
  }

  static double? _coordinate(Object? value, double min, double max) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return parsed != null && parsed.isFinite && parsed >= min && parsed <= max
        ? parsed
        : null;
  }
}
