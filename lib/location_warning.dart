import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationCoordinates {
  const LocationCoordinates({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

enum LocationAccessIssue {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

class LocationAccessException implements Exception {
  const LocationAccessException(this.issue, this.message);

  final LocationAccessIssue issue;
  final String message;

  @override
  String toString() => message;
}

abstract interface class WarningLocationProvider {
  Future<LocationCoordinates> currentCoordinates();
}

class GeolocatorWarningLocationProvider implements WarningLocationProvider {
  GeolocatorWarningLocationProvider({
    Future<bool> Function()? serviceEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<Position> Function()? currentPosition,
  }) : _serviceEnabled = serviceEnabled ?? Geolocator.isLocationServiceEnabled,
       _checkPermission = checkPermission ?? Geolocator.checkPermission,
       _requestPermission = requestPermission ?? Geolocator.requestPermission,
       _currentPosition = currentPosition ?? _getCurrentPosition;

  final Future<bool> Function() _serviceEnabled;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final Future<Position> Function() _currentPosition;

  static Future<Position> _getCurrentPosition() =>
      Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

  @override
  Future<LocationCoordinates> currentCoordinates() async {
    try {
      if (!await _serviceEnabled()) {
        throw const LocationAccessException(
          LocationAccessIssue.serviceDisabled,
          'Layanan lokasi perangkat nonaktif. Aktifkan GPS lalu coba lagi.',
        );
      }

      var permission = await _checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        throw const LocationAccessException(
          LocationAccessIssue.permissionDeniedForever,
          'Izin lokasi ditolak permanen. Aktifkan izin SiagaNow melalui pengaturan aplikasi.',
        );
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const LocationAccessException(
          LocationAccessIssue.permissionDenied,
          'Izin lokasi ditolak. Izin diperlukan untuk memeriksa peringatan di titik Anda.',
        );
      }

      final position = await _currentPosition();
      final coordinates = LocationCoordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!coordinates.isValid) {
        throw const LocationAccessException(
          LocationAccessIssue.unavailable,
          'Koordinat perangkat tidak valid. Periksa GPS lalu coba lagi.',
        );
      }
      return coordinates;
    } on LocationAccessException {
      rethrow;
    } on TimeoutException {
      throw const LocationAccessException(
        LocationAccessIssue.unavailable,
        'GPS tidak merespons dalam 15 detik. Coba periksa kembali.',
      );
    } on LocationServiceDisabledException {
      throw const LocationAccessException(
        LocationAccessIssue.serviceDisabled,
        'Layanan lokasi perangkat nonaktif. Aktifkan GPS lalu coba lagi.',
      );
    } on PermissionDeniedException {
      throw const LocationAccessException(
        LocationAccessIssue.permissionDenied,
        'Izin lokasi ditolak. Izin diperlukan untuk memeriksa peringatan di titik Anda.',
      );
    } catch (_) {
      throw const LocationAccessException(
        LocationAccessIssue.unavailable,
        'Lokasi perangkat tidak berhasil diperoleh. Coba lagi.',
      );
    }
  }
}
