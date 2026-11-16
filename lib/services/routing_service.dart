import 'package:latlong2/latlong.dart';

class RouteResult {
  const RouteResult({
    required this.polyline,
    this.distanceMeters,
    this.etaMinutes,
    this.nextInstruction,
    this.nextInstructionDistanceMeters,
  });

  final List<LatLng> polyline;
  final double? distanceMeters;
  final int? etaMinutes;
  final String? nextInstruction;
  final double? nextInstructionDistanceMeters;
}

abstract interface class RoutingService {
  Future<RouteResult?> route({required LatLng from, required LatLng to});
}

/// Default until a licensed routing provider is configured for this app.
class UnavailableRoutingService implements RoutingService {
  const UnavailableRoutingService();

  @override
  Future<RouteResult?> route({
    required LatLng from,
    required LatLng to,
  }) async => null;
}
