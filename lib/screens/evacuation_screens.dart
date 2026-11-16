import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/shelter_record.dart';
import '../services/routing_service.dart';
import '../widgets/siaganow_page_background.dart';

class ShelterDetailPage extends StatelessWidget {
  const ShelterDetailPage({
    super.key,
    required this.shelter,
    required this.userLocation,
    required this.routingService,
    required this.loggedIn,
    required this.onSendSafeStatus,
  });

  final ShelterRecord shelter;
  final LatLng? userLocation;
  final RoutingService routingService;
  final bool loggedIn;
  final Future<bool> Function() onSendSafeStatus;

  @override
  Widget build(BuildContext context) {
    final distance = shelter.distanceFrom(userLocation);
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const SiagaNowHeaderBackground(),
        title: const Text('Informasi Shelter'),
      ),
      body: SiagaNowPageBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
          children: [
            Container(
              height: 170,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFDCECE3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_not_supported_outlined, size: 34),
                  SizedBox(height: 8),
                  Text('Foto belum tersedia'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on, color: Color(0xFF01543F)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shelter.name,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(shelter.address),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ShelterStatusChip(
                  icon: Icons.directions_walk,
                  label: distance == null
                      ? 'Jarak belum tersedia'
                      : '${distance.toStringAsFixed(1)} km · garis lurus dari GPS',
                ),
                const _ShelterStatusChip(
                  icon: Icons.schedule,
                  label: 'Estimasi waktu belum tersedia',
                ),
                if (shelter.isVerified)
                  const _ShelterStatusChip(
                    icon: Icons.verified_outlined,
                    label: 'Shelter Resmi',
                  )
                else if (shelter.simulation)
                  const _ShelterStatusChip(
                    icon: Icons.science_outlined,
                    label: 'SIMULASI — BUKAN SHELTER RESMI',
                    warning: true,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Informasi Shelter',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      shelter.isVerified
                          ? 'Sumber: ${shelter.source ?? 'tidak dicantumkan'}. Verifikasi: ${shelter.verifiedAt}.'
                          : shelter.simulation
                          ? 'Data simulasi untuk pengujian. Bukan petunjuk evakuasi resmi.'
                          : 'Sumber atau status verifikasi belum tersedia.',
                    ),
                    if (shelter.capacity != null) ...[
                      const SizedBox(height: 6),
                      Text('Kapasitas tercatat: ${shelter.capacity}'),
                    ],
                    if (shelter.status?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text('Status dari sumber: ${shelter.status}'),
                    ],
                    const SizedBox(height: 6),
                    const Text(
                      'Rute dan waktu tempuh belum disediakan oleh layanan SiagaNow.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Layanan & Fasilitas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FacilityStatusTile(label: 'Logistik'),
                _FacilityStatusTile(label: 'Keamanan'),
                _FacilityStatusTile(label: 'Medis'),
                _FacilityStatusTile(label: 'Toilet'),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF01543F),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: !shelter.hasValidCoordinates
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => EvacuationNavigationPage(
                          shelter: shelter,
                          userLocation: userLocation,
                          routingService: routingService,
                          loggedIn: loggedIn,
                          onSendSafeStatus: onSendSafeStatus,
                        ),
                      ),
                    ),
              icon: const Icon(Icons.near_me_outlined),
              label: const Text('Lihat Rute'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Rute eksternal dan informasi shelter tidak menjamin keselamatan. Ikuti arahan petugas setempat.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Color(0xFF596B60)),
            ),
          ],
        ),
      ),
    );
  }
}

class EvacuationNavigationPage extends StatefulWidget {
  const EvacuationNavigationPage({
    super.key,
    required this.shelter,
    required this.userLocation,
    required this.routingService,
    required this.loggedIn,
    required this.onSendSafeStatus,
  });

  final ShelterRecord shelter;
  final LatLng? userLocation;
  final RoutingService routingService;
  final bool loggedIn;
  final Future<bool> Function() onSendSafeStatus;

  @override
  State<EvacuationNavigationPage> createState() =>
      _EvacuationNavigationPageState();
}

class _EvacuationNavigationPageState extends State<EvacuationNavigationPage> {
  bool loading = false;
  RouteResult? route;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    final from = widget.userLocation;
    final shelter = widget.shelter;
    if (from == null || !shelter.hasValidCoordinates) return;
    setState(() => loading = true);
    try {
      route = await widget.routingService.route(
        from: from,
        to: LatLng(shelter.latitude!, shelter.longitude!),
      );
      if (route != null && route!.polyline.length < 2) {
        route = null;
      }
    } catch (_) {
      route = null;
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _openMaps() async {
    final shelter = widget.shelter;
    if (!shelter.hasValidCoordinates) return;
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${shelter.latitude},${shelter.longitude}',
    });
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aplikasi atau browser peta tidak tersedia.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      flexibleSpace: const SiagaNowHeaderBackground(),
      title: const Text('Navigasi Evakuasi'),
    ),
    body: SiagaNowPageBackground(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF01543F),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.turn_right, color: Colors.white, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.shelter.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (route != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 300,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: route!.polyline.first,
                      initialZoom: 14,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.siaganow.mobile',
                      ),
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: route!.polyline,
                            color: const Color(0xFF19B889),
                            strokeWidth: 5,
                          ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: route!.polyline.first,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.my_location,
                              color: Color(0xFF01543F),
                            ),
                          ),
                          Marker(
                            point: route!.polyline.last,
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.location_on,
                              color: Color(0xFFE94437),
                              size: 34,
                            ),
                          ),
                        ],
                      ),
                      RichAttributionWidget(
                        alignment: AttributionAlignment.bottomRight,
                        attributions: [
                          TextSourceAttribution(
                            '© OpenStreetMap contributors',
                            onTap: () => launchUrl(
                              Uri.parse(
                                'https://www.openstreetmap.org/copyright',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(Icons.map_outlined, size: 52),
                  const SizedBox(height: 8),
                  Text(
                    loading
                        ? 'Memuat informasi rute…'
                        : route == null
                        ? 'Navigasi dalam aplikasi belum tersedia.'
                        : 'Informasi rute dari layanan routing.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (route != null) ...[
                    if (route!.nextInstruction != null)
                      Text(route!.nextInstruction!),
                    Text(
                      route!.distanceMeters == null
                          ? 'Sisa jarak belum tersedia'
                          : 'Sisa jarak ${route!.distanceMeters!.round()} m',
                    ),
                    Text(
                      route!.etaMinutes == null
                          ? 'Estimasi tiba belum tersedia'
                          : 'Estimasi tiba ${route!.etaMinutes} menit',
                    ),
                  ] else
                    const Text(
                      'SiagaNow tidak menghitung jalur atau waktu perjalanan. Buka aplikasi peta dengan tujuan yang sama.',
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: loading ? null : _openMaps,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Buka di Google Maps'),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Rute evakuasi bukan jaminan keselamatan. Ikuti instruksi resmi petugas dan hindari area yang dinyatakan berbahaya.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ShelterArrivalPage(
                  shelter: widget.shelter,
                  userLocation: widget.userLocation,
                  loggedIn: widget.loggedIn,
                  onSendSafeStatus: widget.onSendSafeStatus,
                ),
              ),
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Konfirmasi Kedatangan'),
          ),
        ],
      ),
    ),
  );
}

class ShelterArrivalPage extends StatefulWidget {
  const ShelterArrivalPage({
    super.key,
    required this.shelter,
    required this.userLocation,
    required this.loggedIn,
    required this.onSendSafeStatus,
  });

  final ShelterRecord shelter;
  final LatLng? userLocation;
  final bool loggedIn;
  final Future<bool> Function() onSendSafeStatus;

  @override
  State<ShelterArrivalPage> createState() => _ShelterArrivalPageState();
}

class _ShelterArrivalPageState extends State<ShelterArrivalPage> {
  bool sending = false;
  String? message;

  Future<void> _sendStatus() async {
    setState(() {
      sending = true;
      message = null;
    });
    try {
      final saved = await widget.onSendSafeStatus();
      if (mounted) {
        setState(() {
          message = saved
              ? 'Status aman tersimpan melalui layanan Keluarga Siaga.'
              : 'Status aman tidak tersimpan. Pilih keanggotaan keluarga atau coba lagi.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Status aman gagal dikirim. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final distance = widget.shelter.distanceFrom(widget.userLocation);
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const SiagaNowHeaderBackground(),
        title: Text(widget.shelter.name),
      ),
      body: SiagaNowPageBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 40),
          children: [
            const CircleAvatar(
              radius: 32,
              backgroundColor: Color(0xFF01543F),
              child: Icon(Icons.check, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 14),
            const Text(
              'Konfirmasi Kedatangan',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text('Tujuan: ${widget.shelter.name}', textAlign: TextAlign.center),
            const SizedBox(height: 14),
            Text(widget.shelter.address, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            _ShelterStatusChip(
              icon: Icons.directions_walk,
              label: distance == null
                  ? 'Jarak GPS belum tersedia'
                  : '${distance.toStringAsFixed(1)} km · garis lurus',
            ),
            const SizedBox(height: 12),
            const Text(
              'Konfirmasi ini dilakukan manual. SiagaNow tidak memantau perjalanan atau memastikan Anda telah tiba.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: !widget.loggedIn || sending ? null : _sendStatus,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.health_and_safety_outlined),
              label: Text(
                widget.loggedIn
                    ? 'Kirim Status Aman'
                    : 'Masuk untuk Kirim Status Aman',
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 10),
              Text(message!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShelterStatusChip extends StatelessWidget {
  const _ShelterStatusChip({
    required this.icon,
    required this.label,
    this.warning = false,
  });

  final IconData icon;
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: warning ? const Color(0xFFFFF1D6) : const Color(0xFFE8F4EC),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF01543F)),
        const SizedBox(width: 5),
        Flexible(child: Text(label, style: const TextStyle(fontSize: 11))),
      ],
    ),
  );
}

class _FacilityStatusTile extends StatelessWidget {
  const _FacilityStatusTile({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: 76,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color(0xFFE3E8E5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        const Icon(Icons.help_outline, color: Color(0xFF64736B)),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10),
        ),
        const Text(
          'Tidak ada data',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 8),
        ),
      ],
    ),
  );
}
