import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'dart:io' show Platform;

import 'package:path_provider/path_provider.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

const apiOverride = String.fromEnvironment('SIAGANOW_API_URL');
const demoMode = bool.fromEnvironment('SIAGANOW_DEMO_MODE', defaultValue: true);
const mapTileUrl = String.fromEnvironment(
  'SIAGANOW_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);
const appUserAgent = 'SiagaNowMobile/1.0';
const _defaultMapLatitude = double.fromEnvironment(
  'SIAGANOW_DEFAULT_LATITUDE',
  defaultValue: -0.9471,
);
const _defaultMapLongitude = double.fromEnvironment(
  'SIAGANOW_DEFAULT_LONGITUDE',
  defaultValue: 100.4172,
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
    final android = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin
    >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? true;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
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

class ShelterRecord {
  const ShelterRecord(
    this.name,
    this.address,
    this.source,
    this.verifiedAt,
    this.simulation,
    this.latitude,
    this.longitude,
  );
  final String name;
  final String address;
  final String? source;
  final String? verifiedAt;
  final bool simulation;
  final double? latitude;
  final double? longitude;
  bool get hasValidCoordinates => latitude != null && longitude != null;
  factory ShelterRecord.fromJson(
    Map<String, dynamic> json, {
    bool simulation = false,
  }) => ShelterRecord(
    (json['name'] ?? json['title'] ?? 'Titik informasi').toString(),
    (json['address'] ?? json['description'] ?? 'Lokasi belum dijelaskan')
        .toString(),
    json['source']?.toString(),
    json['verified_at']?.toString(),
    simulation,
    _coordinate(json['latitude'] ?? json['lat'], -90, 90),
    _coordinate(json['longitude'] ?? json['lng'] ?? json['lon'], -180, 180),
  );

  static double? _coordinate(Object? value, double min, double max) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    return parsed != null && parsed.isFinite && parsed >= min && parsed <= max
        ? parsed
        : null;
  }
}

class ReportReceipt {
  const ReportReceipt(this.id, this.status, this.message);
  final Object? id;
  final String status;
  final String message;
  factory ReportReceipt.fromJson(Map<String, dynamic> json) => ReportReceipt(
    json['id'],
    json['status']?.toString() ?? 'submitted',
    'Laporan #${json['id'] ?? '—'} tersimpan: ${json['status'] ?? 'submitted'}.',
  );
}

class WeatherPeriod {
  const WeatherPeriod({
    this.localDateTime,
    this.temperature,
    this.condition,
    this.humidity,
  });
  final String? localDateTime;
  final num? temperature;
  final String? condition;
  final int? humidity;
  factory WeatherPeriod.fromJson(Map<String, dynamic> json) => WeatherPeriod(
    localDateTime: json['local_datetime']?.toString(),
    temperature: num.tryParse('${json['temperature']}'),
    condition: json['condition']?.toString(),
    humidity: int.tryParse('${json['humidity']}'),
  );
}

class SiagaNowApp extends StatefulWidget {
  const SiagaNowApp({super.key});
  @override
  State<SiagaNowApp> createState() => _SiagaNowAppState();
}

class _SiagaNowAppState extends State<SiagaNowApp> {
  final storage = const FlutterSecureStorage();
  final navigatorKey = GlobalKey<NavigatorState>();
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final api = ApiService(storage);
  int tab = 0;
  String? userName;
  bool booting = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    String? token;
    try {
      token = await storage.read(key: 'token');
    } catch (_) {
      token = null;
    }
    if (token != null) {
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

  Future<void> _auth() async {
    final navigatorContext = navigatorKey.currentContext;
    if (navigatorContext == null) return;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: navigatorContext,
      isScrollControlled: true,
      builder: (_) => AuthSheet(api: api),
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
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFCFE3D8)),
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
          style: FilledButton.styleFrom(
            backgroundColor: forest,
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: booting
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : Scaffold(
              appBar: AppBar(
                backgroundColor: const Color(0xFFCDEBDD),
                flexibleSpace: Image.asset(
                  'assets/images/header_waves.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
                title: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: forest,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.shield_moon_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'SiagaNow',
                      style: TextStyle(fontWeight: FontWeight.w800),
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
              body: IndexedStack(
                index: tab,
                children: [
                  HomePage(
                    api: api,
                    onSelectTab: (i) => setState(() => tab = i),
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
                  ShelterPage(api: api),
                  ReportPage(
                    api: api,
                    loggedIn: userName != null,
                    onLogin: _requireLogin,
                  ),
                  NewsPage(api: api),
                  MorePage(
                    api: api,
                    loggedIn: userName != null,
                    onLogin: _requireLogin,
                    onLogout: _logout,
                  ),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                backgroundColor: const Color(0xDDF7FFF9),
                indicatorColor: const Color(0xFFB7E4D0),
                selectedIndex: tab,
                onDestinationSelected: (i) => setState(() => tab = i),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Beranda',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    selectedIcon: Icon(Icons.map),
                    label: 'Peta',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.add_location_alt_outlined),
                    selectedIcon: Icon(Icons.add_location_alt),
                    label: 'Laporan',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.article_outlined),
                    selectedIcon: Icon(Icons.article),
                    label: 'Berita',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.grid_view_rounded),
                    label: 'Lainnya',
                  ),
                ],
              ),
            ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.api,
    required this.onSelectTab,
    required this.onOpenFamily,
  });
  final ApiService api;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onOpenFamily;
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

  @override
  Widget build(BuildContext context) {
    final weather = data?['weather'];
    final stats = data?['statistics'];
    final isDemo =
        data?['data_type'] == 'simulation' || (data == null && demoMode);
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
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
              onTap: () => widget.onSelectTab(3),
            )
          else
            _HomeNewsEmpty(onTap: () => widget.onSelectTab(3)),
          const SizedBox(height: 18),
          _WarningStatusCard(
            warning: data?['warning'],
            loading: loading,
            error: error,
          ),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCFE3D8)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
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
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              'assets/images/landscape_background.png',
              height: 150,
              width: double.infinity,
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
            ),
          ),
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(9),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 218,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null)
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Color(0xFF6F9E86)),
                ),
              if (imageUrl == null && simulation)
                Image.asset(
                  'assets/images/news_flooded_home.jpg',
                  fit: BoxFit.cover,
                ),
              if (imageUrl == null && !simulation)
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
    color: Colors.white,
    borderRadius: BorderRadius.circular(9),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
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

class _WarningStatusCard extends StatelessWidget {
  const _WarningStatusCard({
    required this.warning,
    required this.loading,
    required this.error,
  });
  final dynamic warning;
  final bool loading;
  final String? error;
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
        : known
        ? 'Belum ada peringatan aktif yang dikirim oleh sumber ini.'
        : error ??
              '${values['message'] ?? 'Informasi peringatan resmi belum tersedia.'}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF4CECE)),
      ),
      child: Row(
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
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, height: 1.2),
                ),
              ],
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
      color: const Color(0xFFEAF9EF),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Cuaca dan peringatan')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF9EF),
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
          const SizedBox(height: 14),
          _WarningStatusCard(warning: warning, loading: false, error: null),
          const SizedBox(height: 20),
          const Text(
            'Prakiraan BMKG',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          if (forecasts.isEmpty)
            const _EmptyState(
              text: 'Interval prakiraan belum tersedia dari API.',
            )
          else
            ...forecasts.map(
              (period) => Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.cloud_outlined,
                    color: Color(0xFF397A60),
                  ),
                  title: Text(period.localDateTime ?? 'Waktu belum tersedia'),
                  subtitle: Text(
                    '${period.condition ?? 'Kondisi belum tersedia'}${period.humidity == null ? '' : ' · Kelembapan ${period.humidity}%'}',
                  ),
                  trailing: Text(
                    period.temperature == null ? '—' : '${period.temperature}°',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            'Prakiraan berlaku untuk wilayah administrasi dan bukan pengukuran di alamat rumah.',
            style: TextStyle(fontSize: 12, color: Color(0xFF68756B)),
          ),
        ],
      ),
    );
  }
}

class ShelterPage extends StatefulWidget {
  const ShelterPage({super.key, required this.api});
  final ApiService api;
  @override
  State<ShelterPage> createState() => _ShelterPageState();
}

class _ShelterPageState extends State<ShelterPage> {
  final search = TextEditingController();
  final mapController = MapController();
  static const _initialCenter = LatLng(
    _defaultMapLatitude,
    _defaultMapLongitude,
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
      places = (result['data'] is List ? result['data'] as List : [])
          .whereType<Map>()
          .map(
            (p) => ShelterRecord.fromJson(
              Map<String, dynamic>.from(p),
              simulation: dataType == 'simulation',
            ),
          )
          .toList();
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
    }
    requestPending = false;
    if (mounted) setState(() => loading = false);
  }

  Widget _mapUnavailable(String message) => Container(
    height: 300,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFE8EEE8),
      borderRadius: BorderRadius.circular(20),
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
      if (mapReady) mapController.move(point, 15);
    } on TimeoutException {
      userLocation = null;
      locationMessage =
          'GPS tidak merespons dalam 15 detik. Peta tetap dapat digunakan di lokasi peta terakhir atau default Padang.';
    } on LocationServiceDisabledException {
      userLocation = null;
      locationMessage =
          'GPS/lokasi perangkat nonaktif. Peta menggunakan lokasi peta terakhir atau default Padang; titik ini bukan posisi Anda.';
    } on PermissionDeniedException {
      userLocation = null;
      locationMessage =
          'Izin lokasi ditolak. Peta menggunakan lokasi peta terakhir atau default Padang; titik ini bukan posisi Anda.';
    } catch (error) {
      userLocation = null;
      locationMessage =
          'Lokasi tidak tersedia (${error.toString()}). Peta menggunakan lokasi peta terakhir atau default Padang; titik ini bukan posisi Anda.';
    } finally {
      if (mounted) {
        setState(() => locationLoading = false);
        if (!initialRequest && locationMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(locationMessage!)),
          );
        }
      }
    }
  }

  Future<void> openLocationSettings() async {
    await Geolocator.openAppSettings();
  }

  void showShelter(ShelterRecord place) {
    if (place.simulation || !place.hasValidCoordinates) {
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
      mapController.move(LatLng(place.latitude!, place.longitude!), 15);
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(place.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(place.address),
              const SizedBox(height: 12),
              Text(
                'Sumber: ${place.source ?? 'tidak tercatat'}\nVerifikasi: ${place.verifiedAt ?? 'belum tercatat'}',
              ),
              const SizedBox(height: 12),
              const Text('Rute dan kapasitas resmi tidak tersedia.'),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Peta evakuasi',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 7),
        Text(
          'Jelajahi titik informasi dan rencanakan kesiapsiagaan.',
          style: TextStyle(color: Colors.blueGrey.shade600),
        ),
        const SizedBox(height: 16),
        FutureBuilder<FileCacheStore>(
          future: _tileStore,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _mapUnavailable('Penyimpanan peta tidak dapat disiapkan.');
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
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 300,
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: mapController,
                      options: MapOptions(
                        initialCenter: _initialCenter,
                        initialZoom: 12,
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
                          userAgentPackageName: 'com.example.siaga_now_mobile',
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
              'Shelter tersedia',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            IconButton(
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: CircularProgressIndicator(),
            ),
          )
        else if (places.isEmpty)
          _EmptyState(text: issue ?? 'Belum ada tempat yang tercatat.')
        else
          ...places.map((p) {
            final simulated = p.simulation;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE7F1EA),
                  child: Icon(Icons.place_outlined, color: Color(0xFF145B45)),
                ),
                title: Text(
                  p.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  '${p.address}\n${simulated ? 'Simulasi · bukan shelter terverifikasi' : '${p.source ?? 'Sumber tidak tercatat'} · ${p.verifiedAt == null ? 'Belum diverifikasi' : 'Diverifikasi ${p.verifiedAt}'}'}',
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

class ReportPage extends StatefulWidget {
  const ReportPage({
    super.key,
    required this.api,
    required this.loggedIn,
    required this.onLogin,
  });
  final ApiService api;
  final bool loggedIn;
  final Future<void> Function() onLogin;
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
  String eventType = 'Banjir', damage = 'Rendah';
  DateTime occurredAt = DateTime.now();
  bool sending = false, gettingLocation = false, historyLoading = false;
  List<dynamic> reports = [];
  List<PlatformFile> evidence = [];
  @override
  void dispose() {
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
    if (widget.loggedIn) loadReports();
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
    if (!form.currentState!.validate()) return;
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
        'damage_level': damage,
        'description': description.text.trim(),
        if (injured.text.isNotEmpty) 'injured': injured.text,
        if (deceased.text.isNotEmpty) 'deceased': deceased.text,
      }, evidence);
      final receipt = ReportReceipt.fromJson(
        Map<String, dynamic>.from(result['data'] as Map),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(receipt.message)));
        title.clear();
        description.clear();
        evidence.clear();
        injured.clear();
        deceased.clear();
        await loadReports();
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
    padding: const EdgeInsets.all(20),
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
                  'Detail kejadian',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 14),
                _field(
                  title,
                  'Judul laporan',
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
                const SizedBox(height: 12),
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
                        label: Text(
                          '${occurredAt.year}-${occurredAt.month.toString().padLeft(2, '0')}-${occurredAt.day.toString().padLeft(2, '0')}',
                        ),
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
                        label: Text(
                          '${occurredAt.hour.toString().padLeft(2, '0')}:${occurredAt.minute.toString().padLeft(2, '0')}',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                          : 'Gunakan lokasi perangkat',
                    ),
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
                const Padding(
                  padding: EdgeInsets.only(top: 7),
                  child: Text(
                    'Koordinat tidak diisi otomatis. Gunakan lokasi perangkat atau masukkan titik kejadian secara manual.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF85661B)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: damage,
                  decoration: const InputDecoration(
                    labelText: 'Dampak yang terlihat',
                    border: OutlineInputBorder(),
                  ),
                  items: ['Rendah', 'Sedang', 'Tinggi']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => setState(() => damage = v!),
                ),
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
                  onPressed: pickEvidence,
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
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: sending ? null : submit,
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(sending ? 'Mengirim…' : 'Kirim laporan'),
                  ),
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
        const Center(child: CircularProgressIndicator())
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
      border: const OutlineInputBorder(),
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
    padding: const EdgeInsets.all(20),
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
        onTap: () =>
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const DonationPage())),
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

class DonationPage extends StatelessWidget {
  const DonationPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Donasi')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFE7F6ED),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.volunteer_activism_outlined,
                size: 36,
                color: Color(0xFF075B49),
              ),
              SizedBox(height: 14),
              Text(
                'Dukungan untuk kesiapsiagaan',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'Halaman ini hanya menampilkan informasi yang telah diverifikasi. Saat ini belum ada program atau organisasi donasi resmi yang dikonfigurasi di aplikasi.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Card(
          child: ListTile(
            leading: Icon(Icons.verified_outlined),
            title: Text('Verifikasi kanal terlebih dahulu'),
            subtitle: Text(
              'Gunakan kanal resmi lembaga terkait yang Anda verifikasi secara mandiri. SiagaNow belum menyediakan tautan donasi resmi.',
            ),
            isThreeLine: true,
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.payments_outlined),
            title: Text('Pembayaran dalam aplikasi tidak tersedia'),
            subtitle: Text(
              'Tidak ada pembayaran, konfirmasi donasi, target, atau total dana yang disimpan oleh aplikasi ini.',
            ),
            isThreeLine: true,
          ),
        ),
      ],
    ),
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
              decoration: const InputDecoration(labelText: 'Hubungan (opsional)'),
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
                if (input.isNotEmpty && !RegExp(r'^[+0-9() .-]{5,32}$').hasMatch(input)) {
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
              decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
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
          ? membershipData.whereType<Map>().map(Map<String, dynamic>.from).toList()
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
          const SnackBar(content: Text('Konfirmasi tersimpan di server. Ini mencatat jawaban saat ini, bukan jaminan kondisi setelahnya.')),
        );
      }
      if (mounted) await load(retryPending: false);
    } catch (e) {
      if (mounted && refresh) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tidak tersambung; konfirmasi disimpan sementara di perangkat dan akan dicoba lagi. $e')),
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
    final initialHours = int.tryParse('${member['reminder_frequency_hours']}') ?? 24;
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
                  subtitle: const Text('Hanya pada perangkat ini; tidak dikirim sebagai push.'),
                  value: enabled,
                  onChanged: (value) => setDialogState(() => enabled = value),
                ),
                DropdownButtonFormField<int>(
                  value: hours,
                  decoration: const InputDecoration(labelText: 'Frekuensi'),
                  items: const [
                    DropdownMenuItem(value: 24, child: Text('Setiap hari')),
                    DropdownMenuItem(value: 168, child: Text('Setiap 7 hari')),
                  ],
                  onChanged: (value) => setDialogState(() => hours = value ?? 24),
                ),
                const SizedBox(height: 8),
                Text('Zona waktu perangkat: ${FamilyReminderService.timezoneName}'),
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
          const SnackBar(content: Text('Izin notifikasi ditolak. Pengingat tidak diaktifkan.')),
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
          throw const ApiException('Pengaturan tersimpan tetapi jadwal lokal gagal dibuat; pengingat dinonaktifkan kembali.');
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
    final overdue = member['overdue'] == true ||
        (member['reminder_enabled'] == true &&
            nextAt != null &&
            nextAt.isBefore(DateTime.now().toUtc()));
    final checkInAt = DateTime.tryParse('${member['check_in_at'] ?? ''}');
    if (overdue) return 'Menunggu konfirmasi · terlambat jadwal, bukan keadaan darurat';
    if (checkInAt == null) return 'Belum ada konfirmasi';
    return 'Sudah konfirmasi aman · ${checkInAt.toLocal()} (jawaban saat itu, bukan status saat ini)';
  }

  String reminderSummary(Map<String, dynamic> member) {
    if (member['reminder_enabled'] != true) return 'Pengingat nonaktif';
    final nextAt = DateTime.tryParse('${member['next_reminder_at'] ?? ''}');
    final frequency = int.tryParse('${member['reminder_frequency_hours']}') ?? 24;
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
      title: const Text('Keluarga Siaga'),
      actions: [
        if (authenticated)
          IconButton(
            onPressed: saving ? null : load,
            icon: const Icon(Icons.refresh),
          ),
      ],
    ),
    body: !authenticated
        ? _FeatureLoginPrompt(
            onLogin: signIn,
            text: 'Masuk untuk membuat dan mengelola keluarga Anda.',
          )
        : loading
        ? const Center(child: CircularProgressIndicator())
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
                        icon: const Icon(Icons.more_vert, color: Colors.white),
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
                        if (phone?.isNotEmpty == true) 'Kontak darurat: $phone',
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
                              const PopupMenuItem(value: 'edit', child: Text('Ubah')),
                              if (member['user_id'] == null)
                                const PopupMenuItem(value: 'invite', child: Text('Undang akun')),
                              const PopupMenuItem(value: 'reminder', child: Text('Pengingat')),
                              const PopupMenuItem(value: 'remove', child: Text('Hapus')),
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
                          for (final raw in (membership['members'] is List
                                  ? membership['members'] as List
                                  : const <Object>[])
                              .whereType<Map>())
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Text(
                                '${raw['name']}: ${checkInSummary(Map<String, dynamic>.from(raw))}',
                              ),
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton.icon(
                                onPressed: saving ||
                                        pendingCheckIns.contains(
                                          int.tryParse('${membership['id']}'),
                                        )
                                    ? null
                                    : () => checkIn(
                                        int.parse('${membership['id']}'),
                                      ),
                                icon: pendingCheckIns.contains(
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
      title: const Text('Penilaian Risiko'),
      actions: [
        if (authenticated)
          IconButton(
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
          ),
      ],
    ),
    body: !authenticated
        ? _FeatureLoginPrompt(
            onLogin: signIn,
            text: 'Masuk untuk menyimpan dan melihat pemeriksaan risiko Anda.',
          )
        : loading
        ? const Center(child: CircularProgressIndicator())
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
                                validator: (v) => _coordinateValue(v, -90, 90),
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
                              submitting ? 'Menyimpan…' : 'Simpan pemeriksaan',
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
                  message: 'Pemeriksaan yang Anda simpan akan muncul di sini.',
                ),
              ...assessments.whereType<Map>().map((raw) {
                final item = Map<String, dynamic>.from(raw);
                final limits = item['limitations'] is List
                    ? (item['limitations'] as List).map((e) => '$e').join('\n')
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
      color: const Color(0xFFEAF6EF),
      borderRadius: BorderRadius.circular(16),
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
      color: const Color(0xFFFFEEEE),
      borderRadius: BorderRadius.circular(12),
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
      color: const Color(0xFFFFF3D7),
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

class EmergencyContactsPage extends StatelessWidget {
  const EmergencyContactsPage({super.key});
  Future<void> _call(BuildContext context) async {
    final opened = await launchUrl(Uri(scheme: 'tel', path: '112'));
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dialer tidak tersedia pada perangkat ini.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kontak darurat')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text(
          'Layanan darurat',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Kontak yang dapat ditampilkan aplikasi saat ini terbatas pada layanan yang sudah dicantumkan untuk Kota Padang.',
        ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.emergency_outlined)),
            title: const Text('PCC 112 · Kota Padang'),
            subtitle: const Text(
              'Layanan panggilan darurat gratis untuk Kota Padang. Sumber: sigap.padang.go.id. Untuk wilayah lain, hubungi BPBD kabupaten/kota setempat.',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: 'Buka dialer',
              onPressed: () => _call(context),
              icon: const Icon(Icons.call_outlined),
            ),
            onTap: () => _call(context),
          ),
        ),
        const SizedBox(height: 14),
        const _EmptyState(
          text: 'Kontak pribadi/keluarga belum tersimpan. Pengelolaan kontak keluarga belum tersedia pada aplikasi ini.',
        ),
      ],
    ),
  );
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.api,
    required this.onLogin,
    required this.onLogout,
  });
  final ApiService api;
  final VoidCallback onLogin;
  final Future<void> Function() onLogout;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  UserProfile? profile;
  bool loading = true;
  String? error;
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
    appBar: AppBar(
      title: const Text('Profil'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? _EmptyState(text: error!)
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 18,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF087354), Color(0xFF55A982)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 30,
                      backgroundColor: Color(0xFFD0F1DF),
                      child: Icon(
                        Icons.person,
                        size: 34,
                        color: Color(0xFF075B49),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile?.name ?? '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            profile?.email ?? 'Email tidak tersedia',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Edit profil',
                      onPressed: () => _showUnavailable(
                        context,
                        'Edit profil',
                        'Perubahan profil belum tersedia melalui API mobile.',
                      ),
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    if (profile?.phone?.isNotEmpty == true)
                      ListTile(
                        leading: const Icon(Icons.phone_outlined),
                        title: Text(profile!.phone!),
                      ),
                    if (profile?.address?.isNotEmpty == true)
                      ListTile(
                        leading: const Icon(Icons.location_on_outlined),
                        title: Text(profile!.address!),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReportHistoryPage(
                      api: widget.api,
                      onLogin: widget.onLogin,
                    ),
                  ),
                ),
                icon: const Icon(Icons.assignment_outlined),
                label: const Text('Laporan saya'),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.volunteer_activism_outlined),
                      title: const Text('Informasi donasi'),
                      subtitle: const Text('Tidak ada transaksi tersimpan.'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DonationPage()),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.emergency_outlined),
                      title: const Text('Kontak darurat'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EmergencyContactsPage(),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.notifications_outlined),
                      title: const Text('Notifikasi'),
                      subtitle: const Text(
                        'Pengaturan notifikasi belum tersedia.',
                      ),
                      onTap: () => _showUnavailable(
                        context,
                        'Notifikasi',
                        'Aplikasi belum terhubung dengan layanan notifikasi.',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip_outlined),
                      title: const Text('Privasi dan keamanan'),
                      onTap: () => _showUnavailable(
                        context,
                        'Privasi dan keamanan',
                        'Data akun dan laporan dikirim ke API SiagaNow. Data keluarga hanya dapat diakses pemilik grup.',
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Tentang SiagaNow'),
                      onTap: () => _showUnavailable(
                        context,
                        'Tentang SiagaNow',
                        'SiagaNow menghubungkan informasi kesiapsiagaan dengan layanan API yang tersedia. Informasi simulasi bukan peringatan resmi.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await widget.onLogout();
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.logout),
                label: const Text('Keluar'),
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
  bool loading = true;
  String? error;
  List<dynamic> articles = [];
  String? type;
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
    } catch (e) {
      error = '$e';
      articles = [];
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Berita kebencanaan',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
        ),
        if (type == 'simulation')
          const Padding(padding: EdgeInsets.only(top: 12), child: DemoBadge()),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (articles.isEmpty)
          _EmptyState(
            text: error ?? 'Belum tersedia berita kejadian terverifikasi.',
          )
        else
          ...articles.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final article = Map<String, dynamic>.from(item as Map);
            final image = article['image_url'] ?? article['image'];
            final remoteImage = image is String && image.startsWith('http');
            return Card(
              child: ListTile(
                leading: SizedBox(
                  width: 60,
                  height: 60,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: remoteImage
                        ? Image.network(
                            image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.article_outlined),
                          )
                        : type == 'simulation'
                        ? Image.asset(
                            index.isEven
                                ? 'assets/images/news_flooded_home.jpg'
                                : 'assets/images/news_flood_damage.jpg',
                            fit: BoxFit.cover,
                          )
                        : const Icon(Icons.article_outlined),
                  ),
                ),
                title: Text('${article['title'] ?? 'Informasi'}'),
                subtitle: Text(
                  '${article['summary'] ?? article['description'] ?? ''}\n${article['source'] ?? 'Sumber tidak dicantumkan'} · ${article['published_at'] ?? 'tanggal tidak tersedia'}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NewsDetailPage(
                      article: article,
                      simulation: type == 'simulation',
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    ),
  );
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
    return Scaffold(
      appBar: AppBar(title: const Text('Detail berita')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (imageUrl != null)
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
          if (imageUrl == null && simulation)
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
    );
  }
}

class ReportDetailPage extends StatelessWidget {
  const ReportDetailPage({super.key, required this.report});
  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final injured = report['injured'];
    final deceased = report['deceased'];
    return Scaffold(
      appBar: AppBar(title: const Text('Detail laporan')),
      body: ListView(
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
                  subtitle: Text('${report['event_type'] ?? 'Belum tersedia'}'),
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
        ],
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
      title: const Text('Laporan saya'),
      actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? _EmptyState(text: error!)
        : reports.isEmpty
        ? const _EmptyState(text: 'Belum ada laporan tersimpan pada akun ini.')
        : ListView(
            children: reports
                .map(
                  (r) => Card(
                    child: ListTile(
                      title: Text('${r['title'] ?? 'Laporan'}'),
                      subtitle: Text(
                        'Status ${r['status'] ?? '—'} · ${r['created_at'] ?? ''}',
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
              registering ? 'Buat akun SiagaNow' : 'Selamat datang',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              registering
                  ? 'Daftar dengan data yang dibutuhkan akun Anda.'
                  : 'Masuk dengan akun SiagaNow Anda.',
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
                decoration: const InputDecoration(
                  labelText: 'Email atau nomor HP',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Wajib diisi.' : null,
              ),
            if (!registering) const SizedBox(height: 12),
            TextFormField(
              controller: password,
              obscureText: !passwordVisible,
              decoration: InputDecoration(
                labelText: 'Kata sandi',
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
