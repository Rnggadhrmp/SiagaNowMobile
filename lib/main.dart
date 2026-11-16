import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'dart:io' show File, Platform;

import 'package:path_provider/path_provider.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'location_warning.dart';
import 'services/profile_photo_service.dart';
import 'models/shelter_record.dart';
import 'services/routing_service.dart';
import 'services/donation_repository.dart';
import 'screens/evacuation_screens.dart';
import 'screens/emergency_contacts_page.dart';
import 'screens/donation_page.dart';
import 'widgets/siaganow_page_background.dart';

export 'widgets/siaganow_page_background.dart';
export 'models/shelter_record.dart';
export 'services/routing_service.dart';

const apiOverride = String.fromEnvironment('SIAGANOW_API_URL');
const demoMode = bool.fromEnvironment('SIAGANOW_DEMO_MODE', defaultValue: true);
const shelterSimulationEnabled = bool.fromEnvironment(
  'SIAGANOW_SHELTER_SIMULATION',
  defaultValue: false,
);
const mapTileUrl = String.fromEnvironment(
  'SIAGANOW_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);
const appUserAgent = 'SiagaNowMobile/1.0';
const _onboardingCompleteKey = 'siaganow.onboarding.completed.v1';

WidgetStateProperty<double?> _actionButtonElevation(double restingElevation) =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return 0;
      if (states.contains(WidgetState.pressed)) return restingElevation * 0.45;
      return restingElevation;
    });

const _actionButtonShadow = WidgetStatePropertyAll<Color>(Color(0x4D075B49));

class _AnimatedTabStack extends StatelessWidget {
  const _AnimatedTabStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 320);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < children.length; i++)
          Positioned.fill(
            key: ValueKey('tab-$i'),
            child: AnimatedSlide(
              duration: duration,
              curve: Curves.easeInOutCubic,
              offset: i == index ? Offset.zero : const Offset(.018, 0),
              child: AnimatedOpacity(
                duration: duration,
                curve: Curves.easeInOutCubic,
                opacity: i == index ? 1 : 0,
                child: IgnorePointer(
                  ignoring: i != index,
                  child: ExcludeSemantics(
                    excluding: i != index,
                    child: TickerMode(enabled: i == index, child: children[i]),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _GlassNavigationBar extends StatelessWidget {
  const _GlassNavigationBar({required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  static const _items =
      <
        ({
          String label,
          String semanticLabel,
          IconData icon,
          IconData activeIcon,
        })
      >[
        (
          label: 'Beranda',
          semanticLabel: 'Beranda',
          icon: Icons.home_outlined,
          activeIcon: Icons.home,
        ),
        (
          label: 'Rute',
          semanticLabel: 'Rute Evakuasi',
          icon: Icons.map_outlined,
          activeIcon: Icons.map,
        ),
        (
          label: 'Laporan',
          semanticLabel: 'Laporkan Bencana',
          icon: Icons.add_location_alt_outlined,
          activeIcon: Icons.add_location_alt,
        ),
        (
          label: 'Donasi',
          semanticLabel: 'Donasi',
          icon: Icons.mail_outline_rounded,
          activeIcon: Icons.mail_rounded,
        ),
        (
          label: 'Darurat',
          semanticLabel: 'Layanan Darurat',
          icon: Icons.call_outlined,
          activeIcon: Icons.call,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 11, sigmaY: 11),
            child: Container(
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xC9F7FFF9),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: const Color(0x99FFFFFF), width: 1),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26075B49),
                    blurRadius: 18,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Expanded(
                      child: _GlassNavigationDestination(
                        key: ValueKey('nav-destination-$i'),
                        item: _items[i],
                        selected: i == index,
                        reduceMotion: reduceMotion,
                        onTap: () => onSelected(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassNavigationDestination extends StatelessWidget {
  const _GlassNavigationDestination({
    super.key,
    required this.item,
    required this.selected,
    required this.reduceMotion,
    required this.onTap,
  });

  final ({
    String label,
    String semanticLabel,
    IconData icon,
    IconData activeIcon,
  })
  item;
  final bool selected;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 300);
    return Semantics(
      button: true,
      selected: selected,
      label: item.semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeInOutCubic,
                  width: selected ? 50 : 42,
                  height: 31,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF01543F)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: animation, child: child),
                      ),
                      child: Icon(
                        selected ? item.activeIcon : item.icon,
                        key: ValueKey(selected),
                        size: 23,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF45584E),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: duration,
                  curve: Curves.easeInOutCubic,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.1,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? const Color(0xFF01543F)
                        : const Color(0xFF45584E),
                  ),
                  child: Text(item.label, maxLines: 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SiagaNowPageTransitionsBuilder extends PageTransitionsBuilder {
  const _SiagaNowPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.025, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

class _LoadingSkeleton extends StatefulWidget {
  const _LoadingSkeleton({this.rows = 3});
  final int rows;

  @override
  State<_LoadingSkeleton> createState() => _LoadingSkeletonState();
}

class _LoadingSkeletonState extends State<_LoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  );

  @override
  void initState() {
    super.initState();
    _shimmer.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shimmer.stop();
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _shimmer,
    builder: (context, _) => ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) {
        if (MediaQuery.disableAnimationsOf(context)) {
          return const LinearGradient(
            colors: [Colors.transparent, Colors.transparent],
          ).createShader(bounds);
        }
        final shift = _shimmer.value * 2.4 - 1.2;
        return LinearGradient(
          begin: Alignment(shift - .7, 0),
          end: Alignment(shift + .7, 0),
          colors: const [
            Colors.transparent,
            Color(0x66FFFFFF),
            Colors.transparent,
          ],
          stops: const [0, .5, 1],
        ).createShader(bounds);
      },
      child: Column(
        children: List.generate(
          widget.rows,
          (index) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              height: index == 0 ? 88 : 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .78),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0x334C8B70)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 13,
                    width: index == 0 ? 150 : 112,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6E9DE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 10,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE4EFE8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  if (index == 0) ...[
                    const SizedBox(height: 7),
                    Container(
                      height: 10,
                      width: 190,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4EFE8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

const _defaultMapLatitude = String.fromEnvironment(
  'SIAGANOW_DEFAULT_LATITUDE',
  defaultValue: '-0.9471',
);
const _defaultMapLongitude = String.fromEnvironment(
  'SIAGANOW_DEFAULT_LONGITUDE',
  defaultValue: '100.4172',
);

String get apiBase => apiOverride.isNotEmpty
    ? apiOverride.replaceFirst(RegExp(r'/+$'), '')
    : (kIsWeb ? 'http://127.0.0.1:8000/api' : 'http://10.0.2.2:8000/api');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FamilyReminderService.initialize();
  runApp(const SiagaNowApp());
}

class FamilyReminderService {
  FamilyReminderService._();
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static String timezoneName = 'UTC';
  static bool initialized = false;

  static Future<void> initialize() async {
    if (initialized) return;
    tz_data.initializeTimeZones();
    try {
      timezoneName = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (_) {
      timezoneName = 'UTC';
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    initialized = true;
  }

  static int notificationId(int memberId) =>
      100000 + memberId.abs() % 1000000000;

  static Future<bool> requestPermission() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? true;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }

  static Future<void> schedule({
    required int memberId,
    required String memberName,
    required bool enabled,
    required int frequencyHours,
    required DateTime? nextReminderAt,
    required String timezone,
  }) async {
    await initialize();
    final id = notificationId(memberId);
    if (!enabled || nextReminderAt == null) {
      await _plugin.cancel(id);
      return;
    }
    final location = tz.getLocation(timezone);
    final scheduled = tz.TZDateTime.from(nextReminderAt.toUtc(), location);
    if (!scheduled.isAfter(tz.TZDateTime.now(location))) {
      throw const ApiException(
        'Waktu pengingat berikutnya sudah lewat. Segarkan data dan coba lagi.',
      );
    }
    final repeat = switch (frequencyHours) {
      24 => DateTimeComponents.time,
      168 => DateTimeComponents.dayOfWeekAndTime,
      _ => null,
    };
    await _plugin.zonedSchedule(
      id,
      'Pengingat Keluarga Siaga',
      'Periksa kabar $memberName dan konfirmasikan kondisi Anda di SiagaNow.',
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'family_safety_reminders',
          'Pengingat keluarga',
          channelDescription: 'Pengingat lokal untuk check-in keluarga.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: repeat,
      payload: 'family-member:$memberId',
    );
  }
}

class ApiService {
  ApiService(this.storage, {http.Client? client, this.tokenReader})
    : _client = client ?? http.Client();
  final FlutterSecureStorage storage;
  final http.Client _client;
  final Future<String?> Function()? tokenReader;

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$apiBase/${path.replaceFirst(RegExp(r'^/+'), '')}');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _request(
    Future<http.Response> Function(Map<String, String>) send,
  ) async {
    final token = tokenReader == null
        ? await storage.read(key: 'token')
        : await tokenReader!();
    final headers = <String, String>{
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    try {
      final response = await send(headers).timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) await storage.delete(key: 'token');
      dynamic decoded;
      try {
        decoded = response.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(response.body);
      } on FormatException {
        throw const ApiException(
          'Server mengirim respons yang tidak bisa dibaca.',
        );
      }
      if (decoded is! Map) {
        throw const ApiException(
          'Server mengirim format data yang tidak sesuai.',
        );
      }
      final body = Map<String, dynamic>.from(decoded);
      if (response.statusCode >= 400) {
        final errors = body['errors'];
        final details = errors is Map
            ? errors.values.expand((v) => v is List ? v : [v]).join('\n')
            : null;
        throw ApiException(
          (details?.isNotEmpty == true
                  ? details
                  : body['message']?.toString()) ??
              'Permintaan gagal (${response.statusCode}).',
          response.statusCode,
        );
      }
      return body;
    } on ApiException {
      rethrow;
    } on http.ClientException {
      throw const ApiException(
        'Tidak dapat terhubung ke server. Periksa alamat API dan jaringan.',
      );
    } on TimeoutException {
      throw const ApiException('Server terlalu lama merespons. Coba lagi.');
    }
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      _request((headers) => _client.get(_uri(path, query), headers: headers));

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data) =>
      _request(
        (headers) => _client.post(
          _uri(path),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode(data),
        ),
      );

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> data) =>
      _request(
        (headers) => _client.put(
          _uri(path),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode(data),
        ),
      );

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> data) =>
      _request(
        (headers) => _client.patch(
          _uri(path),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode(data),
        ),
      );

  Future<Map<String, dynamic>> delete(String path) =>
      _request((headers) => _client.delete(_uri(path), headers: headers));

  Future<Map<String, dynamic>> uploadReport(
    Map<String, dynamic> data,
    List<PlatformFile> files,
  ) async => _request((headers) async {
    final request = http.MultipartRequest('POST', _uri('reports'))
      ..headers.addAll(headers);
    for (final entry in data.entries) {
      request.fields[entry.key] = entry.value.toString();
    }
    for (final file in files) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'evidence[]',
          await file.readAsBytes(),
          filename: file.name,
        ),
      );
    }
    return _client.send(request).then(http.Response.fromStream);
  });
}

class ApiException implements Exception {
  const ApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.address,
  });
  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String? address;
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: int.tryParse('${json['id']}') ?? 0,
    name: json['name']?.toString() ?? '',
    email: json['email']?.toString(),
    phone: json['phone']?.toString(),
    address: json['address']?.toString(),
  );
}

class ReportReceipt {
  const ReportReceipt(
    this.id,
    this.status,
    this.message, {
    this.shelter,
    this.aiAnalysis,
  });
  final Object? id;
  final String status;
  final String message;
  final ReportShelterInfo? shelter;
  final ReportAiAnalysis? aiAnalysis;

  factory ReportReceipt.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id == null || id.toString().trim().isEmpty) {
      throw const ApiException(
        'Server belum mengonfirmasi bahwa laporan berhasil disimpan.',
      );
    }
    final status = json['status']?.toString() ?? 'submitted';
    return ReportReceipt(
      id,
      status,
      'Laporan #${json['id'] ?? '—'} tersimpan: $status.',
      shelter: ReportShelterInfo.fromResponse(json),
      aiAnalysis: ReportAiAnalysis.fromJson(json['ai_analysis']),
    );
  }
}

class ReportAiAnalysis {
  const ReportAiAnalysis({
    required this.status,
    this.verificationStatus,
    this.serviceStatus,
  });
  final String status;
  final String? verificationStatus;
  final String? serviceStatus;

  factory ReportAiAnalysis.fromJson(Object? value) {
    final json = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    final status = switch (json['status']?.toString()) {
      'processing' => 'processing',
      'completed' => 'completed',
      'failed' => 'failed',
      _ => 'pending',
    };
    final verification = switch (json['verification_status']?.toString()) {
      'verified' => 'verified',
      'rejected' => 'rejected',
      _ => 'pending',
    };
    return ReportAiAnalysis(
      status: status,
      verificationStatus: verification,
      serviceStatus: json['service_status']?.toString(),
    );
  }

  String get label => switch (status) {
    'processing' => 'Sedang dianalisis',
    'completed' => 'Analisis selesai',
    'failed' => 'Analisis belum tersedia',
    _ =>
      serviceStatus == 'not_configured'
          ? 'Model YOLO belum terhubung'
          : 'Menunggu analisis',
  };

  String get verificationLabel => switch (verificationStatus) {
    'verified' => 'Sudah diverifikasi admin',
    'rejected' => 'Ditandai tidak sesuai oleh admin',
    _ => 'Menunggu verifikasi admin',
  };
}

class _ReportAiStatusCard extends StatelessWidget {
  const _ReportAiStatusCard({required this.analysis});
  final ReportAiAnalysis analysis;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.auto_awesome_outlined),
      title: const Text('Analisis AI'),
      subtitle: Text(
        '${analysis.label} · ${analysis.verificationLabel}. Hasil AI bukan keputusan resmi; verifikasi admin menentukan tindak lanjut.',
      ),
      isThreeLine: true,
    ),
  );
}

class ReportShelterInfo {
  const ReportShelterInfo({
    required this.name,
    required this.location,
    this.simulation = false,
    this.distanceKm,
  });

  final String name;
  final String location;
  final bool simulation;
  final double? distanceKm;

  factory ReportShelterInfo.localSimulation(ShelterRecord shelter, double km) =>
      ReportShelterInfo(
        name: shelter.name,
        location: shelter.address,
        simulation: true,
        distanceKm: km,
      );

  static ReportShelterInfo? fromResponse(Map<String, dynamic> response) {
    final raw = response['shelter'] ?? response['recommended_shelter'];
    if (raw is! Map) return null;
    final shelter = Map<String, dynamic>.from(raw);
    final source = shelter['source']?.toString().toLowerCase() ?? '';
    final type = shelter['data_type']?.toString().toLowerCase() ?? '';
    final verifiedAt = shelter['verified_at']?.toString();
    final isSimulation =
        shelter['simulation'] == true ||
        type == 'simulation' ||
        type == 'simulated' ||
        source.contains('simulasi');
    final isVerified =
        shelter['verified'] == true ||
        (type == 'actual' && verifiedAt?.isNotEmpty == true);
    final name = shelter['name']?.toString().trim() ?? '';
    if (isSimulation || !isVerified || name.isEmpty) return null;

    final location =
        (shelter['address'] ??
                shelter['location_label'] ??
                shelter['location'] ??
                'Lokasi terverifikasi')
            .toString()
            .trim();
    return ReportShelterInfo(
      name: name,
      location: location.isEmpty ? 'Lokasi terverifikasi' : location,
    );
  }
}

class WeatherPeriod {
  const WeatherPeriod({
    this.localDateTime,
    this.temperature,
    this.condition,
    this.humidity,
    this.rainMm,
    this.windKmh,
  });
  final String? localDateTime;
  final num? temperature;
  final String? condition;
  final int? humidity;
  final num? rainMm;
  final num? windKmh;
  factory WeatherPeriod.fromJson(Map<String, dynamic> json) => WeatherPeriod(
    localDateTime: json['local_datetime']?.toString(),
    temperature: num.tryParse('${json['temperature']}'),
    condition: json['condition']?.toString(),
    humidity: int.tryParse('${json['humidity']}'),
    rainMm: num.tryParse('${json['rain_mm']}'),
    windKmh: num.tryParse('${json['wind_kmh']}'),
  );
}

IconData weatherIconForCondition(String? condition) {
  final value = (condition ?? '').toLowerCase();
  if (value.contains('petir') || value.contains('guntur')) {
    return Icons.thunderstorm_rounded;
  }
  if (value.contains('hujan')) return Icons.umbrella_rounded;
  if (value.contains('kabut') || value.contains('asap')) {
    return Icons.foggy;
  }
  if (value.contains('cerah') && value.contains('awan')) {
    return Icons.wb_cloudy_rounded;
  }
  if (value.contains('cerah')) return Icons.wb_sunny_rounded;
  if (value.contains('awan') || value.contains('berawan')) {
    return Icons.cloud_rounded;
  }
  return Icons.cloud_outlined;
}

abstract interface class OnboardingProgressStore {
  Future<bool> isComplete();
  Future<void> markComplete();
}

class SharedPreferencesOnboardingStore implements OnboardingProgressStore {
  @override
  Future<bool> isComplete() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_onboardingCompleteKey) ?? false;
  }

  @override
  Future<void> markComplete() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_onboardingCompleteKey, true);
  }
}

class SiagaNowApp extends StatefulWidget {
  const SiagaNowApp({
    super.key,
    this.onboardingStore,
    this.tokenReader,
    this.apiService,
    this.routingService,
  });

  final OnboardingProgressStore? onboardingStore;
  final Future<String?> Function()? tokenReader;
  final ApiService? apiService;
  final RoutingService? routingService;

  @override
  State<SiagaNowApp> createState() => _SiagaNowAppState();
}

class _SiagaNowAppState extends State<SiagaNowApp> {
  final storage = const FlutterSecureStorage();
  late final OnboardingProgressStore onboardingStore =
      widget.onboardingStore ?? SharedPreferencesOnboardingStore();
  final navigatorKey = GlobalKey<NavigatorState>();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final api = widget.apiService ?? ApiService(storage);
  int tab = 0;
  String? userName;
  bool booting = true;
  bool onboardingPending = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    var onboardingComplete = false;
    try {
      onboardingComplete = await onboardingStore.isComplete();
    } catch (_) {
      onboardingComplete = false;
    }

    String? token;
    try {
      token = widget.tokenReader == null
          ? await storage.read(key: 'token')
          : await widget.tokenReader!();
    } catch (_) {
      token = null;
    }
    if (!onboardingComplete && token?.isNotEmpty == true) {
      onboardingComplete = true;
      try {
        await onboardingStore.markComplete();
      } catch (_) {
        // Keep an existing signed-in user on the existing startup path.
      }
    }
    onboardingPending = !onboardingComplete && token?.isNotEmpty != true;

    if (token?.isNotEmpty == true) {
      try {
        final me = await api.get('user');
        final profile = UserProfile.fromJson(
          Map<String, dynamic>.from(me['data'] as Map),
        );
        userName = profile.name;
      } on ApiException catch (e) {
        if (e.statusCode == 401 || e.statusCode == 403) {
          await storage.delete(key: 'token');
        }
      } catch (_) {
        /* Keep a possibly valid session during temporary outages. */
      }
    }
    if (mounted) setState(() => booting = false);
  }

  Future<void> _completeOnboarding() async {
    try {
      await onboardingStore.markComplete();
    } catch (_) {
      // Continue into the app if local preferences are temporarily unavailable.
    }
    if (mounted) setState(() => onboardingPending = false);
  }

  Future<void> _auth() async {
    final navigatorContext = navigatorKey.currentContext;
    if (navigatorContext == null) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: navigatorContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
          child: ColoredBox(
            color: const Color(0xFFF7FFF9),
            child: AuthSheet(api: api),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => userName = result['name']?.toString());
    }
  }

  Future<void> _requireLogin() async {
    if (mounted) setState(() => userName = null);
    await _auth();
  }

  Future<void> _logout() async {
    var revoked = true;
    try {
      await api.post('logout', {});
    } catch (_) {
      revoked = false;
    }
    await storage.delete(key: 'token');
    if (mounted) {
      setState(() => userName = null);
      messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            revoked ? 'Anda telah keluar.' : 'Anda telah keluar di perangkat ini. Pencabutan token server belum dapat dikonfirmasi.',
          ),
        ),
      );
    }
  }

  Future<bool> _sendFamilySafeStatus() async {
    if (userName == null) return false;
    final response = await api.get('family-memberships');
    final memberships =
        (response['data'] is List ? response['data'] as List : [])
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .toList();
    if (memberships.isEmpty) return false;
    Map<String, dynamic>? membership;
    if (memberships.length == 1) {
      membership = memberships.single;
    } else {
      final context = navigatorKey.currentContext;
      if (context == null || !context.mounted) return false;
      membership = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Pilih keluarga'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: memberships.map((value) {
                final group = value['group'] is Map
                    ? Map<String, dynamic>.from(value['group'] as Map)
                    : const <String, dynamic>{};
                return ListTile(
                  title: Text('${group['name'] ?? 'Keluarga Siaga'}'),
                  subtitle: Text('${value['name'] ?? 'Anggota'}'),
                  onTap: () => Navigator.pop(dialogContext, value),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal'),
            ),
          ],
        ),
      );
    }
    if (membership == null) return false;
    final memberId = int.tryParse('${membership['id']}');
    if (memberId == null) return false;
    final key = 'family_checkin_pending_$memberId';
    var requestId = await storage.read(key: key);
    if (requestId == null) {
      requestId = List.generate(
        32,
        (_) => Random.secure().nextInt(16).toRadixString(16),
      ).join();
      await storage.write(key: key, value: requestId);
    }
    await api.post('family-members/$memberId/check-in', {
      'request_id': requestId,
    });
    await storage.delete(key: key);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    const forest = Color(0xFF075B49);
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      title: 'SiagaNow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: forest,
          surface: const Color(0xFFEFF8F2),
        ),
        scaffoldBackgroundColor: const Color(0xFFD3F1E0),
        fontFamily: 'Poppins',
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFFCDEBDD),
          foregroundColor: const Color(0xFF15392F),
          elevation: 0,
          toolbarHeight: 90,
        ),
        cardTheme: CardThemeData(
          color: SiagaNowSurfaceTokens.info,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              SiagaNowSurfaceTokens.cardRadius,
            ),
            side: const BorderSide(color: SiagaNowSurfaceTokens.border),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xC7F7FFF9),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              SiagaNowSurfaceTokens.dialogRadius,
            ),
            side: const BorderSide(color: SiagaNowSurfaceTokens.border),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xC7F7FFF9),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFBCD4C7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFBCD4C7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: forest, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style:
              FilledButton.styleFrom(
                backgroundColor: forest,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ).copyWith(
                elevation: _actionButtonElevation(3),
                shadowColor: _actionButtonShadow,
              ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            elevation: _actionButtonElevation(1.5),
            shadowColor: _actionButtonShadow,
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            elevation: _actionButtonElevation(2),
            shadowColor: _actionButtonShadow,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom().copyWith(
            elevation: _actionButtonElevation(3),
            shadowColor: _actionButtonShadow,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom().copyWith(
            elevation: _actionButtonElevation(2),
            shadowColor: _actionButtonShadow,
          ),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: _SiagaNowPageTransitionsBuilder(),
            TargetPlatform.iOS: _SiagaNowPageTransitionsBuilder(),
          },
        ),
      ),
      home: booting
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : onboardingPending
          ? SiagaNowIntro(onFinished: _completeOnboarding)
          : Scaffold(
              extendBody: true,
              appBar: AppBar(
                backgroundColor: const Color(0xFFCDEBDD),
                toolbarHeight: 92,
                flexibleSpace: const SiagaNowHeaderBackground(),
                title: Row(
                  children: [
                    Image.asset(
                      'assets/images/siaganow-nature-emblem.png',
                      width: 46,
                      height: 38,
                      fit: BoxFit.contain,
                      semanticLabel: 'Lambang SiagaNow',
                    ),
                    const SizedBox(width: 6),
                    const Flexible(
                      child: Text(
                        'SiagaNow',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: userName == null ? 'Masuk atau daftar' : 'Profil',
                    onPressed: () => userName == null
                        ? _auth()
                        : navigatorKey.currentState!.push(
                            MaterialPageRoute(
                              builder: (_) => ProfilePage(
                                api: api,
                                onLogin: _requireLogin,
                                onLogout: _logout,
                              ),
                            ),
                          ),
                    icon: CircleAvatar(
                      radius: 17,
                      backgroundColor: const Color(0xFF075B49),
                      child: Icon(
                        userName == null ? Icons.person_outline : Icons.person,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: SiagaNowPageBackground(
                showTop: false,
                child: _AnimatedTabStack(
                  index: tab,
                  children: [
                    HomePage(
                      api: api,
                      onSelectTab: (i) => setState(() => tab = i),
                      onOpenNews: () => navigatorKey.currentState!.push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(
                              flexibleSpace: const SiagaNowHeaderBackground(),
                              title: const Text('Halaman Berita'),
                            ),
                            body: SiagaNowPageBackground(
                              child: NewsPage(api: api),
                            ),
                          ),
                        ),
                      ),
                      onOpenFamily: () => navigatorKey.currentState!.push(
                        MaterialPageRoute(
                          builder: (_) => FamilyPage(
                            api: api,
                            loggedIn: userName != null,
                            onLogin: _requireLogin,
                          ),
                        ),
                      ),
                    ),
                    ShelterPage(
                      api: api,
                      loggedIn: userName != null,
                      onSendSafeStatus: _sendFamilySafeStatus,
                      routingService:
                          widget.routingService ??
                          const UnavailableRoutingService(),
                    ),
                    ReportPage(
                      api: api,
                      loggedIn: userName != null,
                      onLogin: _requireLogin,
                      onHome: () => setState(() => tab = 0),
                    ),
                    DonationPage(
                      repository: ApiDonationRepository(
                        fetchCampaigns: () => api.get('donation-campaigns'),
                      ),
                      embedded: true,
                      loggedIn: userName != null,
                      onLogin: _requireLogin,
                    ),
                    const EmergencyContactsPage(embedded: true),
                  ],
                ),
              ),
              bottomNavigationBar: _GlassNavigationBar(
                index: tab,
                onSelected: (i) => setState(() => tab = i),
              ),
            ),
    );
  }
}

class SiagaNowIntro extends StatefulWidget {
  const SiagaNowIntro({super.key, required this.onFinished});

  final Future<void> Function() onFinished;

  @override
  State<SiagaNowIntro> createState() => _SiagaNowIntroState();
}

class _SiagaNowIntroState extends State<SiagaNowIntro> {
  static const _forest = Color(0xFF075B49);
  static const _mint = Color(0xFFD3F1E0);

  static const _pages = <_IntroContent>[
    _IntroContent(
      title: 'Kenali Risiko di Sekitarmu',
      description: 'Kenali informasi dan peringatan bencana yang tersedia sebagai bekal memahami situasi di sekitarmu.',
      illustration: _IntroIllustration.risk,
    ),
    _IntroContent(
      title: 'Informasi dan Peta Bencana',
      description: 'Akses informasi cuaca, peta, dan lokasi terkait kebencanaan. Ketersediaan lokasi mengikuti data yang dapat ditampilkan aplikasi.',
      illustration: _IntroIllustration.map,
    ),
    _IntroContent(
      title: 'Keluarga Siaga',
      description: 'Ajak keluarga menyiapkan informasi penting dan tetap saling memberi kabar melalui fitur Family Siaga.',
      illustration: _IntroIllustration.family,
    ),
  ];

  final _pageController = PageController();
  int _currentPage = 0;
  bool _showSplash = true;
  bool _finishing = false;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _splashTimer = Timer(const Duration(milliseconds: 1150), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    await widget.onFinished();
  }

  Future<void> _next() async {
    if (_currentPage == _pages.length - 1) {
      await _finish();
      return;
    }
    await _pageController.animateToPage(
      _currentPage + 1,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _mint,
    body: Stack(
      fit: StackFit.expand,
      children: [
        const SiagaNowColorOverlay(),
        SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: _showSplash
                ? const _IntroSplash(key: ValueKey('intro-splash'))
                : _buildOnboarding(key: const ValueKey('intro-pages')),
          ),
        ),
      ],
    ),
  );

  Widget _buildOnboarding({required Key key}) => Padding(
    key: key,
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    child: Column(
      children: [
        SizedBox(
          height: 52,
          child: Row(
            children: [
              Text(
                '${(_currentPage + 1).toString().padLeft(2, '0')} / ${_pages.length.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: _forest,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_currentPage + 1) / _pages.length,
                    minHeight: 4,
                    backgroundColor: const Color(0xFFB8D8C5),
                    valueColor: const AlwaysStoppedAnimation<Color>(_forest),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _finishing ? null : _finish,
                style: TextButton.styleFrom(
                  foregroundColor: _forest,
                  minimumSize: const Size(64, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text('Lewati'),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            itemCount: _pages.length,
            onPageChanged: (page) => setState(() => _currentPage = page),
            itemBuilder: (context, index) => _IntroPage(content: _pages[index]),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_pages.length, (index) {
            final selected = index == _currentPage;
            return Semantics(
              label: 'Halaman ${index + 1} dari ${_pages.length}',
              selected: selected,
              button: true,
              child: InkWell(
                onTap: _finishing
                    ? null
                    : () => _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOutCubic,
                      ),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: selected ? 24 : 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: selected ? _forest : const Color(0xFF9DBEAA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _finishing ? null : _next,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _currentPage == _pages.length - 1
                      ? 'Mulai Sekarang'
                      : 'Selanjutnya',
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _IntroSplash extends StatelessWidget {
  const _IntroSplash({super.key});

  static const _forest = Color(0xFF075B49);

  @override
  Widget build(BuildContext context) => Center(
    key: key,
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.94, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/siaganow-nature-emblem.png',
              width: 132,
              height: 88,
              fit: BoxFit.contain,
              semanticLabel: 'Logo resmi SiagaNow',
            ),
            const SizedBox(height: 14),
            const Text(
              'SiagaNow',
              style: TextStyle(
                color: _forest,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Siap Menghadapi Bencana, Lindungi Keluarga',
              textAlign: TextAlign.center,
              style: TextStyle(color: _forest, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 26),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: _forest,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

enum _IntroIllustration { risk, map, family }

class _IntroContent {
  const _IntroContent({
    required this.title,
    required this.description,
    required this.illustration,
  });

  final String title;
  final String description;
  final _IntroIllustration illustration;
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({required this.content});

  static const _forest = Color(0xFF075B49);
  static const _ink = Color(0xFF15392F);
  static const _surface = Color(0xFFEFF8F2);

  final _IntroContent content;

  Widget _illustration(double height) {
    switch (content.illustration) {
      case _IntroIllustration.risk:
        return Image.asset(
          'assets/illustrations/home_flood_warning.png',
          height: height,
          fit: BoxFit.contain,
          semanticLabel: 'Ilustrasi peringatan banjir',
        );
      case _IntroIllustration.map:
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/landscape_background.png',
                  fit: BoxFit.cover,
                  semanticLabel: 'Ilustrasi lanskap, bukan peta lokasi',
                ),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: const BoxDecoration(
                      color: Color(0xF2EFF8F2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.map_outlined,
                      size: 62,
                      color: _forest,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      case _IntroIllustration.family:
        return SizedBox(
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                'assets/illustrations/login_shield_landscape.png',
                height: height,
                fit: BoxFit.contain,
                semanticLabel: 'Ilustrasi perlindungan dan kesiapsiagaan',
              ),
              Positioned(
                right: 14,
                bottom: 10,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: _surface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.family_restroom_outlined,
                    size: 34,
                    color: _forest,
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final artHeight = (constraints.maxHeight * 0.43).clamp(175.0, 270.0);
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 10, 2, 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: artHeight,
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SiagaNowSurfaceTokens.mintInfo,
                    borderRadius: BorderRadius.circular(
                      SiagaNowSurfaceTokens.panelRadius,
                    ),
                    border: Border.all(color: SiagaNowSurfaceTokens.border),
                  ),
                  child: Center(child: _illustration(artHeight - 28)),
                ),
                const SizedBox(height: 22),
                Text(
                  content.title,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 25,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  content.description,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    color: Color(0xFF355249),
                    fontSize: 16,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.api,
    required this.onSelectTab,
    required this.onOpenNews,
    required this.onOpenFamily,
    this.locationProvider,
  });
  final ApiService api;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onOpenNews;
  final VoidCallback onOpenFamily;
  final WarningLocationProvider? locationProvider;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? data;
  List<dynamic> news = [];
  String? newsDataType;
  List<WeatherPeriod> forecasts = [];
  bool loading = true;
  String? error;
  Map<String, dynamic>? locationWarning;
  bool locationWarningLoading = false;
  String? locationWarningError;
  LocationAccessIssue? locationAccessIssue;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      data = await widget.api.get('home');
      final forecast = data?['weather_forecast'];
      final periods = forecast is Map ? forecast['forecasts'] : null;
      forecasts = periods is List
          ? periods
                .whereType<Map>()
                .map(
                  (p) => WeatherPeriod.fromJson(Map<String, dynamic>.from(p)),
                )
                .toList()
          : [];
      final newsResponse = await widget.api.get('news');
      news = newsResponse['data'] is List ? newsResponse['data'] as List : [];
      newsDataType = newsResponse['data_type']?.toString();
    } catch (e) {
      error = e is ApiException
          ? e.message
          : 'Informasi aktual tidak tersedia.';
      if (demoMode && data == null) {
        data = {
          'data_type': 'unavailable',
          'weather': {},
          'statistics': {},
          'warning': {'status': 'unknown', 'active': false, 'message': error},
        };
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> checkLocationWarning() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Periksa peringatan di lokasi Anda'),
        content: const Text(
          'SiagaNow akan menggunakan lokasi perangkat untuk satu kali pemeriksaan cakupan peringatan cuaca. Lokasi tidak digunakan untuk pelacakan latar belakang.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;

    setState(() {
      locationWarningLoading = true;
      locationWarningError = null;
      locationAccessIssue = null;
      locationWarning = {
        'status': 'unknown',
        'message': 'Memeriksa peringatan pada koordinat perangkat…',
        'source': 'BMKG',
      };
    });

    try {
      final coordinates =
          await (widget.locationProvider ?? GeolocatorWarningLocationProvider())
              .currentCoordinates();
      if (!coordinates.isValid) {
        throw const LocationAccessException(
          LocationAccessIssue.unavailable,
          'Koordinat perangkat tidak valid. Coba lagi.',
        );
      }

      final response = await widget.api.get(
        'weather-warning',
        query: {
          'lat': coordinates.latitude.toString(),
          'lng': coordinates.longitude.toString(),
        },
      );
      final status = response['status']?.toString();
      if (!['warning_found', 'no_warning_found', 'unknown'].contains(status)) {
        throw const ApiException(
          'Respons status peringatan tidak lengkap. Status tetap belum diketahui.',
        );
      }

      locationWarning = Map<String, dynamic>.from(response)
        ..['active'] = status == 'warning_found';
      if (status == 'unknown') {
        locationWarningError = response['message']?.toString();
      }
    } on LocationAccessException catch (exception) {
      locationAccessIssue = exception.issue;
      locationWarningError = exception.message;
      locationWarning = {
        'status': 'unknown',
        'message': exception.message,
        'source': 'BMKG',
      };
    } on ApiException catch (exception) {
      locationWarningError = exception.message;
      locationWarning = {
        'status': 'unknown',
        'message': exception.message,
        'source': 'BMKG',
      };
    } catch (_) {
      locationWarningError =
          'Pemeriksaan gagal. Status peringatan tetap belum diketahui.';
      locationWarning = {
        'status': 'unknown',
        'message': locationWarningError,
        'source': 'BMKG',
      };
    } finally {
      if (mounted) setState(() => locationWarningLoading = false);
    }
  }

  Future<void> openLocationSettings() async {
    if (locationAccessIssue == LocationAccessIssue.permissionDeniedForever) {
      await Geolocator.openAppSettings();
    } else if (locationAccessIssue == LocationAccessIssue.serviceDisabled) {
      await Geolocator.openLocationSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final weather = data?['weather'];
    final stats = data?['statistics'];
    final isDemo =
        data?['data_type'] == 'simulation' || (data == null && demoMode);
    if (loading) {
      return RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          children: const [_LoadingSkeleton(rows: 4)],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 112),
        children: [
          const SizedBox(height: 4),
          Text(
            'SIAGA UNTUK HARI INI',
            style: TextStyle(
              color: const Color(0xFF075B49),
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          if (news.isNotEmpty)
            _HomeNewsCard(
              item: Map<String, dynamic>.from(news.first as Map),
              simulation: newsDataType == 'simulation',
              onTap: widget.onOpenNews,
            )
          else
            _HomeNewsEmpty(onTap: widget.onOpenNews),
          const SizedBox(height: 18),
          _WarningStatusCard(
            warning: locationWarning ?? data?['warning'],
            loading: loading || locationWarningLoading,
            error: locationWarningError ?? error,
            checkingLocation: locationWarningLoading,
            onCheckLocation: checkLocationWarning,
            onOpenSettings:
                locationAccessIssue ==
                        LocationAccessIssue.permissionDeniedForever ||
                    locationAccessIssue == LocationAccessIssue.serviceDisabled
                ? openLocationSettings
                : null,
          ),
          const SizedBox(height: 18),
          _AiFloodDetectionCard(value: data?['flood_detection']),
          const SizedBox(height: 18),
          Material(
            color: const Color(0xFF087354),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: widget.onOpenFamily,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 17,
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFD0F1DF),
                      child: Icon(
                        Icons.family_restroom,
                        color: Color(0xFF075B49),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Keluarga Siaga',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Persiapan keluarga sebelum bencana',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _HomeWeatherCard(
            weather: weather,
            isDemo: isDemo,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WeatherDetailPage(
                  weather: weather,
                  forecasts: forecasts,
                  warning: data?['warning'],
                ),
              ),
            ),
          ),
          if (stats is Map) ...[
            const SizedBox(height: 12),
            _HomeStatsCard(values: Map<String, dynamic>.from(stats)),
          ],
          const SizedBox(height: 18),
          const Text(
            'Prakiraan cuaca',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          Text(
            (data?['weather_forecast']?['message'] ??
                    'Prakiraan mendatang belum tersedia dari API.')
                .toString(),
            style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
          ),
          if (forecasts.isNotEmpty)
            SizedBox(
              height: 126,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: forecasts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final period = forecasts[index];
                  return Container(
                    width: 128,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SiagaNowSurfaceTokens.info,
                      borderRadius: BorderRadius.circular(
                        SiagaNowSurfaceTokens.cardRadius,
                      ),
                      border: Border.all(color: SiagaNowSurfaceTokens.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(
                          weatherIconForCondition(period.condition),
                          size: 22,
                          color: const Color(0xFF116349),
                        ),
                        Text(
                          period.localDateTime ?? 'Waktu tidak tersedia',
                          maxLines: 2,
                          style: const TextStyle(fontSize: 11),
                        ),
                        Text(
                          period.temperature == null
                              ? '—'
                              : '${period.temperature}°',
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${period.condition ?? 'Kondisi tidak tersedia'}${period.humidity == null ? '' : ' · ${period.humidity}% RH'}',
                          maxLines: 2,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  );
                },
              ),
            )
          else
            const _EmptyState(text: 'Interval prakiraan belum tersedia.'),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton.icon(
                onPressed: load,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba muat kembali'),
              ),
            ),
          const SizedBox(height: 22),
          const Text(
            'Akses cepat',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: QuickCard(
                  icon: Icons.map_outlined,
                  title: 'Peta & shelter',
                  subtitle: 'Cari informasi titik',
                  onTap: () => widget.onSelectTab(1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: QuickCard(
                  icon: Icons.add_location_alt_outlined,
                  title: 'Kirim laporan',
                  subtitle: 'Bagikan kondisi',
                  onTap: () => widget.onSelectTab(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Informasi terbaru',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          if (newsDataType == 'simulation')
            const Padding(padding: EdgeInsets.only(top: 8), child: DemoBadge()),
          if (news.isEmpty)
            const _EmptyState(
              text: 'Berita aktual terverifikasi belum tersedia.',
            )
          else
            ...news
                .take(3)
                .map(
                  (item) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.article_outlined),
                      title: Text('${item['title'] ?? 'Informasi'}'),
                      subtitle: Text(
                        '${item['source'] ?? 'Contoh data'} · ${item['published_at'] ?? 'tanggal tidak tersedia'}',
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 20),
          const Text(
            'Informasi keselamatan',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline, color: Color(0xFF145B45)),
              title: const Text(
                'Periksa sumber sebelum bertindak',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Informasi simulasi bukan peringatan resmi. Ikuti arahan BPBD setempat.',
              ),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

void _showUnavailable(BuildContext context, String title, String message) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}

class _HomeNewsCard extends StatelessWidget {
  const _HomeNewsCard({
    required this.item,
    required this.simulation,
    required this.onTap,
  });
  final Map<String, dynamic> item;
  final bool simulation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = '${item['title'] ?? 'Berita terbaru'}';
    final summary = '${item['summary'] ?? item['description'] ?? ''}';
    final image = item['image_url'] ?? item['image'];
    final imageUrl = image is String && image.startsWith('http') ? image : null;
    final imageAsset = _demoNewsImageAsset(item['image_key']);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(SiagaNowSurfaceTokens.cardRadius),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 218,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageAsset != null)
                Image.asset(imageAsset, fit: BoxFit.cover),
              if (imageAsset == null && imageUrl != null)
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Color(0xFF6F9E86)),
                ),
              if (imageAsset == null && imageUrl == null && simulation)
                Image.asset(
                  'assets/images/news_flooded_home.jpg',
                  fit: BoxFit.cover,
                ),
              if (imageAsset == null && imageUrl == null && !simulation)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF91B9A2), Color(0xFF316C53)],
                    ),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xD9002016)],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF075B49),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    simulation ? 'BERITA · SIMULASI' : 'BERITA TERBARU',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const Positioned(
                right: 10,
                top: 88,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Color(0xEFFFFFFF),
                  child: Icon(Icons.chevron_right, color: Color(0xFF183B31)),
                ),
              ),
              Positioned(
                left: 14,
                right: 50,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Text(
                      '${item['source'] ?? 'Sumber tidak dicantumkan'} · ${item['published_at'] ?? 'tanggal tidak tersedia'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeNewsEmpty extends StatelessWidget {
  const _HomeNewsEmpty({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: SiagaNowSurfaceTokens.info,
    borderRadius: BorderRadius.circular(SiagaNowSurfaceTokens.cardRadius),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SiagaNowSurfaceTokens.cardRadius),
      child: const SizedBox(
        height: 140,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Berita terbaru belum tersedia. Ketuk untuk membuka informasi berita.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );
}

class _AiFloodDetectionCard extends StatelessWidget {
  const _AiFloodDetectionCard({required this.value});

  final dynamic value;

  @override
  Widget build(BuildContext context) {
    final result = value is Map
        ? Map<String, dynamic>.from(value as Map)
        : <String, dynamic>{};
    final status = '${result['status'] ?? 'unknown'}';
    final label = switch (status) {
      'normal' => 'Normal · hasil model',
      'warning' => 'Waspada',
      'danger' => 'Bahaya',
      _ => 'Unknown',
    };
    final observation = result['latest_observation'] is Map
        ? Map<String, dynamic>.from(result['latest_observation'] as Map)
        : <String, dynamic>{};
    final camera = observation['camera'] is Map
        ? Map<String, dynamic>.from(observation['camera'] as Map)
        : <String, dynamic>{};
    final confidence = observation['confidence'];
    final verificationLabel =
        switch ('${observation['verification_status'] ?? ''}') {
          'verified' => 'Ditinjau petugas',
          'rejected' => 'Ditolak petugas',
          'pending' => 'Belum ditinjau petugas',
          _ => null,
        };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SiagaNowSurfaceTokens.mintInfo,
        borderRadius: BorderRadius.circular(SiagaNowSurfaceTokens.panelRadius),
        border: Border.all(color: SiagaNowSurfaceTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.water, color: Color(0xFF075B49), size: 24),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'AI Flood Detection',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${result['message'] ?? 'Observasi AI belum tersedia.'}',
            style: const TextStyle(fontSize: 12, height: 1.35),
          ),
          if (observation.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              [
                if (camera['name'] != null) camera['name'].toString(),
                if (observation['observed_at'] != null)
                  'Observasi ${observation['observed_at']}',
                if (confidence is num)
                  'Confidence ${(confidence * 100).toStringAsFixed(1)}%',
                ?verificationLabel,
              ].join(' · '),
              style: const TextStyle(fontSize: 11, color: Color(0xFF53665C)),
            ),
          ],
          const SizedBox(height: 6),
          const Text(
            'Hasil model bukan peringatan resmi. Jika data tidak ada atau kedaluwarsa, status tetap Unknown.',
            style: TextStyle(
              fontSize: 10,
              height: 1.3,
              color: Color(0xFF53665C),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningStatusCard extends StatelessWidget {
  const _WarningStatusCard({
    required this.warning,
    required this.loading,
    required this.error,
    this.checkingLocation = false,
    this.onCheckLocation,
    this.onOpenSettings,
  });
  final dynamic warning;
  final bool loading;
  final String? error;
  final bool checkingLocation;
  final VoidCallback? onCheckLocation;
  final VoidCallback? onOpenSettings;
  @override
  Widget build(BuildContext context) {
    final values = warning is Map
        ? Map<String, dynamic>.from(warning as Map)
        : <String, dynamic>{};
    final status = '${values['status'] ?? 'unknown'}';
    final active = values['active'] == true;
    final known = status != 'unknown' && status != 'unavailable';
    final title = loading
        ? 'Memeriksa status peringatan'
        : active
        ? 'Peringatan aktif'
        : known
        ? 'Tidak ada peringatan aktif'
        : 'Status peringatan belum diketahui';
    final detail = active
        ? '${values['message'] ?? 'Ikuti instruksi otoritas setempat.'}'
        : status == 'no_warning_found'
        ? '${values['message'] ?? 'Tidak ditemukan peringatan aktif di titik ini. Ini bukan jaminan lokasi aman.'}'
        : known
        ? 'Belum ada peringatan aktif yang dikirim oleh sumber ini.'
        : error ??
              '${values['message'] ?? 'Informasi peringatan resmi belum tersedia.'}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SiagaNowSurfaceTokens.warning,
        borderRadius: BorderRadius.circular(SiagaNowSurfaceTokens.panelRadius),
        border: Border.all(color: const Color(0x66F4CECE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/illustrations/home_flood_warning.png',
                width: 72,
                height: 72,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'INFORMASI PERINGATAN',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF9F4545),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: const TextStyle(fontSize: 12, height: 1.2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (values['source'] != null || values['checked_at'] != null)
            Padding(
              padding: const EdgeInsets.only(left: 84, top: 6),
              child: Text(
                [
                  if (values['source'] != null) 'Sumber: ${values['source']}',
                  if (values['checked_at'] != null)
                    'Diperiksa ${values['checked_at']}',
                ].join(' · '),
                style: const TextStyle(fontSize: 11, color: Color(0xFF68756B)),
              ),
            ),
          if (values['warnings'] is List &&
              (values['warnings'] as List).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 84, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: (values['warnings'] as List)
                    .whereType<Map>()
                    .take(2)
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          [item['title']?.toString(), item['area']?.toString()]
                              .whereType<String>()
                              .where((part) => part.isNotEmpty)
                              .join(' · '),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          if (onOpenSettings != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Buka pengaturan lokasi'),
              ),
            ),
          if (onCheckLocation != null)
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: checkingLocation ? null : onCheckLocation,
                icon: checkingLocation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_outlined),
                label: Text(
                  checkingLocation
                      ? 'Memeriksa lokasi…'
                      : 'Periksa peringatan di lokasi saya',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeWeatherCard extends StatelessWidget {
  const _HomeWeatherCard({
    required this.weather,
    required this.isDemo,
    required this.onTap,
  });
  final dynamic weather;
  final bool isDemo;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final actual = weather is Map && weather['data_type'] == 'actual';
    final location = weather is Map ? weather['location']?.toString() : null;
    final condition = weather is Map ? weather['condition']?.toString() : null;
    return Material(
      color: SiagaNowSurfaceTokens.mintInfo,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Image.asset(
                'assets/illustrations/weather_sun_cloud.png',
                width: 68,
                height: 68,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cuaca hari ini',
                      style: TextStyle(
                        color: Color(0xFF397A60),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      weather is Map
                          ? '${weather['temperature'] ?? '—'}°'
                          : '—',
                      style: const TextStyle(
                        fontSize: 28,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF276649),
                      ),
                    ),
                    Text(
                      condition ?? 'Kondisi cuaca tidak tersedia',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${actual
                          ? 'BMKG'
                          : isDemo
                          ? 'Data contoh'
                          : 'Sumber belum tersedia'}${location == null ? '' : ' · $location'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF66786D),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeStatsCard extends StatelessWidget {
  const _HomeStatsCard({required this.values});
  final Map<String, dynamic> values;
  @override
  Widget build(BuildContext context) {
    final simulated = values['data_type'] == 'simulation';
    final source = values['source']?.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: SiagaNowSurfaceTokens.info,
        borderRadius: BorderRadius.circular(SiagaNowSurfaceTokens.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Statistik bencana',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (simulated)
                const Text(
                  'LATIHAN',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF85661B),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (source != null)
            Text(
              source,
              style: const TextStyle(fontSize: 11, color: Color(0xFF68756B)),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _statValue('Kejadian', values['events'])),
              Expanded(
                child: _statValue('Terdampak', values['affected_people']),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statValue(String label, dynamic value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value?.toString() ?? '—',
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: Color(0xFF075B49),
        ),
      ),
      Text(label, style: const TextStyle(fontSize: 11)),
    ],
  );
}

class WeatherDetailPage extends StatelessWidget {
  const WeatherDetailPage({
    super.key,
    required this.weather,
    required this.forecasts,
    required this.warning,
  });
  final dynamic weather;
  final List<WeatherPeriod> forecasts;
  final dynamic warning;
  @override
  Widget build(BuildContext context) {
    final values = weather is Map
        ? Map<String, dynamic>.from(weather as Map)
        : <String, dynamic>{};
    final firstForecastDate = forecasts.isEmpty
        ? null
        : forecasts.first.localDateTime?.split('T').first;
    final futureDays = <String, WeatherPeriod>{};
    for (final forecast in forecasts) {
      final date = forecast.localDateTime?.split('T').first;
      if (date != null && date != firstForecastDate) {
        futureDays.putIfAbsent(date, () => forecast);
      }
    }
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const SiagaNowHeaderBackground(),
        title: const Text('Cuaca'),
      ),
      body: SiagaNowPageBackground(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                const Expanded(
                  child: TextField(
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: 'Pencarian lokasi',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Cari lokasi',
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Pencarian lokasi belum tersedia.'),
                    ),
                  ),
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: SiagaNowSurfaceTokens.mintInfo,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset(
                    'assets/illustrations/weather_sun_cloud.png',
                    width: 76,
                    height: 76,
                    fit: BoxFit.contain,
                  ),
                  Text(
                    '${values['temperature'] ?? '—'}°',
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF075B49),
                    ),
                  ),
                  Text(
                    '${values['condition'] ?? 'Kondisi belum tersedia'}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${values['location'] ?? 'Lokasi tidak tersedia'}'),
                  Text(
                    'Sumber: ${values['source'] ?? 'tidak dicantumkan'}${values['updated_at'] == null ? '' : ' · Diperbarui ${values['updated_at']}'}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF68756B),
                    ),
                  ),
                  if (values['message'] != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${values['message']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _WeatherMetricTile(
                    label: 'Kelembapan Air',
                    value: values['humidity'] == null
                        ? 'Belum tersedia'
                        : '${values['humidity']}%',
                    icon: Icons.water_drop_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: _WeatherMetricTile(
                    label: 'Kelembapan Tanah',
                    value: 'Data belum tersedia',
                    icon: Icons.grass_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _WeatherMetricTile(
                    label: 'Kecepatan Angin',
                    value: values['wind_kmh'] == null
                        ? 'Belum tersedia'
                        : '${values['wind_kmh']} km/j',
                    icon: Icons.air_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _WarningStatusCard(warning: warning, loading: false, error: null),
            const SizedBox(height: 20),
            const Text(
              'Prakiraan Cuaca Hari Ini',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            if (forecasts.isEmpty)
              const _EmptyState(
                text: 'Interval prakiraan belum tersedia dari API.',
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: forecasts
                    .where(
                      (period) =>
                          period.localDateTime?.split('T').first ==
                          firstForecastDate,
                    )
                    .take(4)
                    .map((period) => _WeatherForecastTile(period: period))
                    .toList(),
              ),
            const SizedBox(height: 20),
            const Text(
              'Prakiraan Yang Akan Datang',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            if (futureDays.isEmpty)
              const _EmptyState(
                text: 'Prakiraan hari mendatang belum tersedia dari API.',
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: futureDays.values
                    .take(4)
                    .map((period) => _WeatherForecastTile(period: period))
                    .toList(),
              ),
            const SizedBox(height: 10),
            const Text(
              'Prakiraan BMKG berlaku untuk wilayah administrasi dan bukan pengukuran di alamat rumah.',
              style: TextStyle(fontSize: 12, color: Color(0xFF68756B)),
            ),
            Text(
              'Sumber: ${values['source'] ?? 'belum dicantumkan'}${values['updated_at'] == null ? '' : ' · Diperbarui ${values['updated_at']}'}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF68756B)),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherMetricTile extends StatelessWidget {
  const _WeatherMetricTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 96),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
    decoration: BoxDecoration(
      color: SiagaNowSurfaceTokens.mintInfo,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: const Color(0xFF116349), size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _WeatherForecastTile extends StatelessWidget {
  const _WeatherForecastTile({required this.period});

  final WeatherPeriod period;

  @override
  Widget build(BuildContext context) => Container(
    width: 74,
    constraints: const BoxConstraints(minHeight: 104),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
    decoration: BoxDecoration(
      color: SiagaNowSurfaceTokens.mintInfo,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          period.localDateTime?.replaceFirst('T', '\n') ??
              'Waktu belum tersedia',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 9),
        ),
        Icon(
          weatherIconForCondition(period.condition),
          color: const Color(0xFF116349),
          size: 22,
        ),
        Text(
          period.temperature == null ? '—' : '${period.temperature}°',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        Text(
          period.condition ?? 'Belum tersedia',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 8),
        ),
      ],
    ),
  );
}

class ShelterPage extends StatefulWidget {
  const ShelterPage({
    super.key,
    required this.api,
    required this.loggedIn,
    required this.onSendSafeStatus,
    this.routingService = const UnavailableRoutingService(),
  });
  final ApiService api;
  final bool loggedIn;
  final Future<bool> Function() onSendSafeStatus;
  final RoutingService routingService;
  @override
  State<ShelterPage> createState() => _ShelterPageState();
}

class _ShelterPageState extends State<ShelterPage> {
  final search = TextEditingController();
  final mapController = MapController();
  static final _initialCenter = LatLng(
    double.tryParse(_defaultMapLatitude) ?? -0.9471,
    double.tryParse(_defaultMapLongitude) ?? 100.4172,
  );
  static final Future<FileCacheStore> _tileStore = _createTileStore();
  List<ShelterRecord> places = [];
  bool loading = true;
  bool requestPending = false;
  bool locationLoading = false;
  bool mapReady = false;
  bool tileFailed = false;
  bool initialLocationRequested = false;
  bool locationPermissionPermanentlyDenied = false;
  String? issue;
  String? locationMessage;
  String? dataType;
  LatLng? userLocation;
  LatLng? lastSelectedLocation;

  static Future<FileCacheStore> _createTileStore() async {
    final directory = await getApplicationSupportDirectory();
    return FileCacheStore(
      '${directory.path}${Platform.pathSeparator}map_tiles',
    );
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (requestPending) return;
    requestPending = true;
    setState(() {
      loading = true;
      issue = null;
    });
    try {
      final result = await widget.api.get(
        'shelters',
        query: {if (search.text.trim().isNotEmpty) 'q': search.text.trim()},
      );
      dataType = result['data_type']?.toString();
      final apiShelters = (result['data'] is List ? result['data'] as List : [])
          .whereType<Map>()
          .map(
            (p) => ShelterRecord.fromJson(
              Map<String, dynamic>.from(p),
              simulation: dataType == 'simulation',
            ),
          )
          .toList();
      // In local single-fixture QA mode, do not display other API-provided
      // simulations alongside the one explicitly requested local fixture.
      places = kDebugMode && shelterSimulationEnabled
          ? apiShelters.where((shelter) => !shelter.simulation).toList()
          : apiShelters;
      // Local QA fixtures stay explicitly tagged and can never enter an API request.
      if (kDebugMode && shelterSimulationEnabled) {
        final query = search.text.trim().toLowerCase();
        places.addAll(
          ShelterRecord.localSimulationFixtures.where(
            (shelter) =>
                query.isEmpty ||
                '${shelter.name} ${shelter.address}'.toLowerCase().contains(
                  query,
                ),
          ),
        );
      }
      final matching = realShelters;
      if (matching.length == 1 && mapReady) {
        mapController.move(
          LatLng(matching.single.latitude!, matching.single.longitude!),
          15,
        );
      }
    } catch (_) {
      issue = 'Shelter belum berhasil dimuat. Periksa koneksi lalu coba lagi.';
      places = [];
      if (kDebugMode && shelterSimulationEnabled) {
        final query = search.text.trim().toLowerCase();
        places = ShelterRecord.localSimulationFixtures
            .where(
              (shelter) =>
                  query.isEmpty ||
                  '${shelter.name} ${shelter.address}'.toLowerCase().contains(
                    query,
                  ),
            )
            .toList();
      }
    }
    requestPending = false;
    if (mounted) setState(() => loading = false);
  }

  Widget _mapUnavailable(String message) => Container(
    height: 300,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xBFE8EEE8),
      borderRadius: BorderRadius.circular(SiagaNowSurfaceTokens.cardRadius),
    ),
    padding: const EdgeInsets.all(20),
    child: Text(message, textAlign: TextAlign.center),
  );

  List<ShelterRecord> get realShelters => places
      .where((place) => !place.simulation && place.hasValidCoordinates)
      .toList();

  Future<void> useCurrentLocation({bool initialRequest = false}) async {
    if (locationLoading) return;
    locationPermissionPermanentlyDenied = false;
    setState(() => locationLoading = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const LocationServiceDisabledException();
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        locationPermissionPermanentlyDenied =
            permission == LocationPermission.deniedForever;
        userLocation = null;
        throw ApiException(
          permission == LocationPermission.deniedForever
              ? 'Izin lokasi ditolak permanen. Peta tetap memakai titik default/lokasi peta terakhir, bukan posisi Anda.'
              : 'Izin lokasi ditolak. Peta tetap memakai titik default/lokasi peta terakhir, bukan posisi Anda.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        userLocation = point;
        locationMessage = 'Posisi perangkat dari GPS satu kali.';
      });
      if (mapReady &&
          !(initialRequest && kDebugMode && shelterSimulationEnabled)) {
        mapController.move(point, 15);
      }
    } on TimeoutException {
      userLocation = null;
      locationMessage = 'GPS tidak merespons dalam 15 detik. Peta tetap dapat digunakan di lokasi peta terakhir atau default Padang.';
    } on LocationServiceDisabledException {
      userLocation = null;
      locationMessage = 'GPS/lokasi perangkat nonaktif. Peta menggunakan lokasi peta terakhir atau default Padang; titik ini bukan posisi Anda.';
    } on PermissionDeniedException {
      userLocation = null;
      locationMessage = 'Izin lokasi ditolak. Peta menggunakan lokasi peta terakhir atau default Padang; titik ini bukan posisi Anda.';
    } catch (error) {
      userLocation = null;
      locationMessage =
          'Lokasi tidak tersedia (${error.toString()}). Peta menggunakan lokasi peta terakhir atau default Padang; titik ini bukan posisi Anda.';
    } finally {
      if (mounted) {
        setState(() => locationLoading = false);
        if (!initialRequest && locationMessage != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(locationMessage!)));
        }
      }
    }
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openAppSettings();
  }

  void showShelter(ShelterRecord place) {
    if (!place.hasValidCoordinates) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hasil ini tidak memiliki koordinat shelter terverifikasi.',
          ),
        ),
      );
      return;
    }
    if (mapReady) {
      mapController.move(LatLng(place.latitude!, place.longitude!), 14);
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShelterDetailPage(
          shelter: place,
          userLocation: userLocation,
          routingService: widget.routingService,
          loggedIn: widget.loggedIn,
          onSendSafeStatus: widget.onSendSafeStatus,
        ),
      ),
    );
  }

  Future<void> openSimulationDirections(ShelterRecord shelter) async {
    if (!shelter.simulation || !shelter.hasValidCoordinates) return;
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
  Widget build(BuildContext context) {
    final sortedPlaces = [...places];
    if (userLocation != null) {
      sortedPlaces.sort((left, right) {
        final leftDistance = left.distanceFrom(userLocation);
        final rightDistance = right.distanceFrom(userLocation);
        if (leftDistance == null) return rightDistance == null ? 0 : 1;
        if (rightDistance == null) return -1;
        return leftDistance.compareTo(rightDistance);
      });
    }
    final nearestVerified = userLocation == null
        ? null
        : sortedPlaces
              .where((place) => place.isVerified && place.hasValidCoordinates)
              .firstOrNull;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
        children: [
          const Text(
            'Rute Evakuasi',
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          Text(
            'Jelajahi titik informasi dan rencanakan kesiapsiagaan.',
            style: TextStyle(color: Colors.blueGrey.shade600),
          ),
          if (kDebugMode && shelterSimulationEnabled) ...[
            const SizedBox(height: 10),
            const _SimulationNotice(),
          ],
          const SizedBox(height: 16),
          FutureBuilder<FileCacheStore>(
            future: _tileStore,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _mapUnavailable(
                  'Penyimpanan peta tidak dapat disiapkan.',
                );
              }
              if (!snapshot.hasData) {
                return const SizedBox(
                  height: 300,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final markers = <Marker>[
                for (final shelter in realShelters)
                  Marker(
                    point: LatLng(shelter.latitude!, shelter.longitude!),
                    width: 48,
                    height: 52,
                    child: IconButton(
                      tooltip: shelter.name,
                      onPressed: () => showShelter(shelter),
                      icon: const Icon(
                        Icons.location_on,
                        size: 42,
                        color: Color(0xFF145B45),
                      ),
                    ),
                  ),
                if (kDebugMode && shelterSimulationEnabled)
                  for (final shelter in places.where(
                    (place) => place.simulation && place.hasValidCoordinates,
                  ))
                    Marker(
                      point: LatLng(shelter.latitude!, shelter.longitude!),
                      width: 52,
                      height: 54,
                      child: IconButton(
                        tooltip: '${shelter.name} · simulasi',
                        onPressed: () => showShelter(shelter),
                        icon: const Icon(
                          Icons.location_on,
                          size: 44,
                          color: Color(0xFFE69B22),
                        ),
                      ),
                    ),
                if (userLocation != null)
                  Marker(
                    point: userLocation!,
                    width: 44,
                    height: 44,
                    child: const Icon(
                      Icons.my_location,
                      size: 30,
                      color: Colors.blue,
                    ),
                  ),
              ];
              return ClipRRect(
                borderRadius: BorderRadius.circular(
                  SiagaNowSurfaceTokens.cardRadius,
                ),
                child: SizedBox(
                  height: 300,
                  child: Stack(
                    children: [
                      FlutterMap(
                        mapController: mapController,
                        options: MapOptions(
                          initialCenter: _initialCenter,
                          initialZoom: kDebugMode && shelterSimulationEnabled
                              ? 10
                              : 12,
                          onMapReady: () {
                            if (!mounted) return;
                            setState(() => mapReady = true);
                            if (!initialLocationRequested) {
                              initialLocationRequested = true;
                              unawaited(
                                useCurrentLocation(initialRequest: true),
                              );
                            }
                          },
                          onPositionChanged: (camera, hasGesture) {
                            if (hasGesture) {
                              lastSelectedLocation = camera.center;
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: mapTileUrl,
                            userAgentPackageName:
                                'com.example.siaga_now_mobile',
                            tileProvider: CachedTileProvider(
                              store: snapshot.data!,
                              headers: {'User-Agent': appUserAgent},
                              cachePolicy: CachePolicy.request,
                              maxStale: const Duration(days: 30),
                              hitCacheOnNetworkFailure: true,
                            ),
                            errorTileCallback: (_, _, _) {
                              if (!tileFailed && mounted) {
                                setState(() => tileFailed = true);
                              }
                            },
                          ),
                          MarkerLayer(markers: markers),
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
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Column(
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'map-zoom-in',
                              onPressed: () => mapController.move(
                                mapController.camera.center,
                                mapController.camera.zoom + 1,
                              ),
                              child: const Icon(Icons.add),
                            ),
                            const SizedBox(height: 6),
                            FloatingActionButton.small(
                              heroTag: 'map-zoom-out',
                              onPressed: () => mapController.move(
                                mapController.camera.center,
                                mapController.camera.zoom - 1,
                              ),
                              child: const Icon(Icons.remove),
                            ),
                            const SizedBox(height: 6),
                            FloatingActionButton.small(
                              heroTag: 'map-my-location',
                              onPressed: locationLoading
                                  ? null
                                  : useCurrentLocation,
                              child: locationLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.my_location),
                            ),
                          ],
                        ),
                      ),
                      if (tileFailed)
                        const Positioned(
                          left: 8,
                          top: 8,
                          right: 64,
                          child: Material(
                            color: Color(0xFFF8E9D8),
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'Sebagian peta gagal dimuat. Coba lagi saat jaringan tersedia.',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: nearestVerified == null
                ? null
                : () => showShelter(nearestVerified),
            icon: const Icon(Icons.route_outlined),
            label: const Text('Cari Shelter Terdekat'),
          ),
          const Text(
            'Urutan hanya berdasarkan jarak lurus dari GPS. Layanan rute belum tersedia dan informasi ini bukan jaminan keselamatan.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFF596B60)),
          ),
          const SizedBox(height: 7),
          const Text(
            'Peta dapat digeser dan diperbesar. © OpenStreetMap contributors',
            style: TextStyle(fontSize: 11),
          ),
          if (locationMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      locationMessage!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (locationPermissionPermanentlyDenied)
                    TextButton(
                      onPressed: openLocationSettings,
                      child: const Text('Pengaturan'),
                    ),
                ],
              ),
            )
          else if (userLocation == null)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                lastSelectedLocation == null
                    ? 'Lokasi default Padang; bukan posisi Anda. Gunakan tombol lokasi untuk mencoba GPS.'
                    : 'Menampilkan lokasi peta terakhir; bukan posisi GPS Anda.',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Rute evakuasi resmi dan zona aman belum tersedia. Jangan gunakan peta ini sebagai panduan rute darurat.',
            style: TextStyle(fontSize: 12, color: Color(0xFF745B2A)),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => load(),
            decoration: InputDecoration(
              labelText: 'Cari shelter berdasarkan nama/alamat',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: loading ? null : load,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 19),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Evakuasi Terdekat',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              IconButton(
                onPressed: loading ? null : load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (issue != null) _InlineError(issue!),
          if (loading)
            const _LoadingSkeleton(rows: 3)
          else if (places.isEmpty)
            _EmptyState(text: issue ?? 'Belum ada tempat yang tercatat.')
          else
            ...sortedPlaces.map((p) {
              final simulated = p.simulation;
              final distanceFromGps = p.distanceFrom(userLocation);
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: simulated
                        ? const Color(0xFFFFF2D5)
                        : const Color(0xFFE7F1EA),
                    child: Icon(
                      Icons.place_outlined,
                      color: simulated
                          ? const Color(0xFFB8740B)
                          : const Color(0xFF145B45),
                    ),
                  ),
                  title: Text(
                    p.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${p.address}${distanceFromGps == null ? '' : '\n${distanceFromGps.toStringAsFixed(1)} km dari GPS'}\n${simulated ? 'SIMULASI — BUKAN SHELTER RESMI' : '${p.source ?? 'Sumber tidak tercatat'} · ${p.verifiedAt == null ? 'Belum diverifikasi' : 'Diverifikasi ${p.verifiedAt}'}'}',
                  ),
                  isThreeLine: true,
                  trailing: Icon(
                    p.hasValidCoordinates && !simulated
                        ? Icons.near_me
                        : Icons.info_outline,
                  ),
                  onTap: () => showShelter(p),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class ReportPage extends StatefulWidget {
  const ReportPage({
    super.key,
    required this.api,
    required this.loggedIn,
    required this.onLogin,
    this.onHome,
  });
  final ApiService api;
  final bool loggedIn;
  final Future<void> Function() onLogin;
  final VoidCallback? onHome;
  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();
  final lat = TextEditingController();
  final lng = TextEditingController();
  final injured = TextEditingController();
  final deceased = TextEditingController();
  String eventType = 'Banjir';
  String? damage;
  bool showDamageError = false;
  DateTime occurredAt = DateTime.now();
  bool sending = false, gettingLocation = false, historyLoading = false;
  List<dynamic> reports = [];
  List<PlatformFile> evidence = [];
  @override
  void dispose() {
    lat.removeListener(_locationEdited);
    lng.removeListener(_locationEdited);
    title.dispose();
    description.dispose();
    lat.dispose();
    lng.dispose();
    injured.dispose();
    deceased.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    lat.addListener(_locationEdited);
    lng.addListener(_locationEdited);
    if (widget.loggedIn) loadReports();
  }

  void _locationEdited() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ReportPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.loggedIn && widget.loggedIn) loadReports();
  }

  Future<void> useDeviceLocation() async {
    setState(() => gettingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const ApiException(
          'Aktifkan GPS atau masukkan koordinat lokasi secara manual.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const ApiException(
          'Izin lokasi ditolak. Masukkan koordinat lokasi secara manual.',
        );
      }
      final position = await Geolocator.getCurrentPosition();
      lat.text = position.latitude.toStringAsFixed(7);
      lng.text = position.longitude.toStringAsFixed(7);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() => gettingLocation = false);
  }

  Future<void> pickMapLocation() async {
    final existingLat = double.tryParse(lat.text);
    final existingLng = double.tryParse(lng.text);
    final initialCenter = existingLat != null && existingLng != null
        ? LatLng(existingLat, existingLng)
        : const LatLng(-2.5, 118);
    final selected = await showDialog<LatLng>(
      context: context,
      builder: (dialogContext) {
        LatLng? point;
        return StatefulBuilder(
          builder: (context, setDialogState) => Dialog.fullscreen(
            child: SafeArea(
              child: Column(
                children: [
                  AppBar(
                    leading: IconButton(
                      tooltip: 'Tutup peta',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                    title: const Text('Pilih lokasi kejadian'),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Ketuk peta pada titik kejadian. Lokasi tidak dipilih otomatis.',
                    ),
                  ),
                  Expanded(
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: initialCenter,
                        initialZoom: existingLat == null ? 4 : 14,
                        onTap: (_, selectedPoint) =>
                            setDialogState(() => point = selectedPoint),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: mapTileUrl,
                          userAgentPackageName: appUserAgent,
                        ),
                        if (point != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: point!,
                                width: 42,
                                height: 48,
                                child: const Icon(
                                  Icons.location_pin,
                                  color: Color(0xFFB3261E),
                                  size: 42,
                                ),
                              ),
                            ],
                          ),
                        RichAttributionWidget(
                          alignment: AttributionAlignment.bottomRight,
                          attributions: [
                            TextSourceAttribution(
                              '© OpenStreetMap contributors',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: point == null
                            ? null
                            : () => Navigator.pop(dialogContext, point),
                        child: const Text('Gunakan lokasi ini'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (selected != null && mounted) {
      lat.text = selected.latitude.toStringAsFixed(7);
      lng.text = selected.longitude.toStringAsFixed(7);
    }
  }

  Future<void> pickEvidence() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'webm'],
    );
    if (files.isEmpty) return;
    final sizes = await Future.wait(files.map((f) => f.length()));
    if (files.length > 5 || sizes.any((size) => size > 10 * 1024 * 1024)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih maksimal 5 file, masing-masing sampai 10 MB.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => evidence = files);
  }

  Future<void> loadReports() async {
    setState(() => historyLoading = true);
    try {
      final result = await widget.api.get('reports');
      reports = result['data'] is List ? result['data'] as List : [];
    } catch (e) {
      if (e is ApiException && (e.statusCode == 401 || e.statusCode == 403)) {
        widget.onLogin();
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() => historyLoading = false);
  }

  Future<void> submit() async {
    if (sending) return;
    if (!form.currentState!.validate()) return;
    if (damage == null) {
      setState(() => showDamageError = true);
      return;
    }
    if (!widget.loggedIn) {
      widget.onLogin();
      return;
    }
    setState(() => sending = true);
    try {
      final now = occurredAt;
      final result = await widget.api.uploadReport({
        'title': title.text.trim(),
        'latitude': double.parse(lat.text),
        'longitude': double.parse(lng.text),
        'event_date':
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        'event_time':
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        'event_type': eventType,
        'damage_level': damage!,
        'description': description.text.trim(),
        if (injured.text.isNotEmpty) 'injured': injured.text,
        if (deceased.text.isNotEmpty) 'deceased': deceased.text,
      }, evidence);
      final rawReport = result['data'];
      if (rawReport is! Map) {
        throw const ApiException(
          'Server belum mengonfirmasi bahwa laporan berhasil disimpan.',
        );
      }
      final reportData = Map<String, dynamic>.from(rawReport);
      if (!reportData.containsKey('shelter')) {
        final outerShelter = result['shelter'] ?? result['recommended_shelter'];
        if (outerShelter != null) reportData['shelter'] = outerShelter;
      }
      final receipt = ReportReceipt.fromJson(reportData);
      final incidentTitle = title.text.trim();
      final incidentLatitude = double.parse(lat.text);
      final incidentLongitude = double.parse(lng.text);
      var recommendedShelter = receipt.shelter;
      if (recommendedShelter == null &&
          kDebugMode &&
          shelterSimulationEnabled) {
        final reportPoint = LatLng(
          double.parse(lat.text),
          double.parse(lng.text),
        );
        final closest =
            ShelterRecord.localSimulationFixtures
                .where((shelter) => shelter.hasValidCoordinates)
                .map(
                  (shelter) => (
                    shelter: shelter,
                    km: const Distance().as(
                      LengthUnit.Kilometer,
                      reportPoint,
                      LatLng(shelter.latitude!, shelter.longitude!),
                    ),
                  ),
                )
                .toList()
              ..sort((a, b) => a.km.compareTo(b.km));
        if (closest.isNotEmpty) {
          recommendedShelter = ReportShelterInfo.localSimulation(
            closest.first.shelter,
            closest.first.km,
          );
        }
      }
      if (mounted) {
        // The form is cleared only after the API returned a valid saved report.
        title.clear();
        description.clear();
        lat.clear();
        lng.clear();
        injured.clear();
        deceased.clear();
        evidence.clear();
        damage = null;
        setState(() => sending = false);
        unawaited(loadReports());
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ReportSuccessPage(
                shelter: recommendedShelter,
                aiAnalysis: receipt.aiAnalysis,
                incidentTitle: incidentTitle,
                incidentLatitude: incidentLatitude,
                incidentLongitude: incidentLongitude,
                onReturnHome: () {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  widget.onHome?.call();
                },
              ),
            ),
          ),
        );
        return;
      }
    } catch (e) {
      if (e is ApiException && (e.statusCode == 401 || e.statusCode == 403)) {
        widget.onLogin();
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() => sending = false);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
    children: [
      const Text(
        'Laporkan bencana',
        style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        'Bagikan informasi untuk ditinjau. Laporan tidak langsung menjadi peringatan resmi.',
        style: TextStyle(color: Colors.blueGrey.shade600, height: 1.45),
      ),
      const SizedBox(height: 16),
      if (!widget.loggedIn)
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Masuk untuk mengirim laporan'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onLogin,
          ),
        ),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Deskripsi bencana',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 14),
                _field(
                  title,
                  'Nama kejadian/bencana',
                  validator: (v) => (v == null || v.trim().length < 4)
                      ? 'Masukkan judul minimal 4 karakter.'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: eventType,
                  decoration: const InputDecoration(
                    labelText: 'Jenis bencana',
                    border: OutlineInputBorder(),
                  ),
                  items: ['Banjir', 'Tanah longsor']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() => eventType = v!),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Lokasi kejadian',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: gettingLocation ? null : useDeviceLocation,
                    icon: gettingLocation
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: Text(
                      gettingLocation
                          ? 'Mengambil lokasi…'
                          : 'Pilih lokasi dari GPS',
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: pickMapLocation,
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Pilih titik di peta'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        lat,
                        'Latitude',
                        validator: (v) => _coordinate(v, -90, 90),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        lng,
                        'Longitude',
                        validator: (v) => _coordinate(v, -180, 180),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _reportLocationPreview(),
                const SizedBox(height: 16),
                const Text(
                  'Waktu kejadian',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final value = await showDatePicker(
                            context: context,
                            initialDate: occurredAt,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now().add(
                              const Duration(days: 1),
                            ),
                          );
                          if (value != null && mounted) {
                            setState(
                              () => occurredAt = DateTime(
                                value.year,
                                value.month,
                                value.day,
                                occurredAt.hour,
                                occurredAt.minute,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: const Text('Pilih tanggal'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final value = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(occurredAt),
                          );
                          if (value != null && mounted) {
                            setState(
                              () => occurredAt = DateTime(
                                occurredAt.year,
                                occurredAt.month,
                                occurredAt.day,
                                value.hour,
                                value.minute,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.schedule),
                        label: const Text('Pilih waktu'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.only(top: 7),
                  child: Text(
                    'Titik peta hanya ditampilkan setelah lokasi dipilih. Jika GPS tidak tersedia, masukkan koordinat kejadian.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF85661B)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Jumlah korban',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        injured,
                        'Luka-luka',
                        validator: _wholeNumber,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        deceased,
                        'Meninggal',
                        validator: _wholeNumber,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 7),
                  child: Text(
                    'Kosong = belum diketahui; 0 = tidak ada. Jumlah yang tidak diketahui disimpan sebagai NULL.',
                    style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Tingkat bencana',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['Rendah', 'Sedang', 'Tinggi']
                      .map(
                        (value) => ChoiceChip(
                          key: ValueKey('report-impact-$value'),
                          label: Text(value),
                          selected: damage == value,
                          onSelected: (selected) => setState(() {
                            damage = selected ? value : null;
                            showDamageError = false;
                          }),
                          selectedColor: const Color(0xFFD4F0E0),
                        ),
                      )
                      .toList(),
                ),
                if (showDamageError && damage == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Pilih tingkat bencana.',
                      style: TextStyle(color: Color(0xFFB3261E), fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 12),
                _field(
                  description,
                  'Ceritakan kondisi yang terlihat',
                  maxLines: 4,
                  validator: (v) => (v == null || v.trim().length < 10)
                      ? 'Deskripsi minimal 10 karakter.'
                      : null,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: sending ? null : pickEvidence,
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    evidence.isEmpty
                        ? 'Lampirkan foto/video (maks. 5 file)'
                        : '${evidence.length} file terpilih',
                  ),
                ),
                if (evidence.isNotEmpty)
                  ...evidence.map(
                    (f) => Text(
                      '• ${f.name}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF7EF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'TIPS\nPastikan lokasi dan waktu sesuai kejadian. Jangan mengambil risiko saat mengumpulkan bukti.',
                    style: TextStyle(height: 1.4, color: Color(0xFF174B38)),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: sending
                            ? null
                            : () => setState(() {
                                form.currentState?.reset();
                                title.clear();
                                description.clear();
                                lat.clear();
                                lng.clear();
                                injured.clear();
                                deceased.clear();
                                evidence.clear();
                                damage = null;
                                showDamageError = false;
                                eventType = 'Banjir';
                                occurredAt = DateTime.now();
                              }),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB3261E),
                          side: const BorderSide(color: Color(0xFFB3261E)),
                        ),
                        child: const Text('Batal'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: sending ? null : submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF01543F),
                        ),
                        icon: sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_outlined),
                        label: Text(sending ? 'Mengirim…' : 'Kirim'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 22),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Laporan saya',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          IconButton(
            onPressed: widget.loggedIn ? loadReports : widget.onLogin,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      if (!widget.loggedIn)
        const _EmptyState(
          text: 'Masuk untuk melihat riwayat laporan akun Anda.',
        )
      else if (historyLoading)
        const _LoadingSkeleton(rows: 2)
      else if (reports.isEmpty)
        const _EmptyState(text: 'Belum ada laporan tersimpan pada akun ini.')
      else
        ...reports.map(
          (r) => Card(
            child: ListTile(
              leading: const Icon(Icons.assignment_outlined),
              title: Text('${r['title'] ?? 'Laporan'}'),
              subtitle: Text(
                'Status: ${r['status'] ?? '—'} · ${r['created_at'] ?? ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReportDetailPage(
                    report: Map<String, dynamic>.from(r as Map),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
  String? _coordinate(String? value, double min, double max) {
    final n = double.tryParse(value ?? '');
    return n == null || n < min || n > max
        ? 'Masukkan titik antara $min dan $max.'
        : null;
  }

  String? _wholeNumber(String? value) =>
      value == null ||
          value.isEmpty ||
          (int.tryParse(value) != null && int.parse(value) >= 0)
      ? null
      : 'Masukkan bilangan bulat 0 atau lebih.';

  Widget _reportLocationPreview() {
    final latitude = double.tryParse(lat.text);
    final longitude = double.tryParse(lng.text);
    final hasLocation =
        latitude != null &&
        longitude != null &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
    if (!hasLocation) {
      return Container(
        height: 112,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4F2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('Pratinjau peta muncul setelah lokasi dipilih.'),
      );
    }
    final point = LatLng(latitude, longitude);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 150,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 14,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: mapTileUrl,
              userAgentPackageName: appUserAgent,
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: point,
                  width: 42,
                  height: 48,
                  child: const Icon(
                    Icons.location_pin,
                    color: Color(0xFFB3261E),
                    size: 42,
                  ),
                ),
              ],
            ),
            RichAttributionWidget(
              alignment: AttributionAlignment.bottomRight,
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    int maxLines = 1,
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: c,
    maxLines: maxLines,
    keyboardType:
        maxLines == 1 &&
            (label == 'Latitude' ||
                label == 'Longitude' ||
                label == 'Luka-luka' ||
                label == 'Meninggal')
        ? TextInputType.numberWithOptions(
            decimal: true,
            signed: label == 'Latitude' || label == 'Longitude',
          )
        : TextInputType.multiline,
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      alignLabelWithHint: maxLines > 1,
      errorMaxLines: 2,
      border: const OutlineInputBorder(),
    ),
  );
}

class ReportSuccessPage extends StatelessWidget {
  const ReportSuccessPage({
    super.key,
    required this.onReturnHome,
    this.shelter,
    this.aiAnalysis,
    this.incidentTitle,
    this.incidentLatitude,
    this.incidentLongitude,
  });

  final VoidCallback onReturnHome;
  final ReportShelterInfo? shelter;
  final ReportAiAnalysis? aiAnalysis;
  final String? incidentTitle;
  final double? incidentLatitude;
  final double? incidentLongitude;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFD4F0E0),
    body: LayoutBuilder(
      builder: (context, constraints) {
        final footerHeight = min(330.0, constraints.maxHeight * .42);
        final safeBottom = constraints.maxHeight * .18;
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFFD4F0E0)),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 280,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF01543F), Color(0xFFD4F0E0)],
                  ),
                ),
              ),
            ),
            const Positioned(
              key: ValueKey('report-status.fixed-header'),
              top: 0,
              left: 0,
              right: 0,
              height: 112,
              child: SiagaNowHeaderBackground(),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: footerHeight,
              child: Image.asset(
                'assets/images/landscape_background.png',
                fit: BoxFit.cover,
                alignment: Alignment.bottomCenter,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: footerHeight,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xB3D4F0E0), Color(0x33D4F0E0)],
                    stops: [0, .55],
                  ),
                ),
              ),
            ),
            const SiagaNowColorOverlay(),
            SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Kembali',
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.arrow_back),
                              color: const Color(0xFF102D25),
                            ),
                            const SizedBox(width: 2),
                            const Text(
                              'Status Laporan',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF102D25),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            min(82.0, constraints.maxHeight * .1),
                            24,
                            140,
                          ),
                          child: Column(
                            children: [
                              MediaQuery.disableAnimationsOf(context)
                                  ? SvgPicture.asset(
                                      'assets/figma/report/status_success.svg',
                                      width: 95,
                                      height: 95,
                                      semanticsLabel:
                                          'Laporan berhasil disimpan',
                                    )
                                  : TweenAnimationBuilder<double>(
                                      tween: Tween(begin: .65, end: 1),
                                      duration: const Duration(
                                        milliseconds: 360,
                                      ),
                                      curve: Curves.easeOutBack,
                                      builder: (context, scale, child) =>
                                          Transform.scale(
                                            scale: scale,
                                            child: child,
                                          ),
                                      child: SvgPicture.asset(
                                        'assets/figma/report/status_success.svg',
                                        width: 95,
                                        height: 95,
                                        semanticsLabel:
                                            'Laporan berhasil disimpan',
                                      ),
                                    ),
                              const SizedBox(height: 16),
                              const Text(
                                'Laporan Tersimpan',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: 280),
                                child: Text(
                                  'Laporan berhasil dikirim dan sedang diproses oleh tim terkait.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    height: 1.5,
                                    color: Color(0xFF171717),
                                  ),
                                ),
                              ),
                              if (incidentTitle != null &&
                                  incidentLatitude != null &&
                                  incidentLongitude != null) ...[
                                const SizedBox(height: 16),
                                Container(
                                  constraints: const BoxConstraints(
                                    maxWidth: 320,
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAF7EF),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'Lokasi kejadian',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF174B38),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        incidentTitle!,
                                        textAlign: TextAlign.center,
                                      ),
                                      Text(
                                        '${incidentLatitude!.toStringAsFixed(5)}, ${incidentLongitude!.toStringAsFixed(5)}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (shelter != null) ...[
                                const SizedBox(height: 22),
                                _ReportShelterCard(shelter: shelter!),
                              ],
                              if (aiAnalysis != null) ...[
                                const SizedBox(height: 16),
                                _ReportAiStatusCard(analysis: aiAnalysis!),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: 26,
                    right: 26,
                    bottom: max(20.0, safeBottom * .68),
                    child: SizedBox(
                      height: 60,
                      child: FilledButton(
                        onPressed: onReturnHome,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF01543F),
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shadowColor: const Color(0x66000000),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Kembali Ke Beranda',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _ReportShelterCard extends StatelessWidget {
  const _ReportShelterCard({required this.shelter});

  final ReportShelterInfo shelter;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 85),
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    decoration: BoxDecoration(
      color: SiagaNowSurfaceTokens.info,
      borderRadius: BorderRadius.circular(SiagaNowSurfaceTokens.cardRadius),
    ),
    child: Row(
      children: [
        SvgPicture.asset(
          'assets/figma/report/shelter_pin.svg',
          width: 40,
          height: 57.3525,
          semanticsLabel: 'Lokasi shelter',
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (shelter.simulation) ...[
                const Text(
                  'SHELTER SIMULASI',
                  style: TextStyle(
                    color: Color(0xFF9A650D),
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 3),
              ],
              Text(
                shelter.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF01543F),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${shelter.location}${shelter.distanceKm == null ? '' : '\nPerkiraan jarak ${shelter.distanceKm!.toStringAsFixed(1)} km · simulasi'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF01543F), fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class MorePage extends StatelessWidget {
  const MorePage({
    super.key,
    required this.api,
    required this.loggedIn,
    required this.onLogin,
    required this.onLogout,
  });
  final ApiService api;
  final bool loggedIn;
  final Future<void> Function() onLogin;
  final Future<void> Function() onLogout;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 112),
    children: [
      const Text(
        'Layanan SiagaNow',
        style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        'Informasi kesiapsiagaan dalam satu tempat.',
        style: TextStyle(color: Colors.blueGrey.shade600),
      ),
      const SizedBox(height: 18),
      _ServiceCard(
        icon: Icons.volunteer_activism_outlined,
        title: 'Donasi tanggap bencana',
        body: 'Informasi kanal resmi dan status pembayaran.',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DonationPage(
              repository: ApiDonationRepository(
                fetchCampaigns: () => api.get('donation-campaigns'),
              ),
              loggedIn: loggedIn,
              onLogin: onLogin,
            ),
          ),
        ),
      ),
      _ServiceCard(
        icon: Icons.person_outline,
        title: 'Profil dan laporan saya',
        body: loggedIn
            ? 'Muat laporan yang tersimpan pada akun ini.'
            : 'Masuk untuk mengakses fitur akun.',
        onTap: loggedIn
            ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfilePage(
                    api: api,
                    onLogin: onLogin,
                    onLogout: onLogout,
                  ),
                ),
              )
            : () => onLogin(),
      ),
      _ServiceCard(
        icon: Icons.emergency_outlined,
        title: 'PCC 112 · Kota Padang',
        body: 'Kontak darurat resmi untuk Kota Padang. Ketuk untuk melihat detail dan membuka dialer.',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EmergencyContactsPage()),
        ),
      ),
      _ServiceCard(
        icon: Icons.family_restroom_outlined,
        title: 'Keluarga Siaga',
        body: 'Kelola anggota keluarga dan kontak darurat.',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                FamilyPage(api: api, loggedIn: loggedIn, onLogin: onLogin),
          ),
        ),
      ),
      _ServiceCard(
        icon: Icons.health_and_safety_outlined,
        title: 'Penilaian risiko',
        body: 'Ajukan pemeriksaan berbasis lokasi dan lihat batasan data.',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RiskAssessmentPage(
              api: api,
              loggedIn: loggedIn,
              onLogin: onLogin,
            ),
          ),
        ),
      ),
    ],
  );
}

class _FamilyNameDialog extends StatefulWidget {
  const _FamilyNameDialog({
    required this.title,
    required this.initial,
    required this.label,
  });
  final String title;
  final String initial;
  final String label;

  @override
  State<_FamilyNameDialog> createState() => _FamilyNameDialogState();
}

class _FamilyNameDialogState extends State<_FamilyNameDialog> {
  late final controller = TextEditingController(text: widget.initial);
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: formKey,
      child: TextFormField(
        controller: controller,
        autofocus: true,
        maxLength: 100,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: widget.label),
        validator: (value) {
          final name = value?.trim() ?? '';
          if (name.isEmpty) return 'Nama keluarga wajib diisi.';
          if (name.length > 100) return 'Nama maksimal 100 karakter.';
          return null;
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () {
          if (formKey.currentState!.validate()) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: const Text('Simpan'),
      ),
    ],
  );
}

class _FamilyMemberDialog extends StatefulWidget {
  const _FamilyMemberDialog({this.member});
  final Map<String, dynamic>? member;

  @override
  State<_FamilyMemberDialog> createState() => _FamilyMemberDialogState();
}

class _FamilyMemberDialogState extends State<_FamilyMemberDialog> {
  final formKey = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: '${widget.member?['name'] ?? ''}',
  );
  late final relation = TextEditingController(
    text: '${widget.member?['relation'] ?? ''}',
  );
  late final phone = TextEditingController(
    text: '${widget.member?['emergency_phone'] ?? ''}',
  );
  late final notes = TextEditingController(
    text: '${widget.member?['notes'] ?? ''}',
  );

  @override
  void dispose() {
    name.dispose();
    relation.dispose();
    phone.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.member == null ? 'Tambah anggota' : 'Ubah anggota'),
    content: Form(
      key: formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Nama'),
              validator: (value) => (value?.trim().isEmpty ?? true)
                  ? 'Nama anggota wajib diisi.'
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: relation,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Hubungan (opsional)',
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: phone,
              keyboardType: TextInputType.phone,
              maxLength: 32,
              decoration: const InputDecoration(
                labelText: 'Kontak darurat (opsional)',
              ),
              validator: (value) {
                final input = value?.trim() ?? '';
                if (input.isNotEmpty &&
                    !RegExp(r'^[+0-9() .-]{5,32}$').hasMatch(input)) {
                  return 'Masukkan nomor telepon yang valid.';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: notes,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () {
          if (!formKey.currentState!.validate()) return;
          Navigator.pop(context, {
            'name': name.text.trim(),
            if (relation.text.trim().isNotEmpty)
              'relation': relation.text.trim(),
            if (phone.text.trim().isNotEmpty)
              'emergency_phone': phone.text.trim(),
            if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim(),
          });
        },
        child: const Text('Simpan'),
      ),
    ],
  );
}

class FamilyPage extends StatefulWidget {
  const FamilyPage({
    super.key,
    required this.api,
    required this.loggedIn,
    required this.onLogin,
  });
  final ApiService api;
  final bool loggedIn;
  final Future<void> Function() onLogin;

  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  Map<String, dynamic>? family;
  List<Map<String, dynamic>> memberships = [];
  bool loading = true;
  bool saving = false;
  final Set<int> pendingCheckIns = {};
  String? error;
  late bool authenticated = widget.loggedIn;

  @override
  void initState() {
    super.initState();
    if (authenticated) {
      load();
    } else {
      loading = false;
    }
  }

  Future<void> load({bool retryPending = true}) async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await widget.api.get('family-groups');
      final data = response['data'];
      if (data is List && data.isNotEmpty && data.first is Map) {
        family = Map<String, dynamic>.from(data.first as Map);
      } else if (data is Map) {
        family = Map<String, dynamic>.from(data);
      } else {
        family = null;
      }
      final membershipResponse = await widget.api.get('family-memberships');
      final membershipData = membershipResponse['data'];
      memberships = membershipData is List
          ? membershipData
                .whereType<Map>()
                .map(Map<String, dynamic>.from)
                .toList()
          : [];
    } catch (e) {
      if (mounted) error = '$e';
    }
    if (mounted) setState(() => loading = false);
    if (retryPending && mounted) {
      for (final membership in memberships) {
        final memberId = int.tryParse('${membership['id']}');
        if (memberId == null) continue;
        final requestId = await widget.api.storage.read(
          key: 'family_checkin_pending_$memberId',
        );
        if (requestId != null) {
          unawaited(_sendCheckIn(memberId, requestId, refresh: false));
        }
      }
    }
  }

  Future<void> signIn() async {
    await widget.onLogin();
    if (!mounted) return;
    final token = await widget.api.storage.read(key: 'token');
    if (token != null && mounted) {
      setState(() => authenticated = true);
      await load();
    }
  }

  Future<String?> _textDialog({
    required String title,
    String initial = '',
    required String label,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (_) =>
          _FamilyNameDialog(title: title, initial: initial, label: label),
    );
  }

  Future<Map<String, String>?> _memberDialog({
    Map<String, dynamic>? member,
  }) async {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _FamilyMemberDialog(member: member),
    );
  }

  Future<void> createFamily() async {
    final name = await _textDialog(
      title: 'Buat keluarga',
      label: 'Nama keluarga',
    );
    if (name == null) return;
    await _mutate(() async {
      await widget.api.post('family-groups', {'name': name});
      await load();
    });
  }

  Future<void> saveMember({Map<String, dynamic>? member}) async {
    final values = await _memberDialog(member: member);
    if (values == null || family == null) return;
    final groupId = '${family!['id']}';
    final memberId = member == null ? null : '${member['id']}';
    await _mutate(() async {
      if (memberId == null) {
        await widget.api.post('family-groups/$groupId/members', values);
      } else {
        await widget.api.put(
          'family-groups/$groupId/members/$memberId',
          values,
        );
      }
      await load();
    });
  }

  Future<void> _sendCheckIn(
    int memberId,
    String requestId, {
    bool refresh = true,
  }) async {
    if (pendingCheckIns.contains(memberId)) return;
    pendingCheckIns.add(memberId);
    if (mounted) setState(() {});
    try {
      await widget.api.post('family-members/$memberId/check-in', {
        'request_id': requestId,
      });
      await widget.api.storage.delete(key: 'family_checkin_pending_$memberId');
      if (mounted && refresh) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Konfirmasi tersimpan di server. Ini mencatat jawaban saat ini, bukan jaminan kondisi setelahnya.',
            ),
          ),
        );
      }
      if (mounted) await load(retryPending: false);
    } catch (e) {
      if (mounted && refresh) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tidak tersambung; konfirmasi disimpan sementara di perangkat dan akan dicoba lagi. $e',
            ),
          ),
        );
      }
    } finally {
      pendingCheckIns.remove(memberId);
      if (mounted) setState(() {});
    }
  }

  Future<void> checkIn(int memberId) async {
    final storageKey = 'family_checkin_pending_$memberId';
    var requestId = await widget.api.storage.read(key: storageKey);
    if (requestId == null) {
      final random = Random.secure();
      requestId = List.generate(
        32,
        (_) => random.nextInt(16).toRadixString(16),
      ).join();
      await widget.api.storage.write(key: storageKey, value: requestId);
    }
    await _sendCheckIn(memberId, requestId);
  }

  Future<void> configureReminder(Map<String, dynamic> member) async {
    final id = int.tryParse('${member['id']}');
    if (id == null) return;
    final currentEnabled = member['reminder_enabled'] == true;
    final initialHours =
        int.tryParse('${member['reminder_frequency_hours']}') ?? 24;
    final choice = await showDialog<(bool, int)>(
      context: context,
      builder: (dialogContext) {
        var enabled = currentEnabled;
        var hours = initialHours == 168 ? 168 : 24;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Pengaturan pengingat'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktifkan pengingat lokal'),
                  subtitle: const Text(
                    'Hanya pada perangkat ini; tidak dikirim sebagai push.',
                  ),
                  value: enabled,
                  onChanged: (value) => setDialogState(() => enabled = value),
                ),
                DropdownButtonFormField<int>(
                  initialValue: hours,
                  decoration: const InputDecoration(labelText: 'Frekuensi'),
                  items: const [
                    DropdownMenuItem(value: 24, child: Text('Setiap hari')),
                    DropdownMenuItem(value: 168, child: Text('Setiap 7 hari')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => hours = value ?? 24),
                ),
                const SizedBox(height: 8),
                Text(
                  'Zona waktu perangkat: ${FamilyReminderService.timezoneName}',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, (enabled, hours)),
                child: const Text('Simpan'),
              ),
            ],
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    if (choice.$1 && !await FamilyReminderService.requestPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Izin notifikasi ditolak. Pengingat tidak diaktifkan.',
            ),
          ),
        );
      }
      return;
    }
    await _mutate(() async {
      final response = await widget.api.patch('family-members/$id/reminders', {
        'enabled': choice.$1,
        'frequency_hours': choice.$2,
        'timezone': FamilyReminderService.timezoneName,
      });
      final data = response['data'] is Map
          ? Map<String, dynamic>.from(response['data'] as Map)
          : <String, dynamic>{};
      final nextAt = DateTime.tryParse('${data['next_reminder_at'] ?? ''}');
      try {
        await FamilyReminderService.schedule(
          memberId: id,
          memberName: '${member['name'] ?? 'anggota keluarga'}',
          enabled: choice.$1,
          frequencyHours: choice.$2,
          nextReminderAt: nextAt,
          timezone: '${data['timezone'] ?? FamilyReminderService.timezoneName}',
        );
      } catch (_) {
        if (choice.$1) {
          await widget.api.patch('family-members/$id/reminders', {
            'enabled': false,
            'frequency_hours': choice.$2,
            'timezone': FamilyReminderService.timezoneName,
          });
          throw const ApiException(
            'Pengaturan tersimpan tetapi jadwal lokal gagal dibuat; pengingat dinonaktifkan kembali.',
          );
        }
        rethrow;
      }
      await load();
    });
  }

  Future<void> createMemberInvitation(Map<String, dynamic> member) async {
    if (family == null) return;
    final result = await widget.api.post(
      'family-groups/${family!['id']}/members/${member['id']}/invitation',
      {},
    );
    final invitation = result['data'] is Map
        ? Map<String, dynamic>.from(result['data'] as Map)
        : <String, dynamic>{};
    final code = invitation['code']?.toString() ?? '';
    if (!mounted || code.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kode undangan keluarga'),
        content: SelectableText(
          'Bagikan kode ini secara pribadi kepada anggota. Kode berlaku 24 jam dan hanya dapat digunakan sekali.\n\n$code',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Tutup'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Kode undangan disalin.')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Salin'),
          ),
        ],
      ),
    );
  }

  Future<void> joinFamily() async {
    var code = '';
    final formKey = GlobalKey<FormState>();
    final submitted = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Gabung keluarga'),
        content: Form(
          key: formKey,
          child: TextFormField(
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Kode undangan'),
            validator: (value) => (value?.trim().isEmpty ?? true)
                ? 'Masukkan kode undangan.'
                : null,
            onSaved: (value) => code = value?.trim() ?? '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                formKey.currentState!.save();
                Navigator.pop(dialogContext, code);
              }
            },
            child: const Text('Gabung'),
          ),
        ],
      ),
    );
    if (submitted == null) return;
    await _mutate(() async {
      await widget.api.post('family-invitations/accept', {'code': submitted});
      await load();
    });
  }

  String checkInSummary(Map<String, dynamic> member) {
    final nextAt = DateTime.tryParse('${member['next_reminder_at'] ?? ''}');
    final overdue =
        member['overdue'] == true ||
        (member['reminder_enabled'] == true &&
            nextAt != null &&
            nextAt.isBefore(DateTime.now().toUtc()));
    final checkInAt = DateTime.tryParse('${member['check_in_at'] ?? ''}');
    if (overdue) {
      return 'Menunggu konfirmasi · terlambat jadwal, bukan keadaan darurat';
    }
    if (checkInAt == null) return 'Belum ada konfirmasi';
    return 'Sudah konfirmasi aman · ${checkInAt.toLocal()} (jawaban saat itu, bukan status saat ini)';
  }

  String reminderSummary(Map<String, dynamic> member) {
    if (member['reminder_enabled'] != true) return 'Pengingat nonaktif';
    final nextAt = DateTime.tryParse('${member['next_reminder_at'] ?? ''}');
    final frequency =
        int.tryParse('${member['reminder_frequency_hours']}') ?? 24;
    final frequencyLabel = frequency == 168 ? '7 hari' : '24 jam';
    return 'Pengingat lokal aktif setiap $frequencyLabel${nextAt == null ? '' : ' · berikutnya ${nextAt.toLocal()}'}';
  }

  Future<void> _mutate(Future<void> Function() action) async {
    if (!mounted) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) error = '$e';
    }
    if (mounted) setState(() => saving = false);
  }

  Future<void> removeMember(Map<String, dynamic> member) async {
    if (family == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus anggota?'),
        content: Text(
          'Hapus ${member['name'] ?? 'anggota ini'} dari kontak keluarga?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _mutate(() async {
      await widget.api.delete(
        'family-groups/${family!['id']}/members/${member['id']}',
      );
      await load();
    });
  }

  Future<void> removeFamily() async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus grup keluarga?'),
        content: const Text(
          'Grup dan daftar anggota tersimpan di dalamnya akan dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (remove != true || family == null) return;
    await _mutate(() async {
      await widget.api.delete('family-groups/${family!['id']}');
      family = null;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      flexibleSpace: const SiagaNowHeaderBackground(),
      title: const Text('Keluarga Siaga'),
      actions: [
        if (authenticated)
          IconButton(
            onPressed: saving ? null : load,
            icon: const Icon(Icons.refresh),
          ),
      ],
    ),
    body: SiagaNowPageBackground(
      child: !authenticated
          ? _FeatureLoginPrompt(
              onLogin: signIn,
              text: 'Masuk untuk membuat dan mengelola keluarga Anda.',
            )
          : loading
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: _LoadingSkeleton(rows: 3),
            )
          : error != null && family == null
          ? _FeatureError(text: error!, retry: load)
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Keluarga dan kontak darurat',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Data hanya dapat dilihat dan dikelola pemilik grup. Fitur ini tidak membagikan lokasi langsung atau mengirim peringatan.',
                ),
                const SizedBox(height: 16),
                if (error != null) _InlineError(error!),
                if (family == null) ...[
                  const _FeatureEmpty(
                    icon: Icons.family_restroom,
                    title: 'Belum ada grup keluarga',
                    message: 'Buat grup untuk menyimpan daftar anggota dan kontak darurat.',
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: saving ? null : createFamily,
                    icon: const Icon(Icons.add),
                    label: const Text('Buat grup keluarga'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: saving ? null : joinFamily,
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Gabung dengan kode undangan'),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF087354),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Color(0xFFD0F1DF),
                          child: Icon(
                            Icons.family_restroom,
                            color: Color(0xFF075B49),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            '${family!['name'] ?? 'Keluarga'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Kelola grup keluarga',
                          enabled: !saving,
                          icon: const Icon(
                            Icons.more_vert,
                            color: Colors.white,
                          ),
                          onSelected: (action) async {
                            if (action == 'rename') {
                              final name = await _textDialog(
                                title: 'Ubah nama keluarga',
                                label: 'Nama keluarga',
                                initial: '${family!['name'] ?? ''}',
                              );
                              if (name != null) {
                                await _mutate(() async {
                                  await widget.api.put(
                                    'family-groups/${family!['id']}',
                                    {'name': name},
                                  );
                                  await load();
                                });
                              }
                            } else {
                              await removeFamily();
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('Ubah nama'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Hapus grup'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Anggota',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: saving ? null : () => saveMember(),
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Tambah'),
                      ),
                    ],
                  ),
                  ...((family!['members'] is List)
                          ? (family!['members'] as List)
                          : const [])
                      .whereType<Map>()
                      .map((raw) {
                        final member = Map<String, dynamic>.from(raw);
                        final phone = member['emergency_phone']?.toString();
                        final notes = member['notes']?.toString();
                        final details = <String>[
                          if (member['relation']?.toString().isNotEmpty == true)
                            '${member['relation']}',
                          if (phone?.isNotEmpty == true)
                            'Kontak darurat: $phone',
                          if (notes?.isNotEmpty == true) 'Catatan: $notes',
                          checkInSummary(member),
                          reminderSummary(member),
                        ];
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFE7F6ED),
                              child: Icon(
                                Icons.person_outline,
                                color: Color(0xFF075B49),
                              ),
                            ),
                            title: Text('${member['name'] ?? 'Anggota'}'),
                            subtitle: Text(details.join('\n')),
                            trailing: PopupMenuButton<String>(
                              enabled: !saving,
                              onSelected: (action) {
                                if (action == 'edit') {
                                  saveMember(member: member);
                                } else if (action == 'invite') {
                                  _mutate(() => createMemberInvitation(member));
                                } else if (action == 'reminder') {
                                  configureReminder(member);
                                } else {
                                  removeMember(member);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Ubah'),
                                ),
                                if (member['user_id'] == null)
                                  const PopupMenuItem(
                                    value: 'invite',
                                    child: Text('Undang akun'),
                                  ),
                                const PopupMenuItem(
                                  value: 'reminder',
                                  child: Text('Pengingat'),
                                ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Hapus'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  if ((family!['members'] as List? ?? []).isEmpty)
                    const _FeatureEmpty(
                      icon: Icons.people_outline,
                      title: 'Belum ada anggota',
                      message: 'Tambahkan anggota dan kontak darurat yang Anda miliki izin untuk simpan.',
                    ),
                ],
                if (memberships.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Keluarga yang saya ikuti',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  for (final membership in memberships)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${(membership['group'] as Map?)?['name'] ?? 'Keluarga'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(checkInSummary(membership)),
                            const SizedBox(height: 6),
                            Text(reminderSummary(membership)),
                            const SizedBox(height: 8),
                            const Text(
                              'Konfirmasi mencatat jawaban pada waktu tersebut; ini bukan bukti kondisi Anda saat ini.',
                              style: TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            for (final raw
                                in (membership['members'] is List
                                        ? membership['members'] as List
                                        : const <Object>[])
                                    .whereType<Map>())
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
                                child: Text(
                                  '${raw['name']}: ${checkInSummary(Map<String, dynamic>.from(raw))}',
                                ),
                              ),
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed:
                                      saving ||
                                          pendingCheckIns.contains(
                                            int.tryParse('${membership['id']}'),
                                          )
                                      ? null
                                      : () => checkIn(
                                          int.parse('${membership['id']}'),
                                        ),
                                  icon:
                                      pendingCheckIns.contains(
                                        int.tryParse('${membership['id']}'),
                                      )
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.health_and_safety_outlined,
                                        ),
                                  label: const Text('Saya Aman'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: saving
                                      ? null
                                      : () => configureReminder(membership),
                                  icon: const Icon(
                                    Icons.notifications_active_outlined,
                                  ),
                                  label: const Text('Pengingat'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (saving) const LinearProgressIndicator(),
              ],
            ),
    ),
  );
}

class RiskAssessmentPage extends StatefulWidget {
  const RiskAssessmentPage({
    super.key,
    required this.api,
    required this.loggedIn,
    required this.onLogin,
  });
  final ApiService api;
  final bool loggedIn;
  final Future<void> Function() onLogin;

  @override
  State<RiskAssessmentPage> createState() => _RiskAssessmentPageState();
}

class _RiskAssessmentPageState extends State<RiskAssessmentPage> {
  final form = GlobalKey<FormState>();
  final latitude = TextEditingController();
  final longitude = TextEditingController();
  final distance = TextEditingController();
  final elevation = TextEditingController();
  List<dynamic> assessments = [];
  bool loading = true, submitting = false, gettingLocation = false;
  String? error;
  bool? floodHistory, landslideHistory;
  String rainfall = 'unknown';
  late bool authenticated = widget.loggedIn;

  @override
  void initState() {
    super.initState();
    if (authenticated) {
      load();
    } else {
      loading = false;
    }
  }

  @override
  void dispose() {
    latitude.dispose();
    longitude.dispose();
    distance.dispose();
    elevation.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await widget.api.get('risk-assessments');
      assessments = response['data'] is List ? response['data'] as List : [];
    } catch (e) {
      if (mounted) error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> signIn() async {
    await widget.onLogin();
    if (!mounted) return;
    final token = await widget.api.storage.read(key: 'token');
    if (token != null && mounted) {
      setState(() => authenticated = true);
      await load();
    }
  }

  Future<void> useLocation() async {
    setState(() => gettingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const ApiException(
          'Aktifkan GPS atau masukkan koordinat secara manual.',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const ApiException(
          'Izin lokasi ditolak. Masukkan koordinat secara manual.',
        );
      }
      final point = await Geolocator.getCurrentPosition();
      latitude.text = point.latitude.toStringAsFixed(7);
      longitude.text = point.longitude.toStringAsFixed(7);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    if (mounted) setState(() => gettingLocation = false);
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    if (!authenticated) {
      await signIn();
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final result = await widget.api.post('risk-assessments', {
        'latitude': double.parse(latitude.text),
        'longitude': double.parse(longitude.text),
        if (distance.text.trim().isNotEmpty)
          'distance_to_river': double.parse(distance.text),
        if (elevation.text.trim().isNotEmpty)
          'elevation': double.parse(elevation.text),
        if (floodHistory != null) 'flood_history': floodHistory,
        if (landslideHistory != null) 'landslide_history': landslideHistory,
        'rainfall_category': rainfall,
      });
      final assessment = result['data'];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              assessment is Map
                  ? 'Pemeriksaan tersimpan dengan status ${assessment['status'] ?? 'pending'}.'
                  : 'Permintaan tersimpan.',
            ),
          ),
        );
        await load();
      }
    } catch (e) {
      if (mounted) error = '$e';
    }
    if (mounted) setState(() => submitting = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      flexibleSpace: const SiagaNowHeaderBackground(),
      title: const Text('Penilaian Risiko'),
      actions: [
        if (authenticated)
          IconButton(
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
          ),
      ],
    ),
    body: SiagaNowPageBackground(
      child: !authenticated
          ? _FeatureLoginPrompt(
              onLogin: signIn,
              text:
                  'Masuk untuk menyimpan dan melihat pemeriksaan risiko Anda.',
            )
          : loading
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: _LoadingSkeleton(rows: 3),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Pemeriksaan berbasis lokasi',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const _InfoBanner(
                  text: 'Permintaan ini disimpan sebagai pending. SiagaNow belum memiliki skor risiko terverifikasi, peta bahaya, atau klasifikasi aman/tidak aman.',
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Lokasi',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: latitude,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Latitude',
                                  ),
                                  validator: (v) =>
                                      _coordinateValue(v, -90, 90),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: longitude,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                  decoration: const InputDecoration(
                                    labelText: 'Longitude',
                                  ),
                                  validator: (v) =>
                                      _coordinateValue(v, -180, 180),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: gettingLocation ? null : useLocation,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (gettingLocation)
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  else
                                    const Icon(Icons.my_location),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Gunakan lokasi perangkat',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(height: 28),
                          const Text(
                            'Informasi yang Anda ketahui (opsional)',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: distance,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText:
                                  'Jarak ke sungai (meter, jika diketahui)',
                            ),
                            validator: _optionalNumber,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: elevation,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Ketinggian (meter, jika diketahui)',
                            ),
                            validator: _optionalNumber,
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<bool?>(
                            initialValue: floodHistory,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Riwayat banjir',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('Belum diketahui'),
                              ),
                              DropdownMenuItem(value: true, child: Text('Ya')),
                              DropdownMenuItem(
                                value: false,
                                child: Text('Tidak'),
                              ),
                            ],
                            onChanged: (v) => setState(() => floodHistory = v),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<bool?>(
                            initialValue: landslideHistory,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Riwayat longsor',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('Belum diketahui'),
                              ),
                              DropdownMenuItem(value: true, child: Text('Ya')),
                              DropdownMenuItem(
                                value: false,
                                child: Text('Tidak'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => landslideHistory = v),
                          ),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            initialValue: rainfall,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Kategori curah hujan',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'unknown',
                                child: Text('Belum diketahui'),
                              ),
                              DropdownMenuItem(
                                value: 'low',
                                child: Text('Rendah'),
                              ),
                              DropdownMenuItem(
                                value: 'moderate',
                                child: Text('Sedang'),
                              ),
                              DropdownMenuItem(
                                value: 'high',
                                child: Text('Tinggi'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => rainfall = v ?? 'unknown'),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: submitting ? null : submit,
                              icon: submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.fact_check_outlined),
                              label: Text(
                                submitting
                                    ? 'Menyimpan…'
                                    : 'Simpan pemeriksaan',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  _InlineError(error!),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Riwayat pemeriksaan',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                if (assessments.isEmpty)
                  const _FeatureEmpty(
                    icon: Icons.history,
                    title: 'Belum ada pemeriksaan',
                    message:
                        'Pemeriksaan yang Anda simpan akan muncul di sini.',
                  ),
                ...assessments.whereType<Map>().map((raw) {
                  final item = Map<String, dynamic>.from(raw);
                  final limits = item['limitations'] is List
                      ? (item['limitations'] as List)
                            .map((e) => '$e')
                            .join('\n')
                      : 'Data pembanding terverifikasi belum lengkap.';
                  return Card(
                    child: ExpansionTile(
                      title: Text('Status: ${item['status'] ?? 'pending'}'),
                      subtitle: Text(
                        'Lokasi ${item['latitude'] ?? '—'}, ${item['longitude'] ?? '—'} · ${item['created_at'] ?? ''}',
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Hasil'),
                              Text(
                                item['result'] == null
                                    ? 'Tidak ada skor atau klasifikasi yang dihitung.'
                                    : '${item['result']}',
                              ),
                              const SizedBox(height: 8),
                              const Text('Batasan data'),
                              Text(limits),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    ),
  );

  String? _coordinateValue(String? value, double min, double max) {
    final number = double.tryParse(value ?? '');
    return number == null || number < min || number > max
        ? 'Masukkan titik antara $min dan $max.'
        : null;
  }

  String? _optionalNumber(String? value) =>
      value == null || value.trim().isEmpty || double.tryParse(value) != null
      ? null
      : 'Masukkan angka yang valid.';
}

class _FeatureLoginPrompt extends StatelessWidget {
  const _FeatureLoginPrompt({required this.onLogin, required this.text});
  final VoidCallback onLogin;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 46, color: Color(0xFF075B49)),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onLogin,
            icon: const Icon(Icons.login),
            label: const Text('Masuk'),
          ),
        ],
      ),
    ),
  );
}

class _FeatureEmpty extends StatelessWidget {
  const _FeatureEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title, message;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 10),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: SiagaNowSurfaceTokens.mintInfo,
      borderRadius: BorderRadius.circular(SiagaNowSurfaceTokens.panelRadius),
      border: Border.all(color: SiagaNowSurfaceTokens.border),
    ),
    child: Column(
      children: [
        Icon(icon, size: 38, color: const Color(0xFF39856B)),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}

class _FeatureError extends StatelessWidget {
  const _FeatureError({required this.text, required this.retry});
  final String text;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba lagi'),
          ),
        ],
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: SiagaNowSurfaceTokens.error,
      borderRadius: BorderRadius.circular(SiagaNowSurfaceTokens.panelRadius),
      border: Border.all(color: const Color(0x668E3333)),
    ),
    child: Text(text, style: const TextStyle(color: Color(0xFF8E3333))),
  );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: SiagaNowSurfaceTokens.notice,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: Color(0xFF85661B)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(color: Color(0xFF765B1C))),
        ),
      ],
    ),
  );
}

class _SimulationNotice extends StatelessWidget {
  const _SimulationNotice();

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: SiagaNowSurfaceTokens.simulationNotice,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFECCB82)),
    ),
    padding: const EdgeInsets.all(12),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.science_outlined, color: Color(0xFF9A650D)),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            'SIMULASI — BUKAN SHELTER RESMI. Satu titik latihan untuk menguji marker, jarak GPS, dan arah eksternal. Tidak ada kapasitas atau status operasional yang diklaim.',
            style: TextStyle(color: Color(0xFF765B1C), height: 1.35),
          ),
        ),
      ],
    ),
  );
}

class _ProfileMenuButton extends StatelessWidget {
  const _ProfileMenuButton({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Material(
      color: const Color(0xFF01543F),
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      shadowColor: const Color(0x44000000),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 46),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 19, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white, size: 25),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.api,
    required this.onLogin,
    required this.onLogout,
    this.photoService,
  });
  final ApiService api;
  final VoidCallback onLogin;
  final Future<void> Function() onLogout;
  final ProfilePhotoService? photoService;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ProfilePhotoService _photoService =
      widget.photoService ?? ProfilePhotoService();
  UserProfile? profile;
  File? profilePhoto;
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
    _loadProfilePhoto();
  }

  Future<void> _loadProfilePhoto() async {
    try {
      final photo = await _photoService.loadSavedPhoto();
      if (mounted) setState(() => profilePhoto = photo);
    } catch (_) {
      // A missing or inaccessible local photo should not block profile data.
    }
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.get('user');
      profile = UserProfile.fromJson(
        Map<String, dynamic>.from(result['data'] as Map),
      );
    } catch (e) {
      error = '$e';
      if (e is ApiException && (e.statusCode == 401 || e.statusCode == 403)) {
        widget.onLogin();
      }
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFCDEBDD),
    appBar: AppBar(
      key: const ValueKey('profile.standard-appbar'),
      backgroundColor: const Color(0xFFCDEBDD),
      toolbarHeight: 92,
      flexibleSpace: const SiagaNowHeaderBackground(),
      leading: IconButton(
        tooltip: 'Kembali',
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
        color: Colors.white,
      ),
      actions: [
        IconButton(
          tooltip: 'Muat ulang profil',
          onPressed: loading ? null : load,
          icon: const Icon(Icons.refresh),
          color: Colors.white,
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: DecoratedBox(
      key: const ValueKey('profile.scroll-background'),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF24785D),
            Color(0xFF479979),
            Color(0xFF9BD0B4),
            Color(0xFFCDEBDD),
          ],
          stops: [0, .18, .48, .78],
        ),
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: _LoadingSkeleton(rows: 3),
            )
          : error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _InlineError(error!),
              ),
            )
          : _buildProfileContent(context),
    ),
  );

  Widget _buildProfileContent(BuildContext context) => ListView(
    key: const ValueKey('profile.scroll-content'),
    padding: const EdgeInsets.fromLTRB(26, 16, 26, 24),
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Semantics(
            button: true,
            label: profilePhoto == null
                ? 'Pilih foto profil'
                : 'Ganti foto profil',
            child: InkWell(
              key: const ValueKey('profile.avatar'),
              customBorder: const CircleBorder(),
              onTap: _pickProfilePhoto,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFD9F3E5),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                  image: profilePhoto == null
                      ? null
                      : DecorationImage(
                          image: FileImage(profilePhoto!),
                          fit: BoxFit.cover,
                        ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (profilePhoto == null)
                      const Icon(
                        Icons.person_outline_rounded,
                        color: Color(0xFF01543F),
                        size: 54,
                      ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF01543F),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(5),
                          child: Icon(
                            Icons.camera_alt_outlined,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile?.name.isNotEmpty == true
                      ? profile!.name
                      : 'Nama belum tersedia',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(color: Color(0x55000000), blurRadius: 4)],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  profile?.email?.isNotEmpty == true
                      ? profile!.email!
                      : 'Email belum tersedia',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF3FFF8),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF01543F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(0, 38),
                    ),
                    onPressed: _showProfilePhotoOptions,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xDFFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x55FFFFFF)),
        ),
        child: Column(
          children: [
            _ProfileInfoLine(
              icon: Icons.phone_outlined,
              label: 'Nomor telepon',
              value: profile?.phone?.isNotEmpty == true
                  ? profile!.phone!
                  : 'Belum tersedia',
            ),
            const Divider(height: 1),
            _ProfileInfoLine(
              icon: Icons.location_on_outlined,
              label: 'Alamat',
              value: profile?.address?.isNotEmpty == true
                  ? profile!.address!
                  : 'Belum tersedia',
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const _ProfileSectionLabel('Aktivitas'),
      const SizedBox(height: 8),
      _ProfileMenuButton(
        icon: Icons.volunteer_activism_outlined,
        title: 'Informasi Donasi',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DonationPage(
              repository: ApiDonationRepository(
                fetchCampaigns: () => widget.api.get('donation-campaigns'),
              ),
              loggedIn: profile != null,
              onLogin: () async => widget.onLogin(),
            ),
          ),
        ),
      ),
      _ProfileMenuButton(
        icon: Icons.assignment_outlined,
        title: 'Laporan Bencana Saya',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ReportHistoryPage(api: widget.api, onLogin: widget.onLogin),
          ),
        ),
      ),
      _ProfileMenuButton(
        icon: Icons.emergency_outlined,
        title: 'Kontak Darurat',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EmergencyContactsPage()),
        ),
      ),
      _ProfileMenuButton(
        icon: Icons.grid_view_rounded,
        title: 'Layanan dan fitur lainnya',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MorePage(
              api: widget.api,
              loggedIn: profile != null,
              onLogin: () async => widget.onLogin(),
              onLogout: widget.onLogout,
            ),
          ),
        ),
      ),
      const SizedBox(height: 7),
      const _ProfileSectionLabel('Pengaturan'),
      const SizedBox(height: 8),
      _ProfileMenuButton(
        icon: Icons.notifications_none_outlined,
        title: 'Notifikasi',
        onTap: () => _showUnavailable(
          context,
          'Notifikasi',
          'Pengaturan notifikasi untuk akun belum tersedia di aplikasi ini.',
        ),
      ),
      _ProfileMenuButton(
        icon: Icons.palette_outlined,
        title: 'Gaya & Tampilan',
        onTap: () => _showUnavailable(
          context,
          'Gaya & Tampilan',
          'Pengaturan tampilan belum tersedia.',
        ),
      ),
      _ProfileMenuButton(
        icon: Icons.privacy_tip_outlined,
        title: 'Privasi dan Keamanan',
        onTap: () => _showUnavailable(
          context,
          'Privasi dan Keamanan',
          'Data akun dan laporan dikirim ke API SiagaNow. Data keluarga hanya dapat diakses pemilik grup.',
        ),
      ),
      _ProfileMenuButton(
        icon: Icons.help_outline,
        title: 'Pusat Bantuan',
        onTap: () => _showUnavailable(
          context,
          'Pusat Bantuan',
          'Informasi bantuan belum tersedia di aplikasi ini.',
        ),
      ),
      _ProfileMenuButton(
        icon: Icons.info_outline,
        title: 'Tentang SiagaNow',
        onTap: () => _showUnavailable(
          context,
          'Tentang SiagaNow',
          'SiagaNow menghubungkan informasi kesiapsiagaan dengan layanan API yang tersedia. Informasi simulasi bukan peringatan resmi.',
        ),
      ),
      const SizedBox(height: 14),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE94437),
            foregroundColor: Colors.white,
            minimumSize: const Size(96, 48),
            padding: const EdgeInsets.symmetric(horizontal: 18),
          ),
          onPressed: () async {
            final shouldLogout = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Keluar dari akun?'),
                content: const Text('Anda dapat masuk kembali kapan saja.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Batal'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Keluar'),
                  ),
                ],
              ),
            );
            if (shouldLogout != true || !context.mounted) return;
            await widget.onLogout();
            if (context.mounted) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.logout, size: 18),
          label: const Text(
            'Keluar',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ],
  );

  Future<void> _showProfilePhotoOptions() async {
    final action = await showDialog<_ProfilePhotoAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFFCFFFD),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Edit profil',
          style: TextStyle(color: Color(0xFF15392F)),
        ),
        content: Text(
          'Nama, email, nomor telepon, dan alamat ditampilkan dari akun server. Anda dapat mengelola foto profil di perangkat ini.',
          style: TextStyle(color: Color(0xFF44685A)),
        ),
        actions: [
          TextButton.icon(
            onPressed: () =>
                Navigator.pop(dialogContext, _ProfilePhotoAction.replace),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Ganti Foto Profil'),
          ),
          TextButton.icon(
            onPressed: profilePhoto == null
                ? null
                : () =>
                      Navigator.pop(dialogContext, _ProfilePhotoAction.remove),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Hapus Foto Profil'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _ProfilePhotoAction.close),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
    switch (action) {
      case _ProfilePhotoAction.replace:
        await _pickProfilePhoto();
      case _ProfilePhotoAction.remove:
        await _removeProfilePhoto();
      case _ProfilePhotoAction.close:
      case null:
        break;
    }
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final picked = await _photoService.pickFromGallery();
      if (picked == null || !mounted) return;
      final file = File(picked.path);
      await _photoService.validatePhoto(file);
      if (!mounted) return;
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFFFCFFFD),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Pratinjau foto profil',
            style: TextStyle(color: Color(0xFF15392F)),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipOval(
                child: Image.file(
                  file,
                  width: 184,
                  height: 184,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 184,
                    height: 184,
                    child: Icon(Icons.broken_image_outlined, size: 48),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Foto akan disimpan di perangkat ini. Maksimal 10 MB.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF44685A), fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Simpan Foto'),
            ),
          ],
        ),
      );
      if (shouldSave != true || !mounted) return;
      final saved = await _photoService.savePhoto(file);
      if (!mounted) return;
      setState(() => profilePhoto = saved);
      _showProfilePhotoMessage('Foto profil tersimpan di perangkat ini.');
    } on ProfilePhotoException catch (e) {
      if (mounted) _showProfilePhotoMessage(e.message);
    } catch (_) {
      if (mounted) {
        _showProfilePhotoMessage('Foto tidak dapat dipilih atau disimpan.');
      }
    }
  }

  Future<void> _removeProfilePhoto() async {
    try {
      await _photoService.deletePhoto();
      if (!mounted) return;
      setState(() => profilePhoto = null);
      _showProfilePhotoMessage('Foto profil dihapus dari perangkat ini.');
    } catch (_) {
      if (mounted) {
        _showProfilePhotoMessage('Foto profil tidak dapat dihapus.');
      }
    }
  }

  void _showProfilePhotoMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _ProfilePhotoAction { replace, remove, close }

class _ProfileSectionLabel extends StatelessWidget {
  const _ProfileSectionLabel(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: const TextStyle(
      color: Color(0xFF01543F),
      fontSize: 13,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _ProfileInfoLine extends StatelessWidget {
  const _ProfileInfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF01543F)),
        const SizedBox(width: 10),
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF44685A),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF15392F),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class NewsPage extends StatefulWidget {
  const NewsPage({super.key, required this.api});
  final ApiService api;
  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  static const _pageSize = 5;
  bool loading = true;
  String? error;
  List<dynamic> articles = [];
  String? type;
  int currentPage = 1;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await widget.api.get('news');
      articles = response['data'] is List ? response['data'] as List : [];
      type = response['data_type']?.toString();
      final pageCount = (articles.length / _pageSize).ceil();
      if (pageCount == 0) {
        currentPage = 1;
      } else if (currentPage > pageCount) {
        currentPage = pageCount;
      }
    } catch (e) {
      error = '$e';
      articles = [];
    }
    if (mounted) setState(() => loading = false);
  }

  void _openArticle(Map<String, dynamic> article) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => NewsDetailPage(
        article: article,
        simulation: type == 'simulation' || article['is_simulated'] == true,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pageCount = (articles.length / _pageSize).ceil();
    final pageItems = articles
        .skip((currentPage - 1) * _pageSize)
        .take(_pageSize)
        .toList();
    final hero = articles.isNotEmpty
        ? Map<String, dynamic>.from(articles.first as Map)
        : null;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          const Text(
            'Berita Terbaru',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          if (type == 'simulation')
            const Padding(padding: EdgeInsets.only(top: 8), child: DemoBadge()),
          if (loading)
            const _LoadingSkeleton(rows: 3)
          else if (hero != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _HomeNewsCard(
                item: hero,
                simulation:
                    type == 'simulation' || hero['is_simulated'] == true,
                onTap: () => _openArticle(hero),
              ),
            )
          else
            _EmptyState(
              text: error ?? 'Belum tersedia berita kejadian terverifikasi.',
            ),
          const SizedBox(height: 18),
          const Text(
            'Semua Berita',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          if (!loading)
            ...pageItems.asMap().entries.map((entry) {
              final index = (currentPage - 1) * _pageSize + entry.key;
              final article = Map<String, dynamic>.from(entry.value as Map);
              final image = article['image_url'] ?? article['image'];
              final remoteImage = image is String && image.startsWith('http');
              final simulated =
                  type == 'simulation' || article['is_simulated'] == true;
              final date = article['published_at']?.toString();
              final location = article['location']?.toString();
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(10),
                  leading: SizedBox(
                    width: 72,
                    height: 88,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: remoteImage
                          ? Image.network(
                              image,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.article_outlined),
                            )
                          : simulated
                          ? Image.asset(
                              index.isEven
                                  ? 'assets/images/news_flooded_home.jpg'
                                  : 'assets/images/news_flood_damage.jpg',
                              fit: BoxFit.cover,
                            )
                          : const Icon(Icons.article_outlined),
                    ),
                  ),
                  title: Text(
                    '${article['title'] ?? 'Informasi'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${article['summary'] ?? article['description'] ?? 'Ringkasan belum tersedia.'}',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${date == null ? 'Tanggal belum tersedia' : date.split('T').first} · ${location?.isNotEmpty == true ? location : 'Lokasi tidak tersedia'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openArticle(article),
                ),
              );
            }),
          if (!loading && pageCount > 1) ...[
            const SizedBox(height: 8),
            _NewsPagination(
              currentPage: currentPage,
              pageCount: pageCount,
              onSelected: (page) => setState(() => currentPage = page),
            ),
          ],
          if (error != null && articles.isNotEmpty)
            Text(error!, style: const TextStyle(color: Color(0xFF8B342D))),
        ],
      ),
    );
  }
}

class _NewsPagination extends StatelessWidget {
  const _NewsPagination({
    required this.currentPage,
    required this.pageCount,
    required this.onSelected,
  });

  final int currentPage;
  final int pageCount;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final pages = <int>{
      1,
      currentPage - 1,
      currentPage,
      currentPage + 1,
      pageCount,
    }.where((page) => page >= 1 && page <= pageCount).toList()..sort();
    final children = <Widget>[
      IconButton(
        tooltip: 'Halaman sebelumnya',
        onPressed: currentPage > 1 ? () => onSelected(currentPage - 1) : null,
        icon: const Icon(Icons.chevron_left),
      ),
    ];
    var previous = 0;
    for (final page in pages) {
      if (previous > 0 && page - previous > 1) {
        children.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Text('…'),
          ),
        );
      }
      children.add(
        Semantics(
          button: true,
          selected: page == currentPage,
          label: 'Halaman $page',
          child: TextButton(
            onPressed: () => onSelected(page),
            style: TextButton.styleFrom(
              foregroundColor: page == currentPage
                  ? Colors.white
                  : const Color(0xFF01543F),
              backgroundColor: page == currentPage
                  ? const Color(0xFF01543F)
                  : Colors.transparent,
              minimumSize: const Size(34, 38),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text('$page'),
          ),
        ),
      );
      previous = page;
    }
    children.add(
      IconButton(
        tooltip: 'Halaman berikutnya',
        onPressed: currentPage < pageCount
            ? () => onSelected(currentPage + 1)
            : null,
        icon: const Icon(Icons.chevron_right),
      ),
    );
    return Align(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}

class NewsDetailPage extends StatelessWidget {
  const NewsDetailPage({
    super.key,
    required this.article,
    required this.simulation,
  });
  final Map<String, dynamic> article;
  final bool simulation;
  @override
  Widget build(BuildContext context) {
    final image = article['image_url'] ?? article['image'];
    final imageUrl = image is String && image.startsWith('http') ? image : null;
    final imageAsset = _demoNewsImageAsset(article['image_key']);
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const SiagaNowHeaderBackground(),
        title: const Text('Detail berita'),
      ),
      body: SiagaNowPageBackground(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (imageAsset != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(imageAsset, height: 210, fit: BoxFit.cover),
              ),
            if (imageAsset == null && imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  imageUrl,
                  height: 210,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 90,
                    child: Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
            if (imageAsset == null && imageUrl == null && simulation)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/news_flooded_home.jpg',
                  height: 210,
                  fit: BoxFit.cover,
                ),
              ),
            if (simulation)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: DemoBadge(),
              ),
            Text(
              '${article['title'] ?? 'Informasi kebencanaan'}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              '${article['source'] ?? 'Sumber tidak dicantumkan'} · ${article['published_at'] ?? 'tanggal tidak tersedia'}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF68756B)),
            ),
            const SizedBox(height: 18),
            Text(
              '${article['summary'] ?? article['description'] ?? 'Ringkasan belum tersedia.'}',
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
            if (article['image_caption'] != null) ...[
              const SizedBox(height: 8),
              Text(
                '${article['image_caption']}',
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ],
            if (article['image_credit'] != null) ...[
              const SizedBox(height: 4),
              Text(
                'Foto: ${article['image_credit']}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF68756B)),
              ),
            ],
            if (article['location'] != null) ...[
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.place_outlined),
                title: Text('${article['location']}'),
              ),
            ],
            if (simulation)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Konten simulasi. Jangan gunakan sebagai peringatan atau laporan kejadian resmi.',
                  style: TextStyle(
                    color: Color(0xFF765B1C),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String? _demoNewsImageAsset(dynamic key) => switch (key) {
  'flood_jakarta' => 'assets/images/demo_flood_illustrative.jpg',
  'mountain_rain' => 'assets/images/demo_mountain_rain.jpg',
  _ => null,
};

class ReportDetailPage extends StatelessWidget {
  const ReportDetailPage({super.key, required this.report});
  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final injured = report['injured'];
    final deceased = report['deceased'];
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const SiagaNowHeaderBackground(),
        title: const Text('Detail laporan'),
      ),
      body: SiagaNowPageBackground(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${report['title'] ?? 'Laporan bencana'}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.fact_check_outlined),
                    title: const Text('Status'),
                    subtitle: Text('${report['status'] ?? 'Belum tersedia'}'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: const Text('Jenis kejadian'),
                    subtitle: Text(
                      '${report['event_type'] ?? 'Belum tersedia'}',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text('Waktu kejadian'),
                    subtitle: Text(
                      '${report['occurred_at'] ?? report['created_at'] ?? 'Belum tersedia'}',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: const Text('Koordinat'),
                    subtitle: Text(
                      '${report['latitude'] ?? '—'}, ${report['longitude'] ?? '—'}',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.construction_outlined),
                    title: const Text('Dampak yang dilaporkan'),
                    subtitle: Text(
                      '${report['damage_level'] ?? 'Belum tersedia'}',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.health_and_safety_outlined),
                    title: const Text('Korban luka / meninggal'),
                    subtitle: Text(
                      '${injured ?? 'Belum diketahui'} / ${deceased ?? 'Belum diketahui'}',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Deskripsi',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${report['description'] ?? 'Deskripsi tidak tersedia.'}',
                    ),
                  ],
                ),
              ),
            ),
            const _InfoBanner(
              text: 'Laporan merupakan kiriman pengguna dan menunggu pemeriksaan petugas. Status ini bukan peringatan resmi.',
            ),
            if (report['ai_analysis'] is Map) ...[
              const SizedBox(height: 12),
              _ReportAiStatusCard(
                analysis: ReportAiAnalysis.fromJson(report['ai_analysis']),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ReportHistoryPage extends StatefulWidget {
  const ReportHistoryPage({
    super.key,
    required this.api,
    required this.onLogin,
  });
  final ApiService api;
  final VoidCallback onLogin;
  @override
  State<ReportHistoryPage> createState() => _ReportHistoryPageState();
}

class _ReportHistoryPageState extends State<ReportHistoryPage> {
  bool loading = true;
  String? error;
  List<dynamic> reports = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.get('reports');
      reports = result['data'] is List ? result['data'] as List : [];
    } catch (e) {
      error = '$e';
      if (e is ApiException && (e.statusCode == 401 || e.statusCode == 403)) {
        widget.onLogin();
      }
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      flexibleSpace: const SiagaNowHeaderBackground(),
      title: const Text('Laporan saya'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
    ),
    body: SiagaNowPageBackground(
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: _LoadingSkeleton(rows: 3),
            )
          : error != null
          ? _EmptyState(text: error!)
          : reports.isEmpty
          ? const _EmptyState(
              text: 'Belum ada laporan tersimpan pada akun ini.',
            )
          : ListView(
              children: reports
                  .map(
                    (r) => Card(
                      child: ListTile(
                        title: Text('${r['title'] ?? 'Laporan'}'),
                        subtitle: Text(
                          'Status ${r['status'] ?? '—'} · ${r['created_at'] ?? ''}\n${r['ai_analysis'] is Map ? ReportAiAnalysis.fromJson(r['ai_analysis']).label : 'Status analisis AI belum tersedia'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ReportDetailPage(
                              report: Map<String, dynamic>.from(r as Map),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
    ),
  );
}

class AuthSheet extends StatefulWidget {
  const AuthSheet({super.key, required this.api});
  final ApiService api;
  @override
  State<AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<AuthSheet> {
  final form = GlobalKey<FormState>();
  final identifier = TextEditingController();
  final password = TextEditingController();
  final name = TextEditingController(),
      phone = TextEditingController(),
      email = TextEditingController(),
      confirmation = TextEditingController();
  bool busy = false, registering = false, passwordVisible = false;
  String? error;
  @override
  void dispose() {
    identifier.dispose();
    password.dispose();
    name.dispose();
    phone.dispose();
    email.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final result = registering
          ? await widget.api.post('register', {
              'name': name.text.trim(),
              'phone': phone.text.trim(),
              'email': email.text.trim(),
              'password': password.text,
              'password_confirmation': confirmation.text,
            })
          : await widget.api.post('login', {
              'identifier': identifier.text.trim(),
              'password': password.text,
            });
      final token = result['token']?.toString();
      if (token == null || token.isEmpty) {
        throw const ApiException('Server tidak mengembalikan token.');
      }
      await widget.api.storage.write(key: 'token', value: token);
      try {
        final profile = await widget.api.get('user');
        final data = profile['data'] is Map
            ? Map<String, dynamic>.from(profile['data'] as Map)
            : <String, dynamic>{};
        if (mounted) Navigator.pop(context, data);
      } catch (e) {
        await widget.api.storage.delete(key: 'token');
        rethrow;
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      22,
      16,
      22,
      MediaQuery.viewInsetsOf(context).bottom + 22,
    ),
    child: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              registering ? 'Buat akun SiagaNow' : 'Selamat Datang',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              registering
                  ? 'Daftar menggunakan akun SiagaNow.'
                  : 'Masuk menggunakan akun SiagaNow.',
            ),
            const SizedBox(height: 12),
            Center(
              child: Image.asset(
                'assets/illustrations/login_shield_landscape.png',
                height: 150,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 20),
            if (registering) ...[
              TextFormField(
                controller: name,
                decoration: const InputDecoration(
                  labelText: 'Nama lengkap',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Wajib diisi.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Nomor HP',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Wajib diisi.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || !v.contains('@')
                    ? 'Masukkan email yang valid.'
                    : null,
              ),
              const SizedBox(height: 12),
            ] else
              TextFormField(
                controller: identifier,
                decoration: _authInputDecoration(
                  labelText: 'Email atau nomor HP',
                  icon: Icons.person_outline,
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Wajib diisi.' : null,
              ),
            if (!registering) const SizedBox(height: 12),
            TextFormField(
              controller: password,
              obscureText: !passwordVisible,
              decoration: _authInputDecoration(
                labelText: 'Kata sandi',
                icon: Icons.lock_outline,
                suffixIcon: IconButton(
                  tooltip: passwordVisible
                      ? 'Sembunyikan kata sandi'
                      : 'Tampilkan kata sandi',
                  onPressed: () =>
                      setState(() => passwordVisible = !passwordVisible),
                  icon: Icon(
                    passwordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: (v) => v == null || v.isEmpty
                  ? 'Wajib diisi.'
                  : registering && v.length < 8
                  ? 'Minimal 8 karakter.'
                  : null,
            ),
            if (registering) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: confirmation,
                obscureText: !passwordVisible,
                decoration: InputDecoration(
                  labelText: 'Ulangi kata sandi',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: passwordVisible
                        ? 'Sembunyikan kata sandi'
                        : 'Tampilkan kata sandi',
                    onPressed: () =>
                        setState(() => passwordVisible = !passwordVisible),
                    icon: Icon(
                      passwordVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                validator: (v) =>
                    v != password.text ? 'Kata sandi tidak sama.' : null,
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : submit,
                child: Text(
                  busy
                      ? 'Memproses…'
                      : registering
                      ? 'Daftar'
                      : 'Masuk',
                ),
              ),
            ),
            if (!registering) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: null,
                  child: const Text('Lupa Kata Sandi? — Belum tersedia'),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF7EF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Gunakan Password sesuai dengan yang anda buat.',
                  style: TextStyle(color: Color(0xFF174B38)),
                ),
              ),
            ],
            Center(
              child: TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        registering = !registering;
                        error = null;
                      }),
                child: Text(
                  registering
                      ? 'Sudah punya akun? Masuk'
                      : 'Belum punya akun? Daftar',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  InputDecoration _authInputDecoration({
    required String labelText,
    required IconData icon,
    Widget? suffixIcon,
  }) => InputDecoration(
    labelText: labelText,
    border: const OutlineInputBorder(),
    prefixIcon: SizedBox(
      width: 52,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFD4F0E0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF01543F), size: 20),
        ),
      ),
    ),
    suffixIcon: suffixIcon,
  );
}

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4D7),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.science_outlined, size: 16, color: Color(0xFF85661B)),
        SizedBox(width: 7),
        Flexible(
          child: Text(
            'Data simulasi untuk demonstrasi — bukan informasi resmi',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF765B1C),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class QuickCard extends StatelessWidget {
  const QuickCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF145B45)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              subtitle,
              style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.icon,
    required this.title,
    required this.body,
    this.onTap,
  });
  final IconData icon;
  final String title, body;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 11),
    child: ListTile(
      contentPadding: const EdgeInsets.all(15),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFE7F1EA),
        child: Icon(icon, color: const Color(0xFF145B45)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(body),
      ),
      onTap: onTap,
      trailing: onTap == null
          ? null
          : Icon(
              icon == Icons.emergency_outlined
                  ? Icons.call_outlined
                  : Icons.chevron_right,
            ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      children: [
        const Icon(Icons.inbox_outlined, size: 36, color: Colors.blueGrey),
        const SizedBox(height: 8),
        Text(text, textAlign: TextAlign.center),
      ],
    ),
  );
}
