import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:siaga_now_mobile/main.dart';

ApiService _api() => ApiService(
  const FlutterSecureStorage(),
  client: MockClient((request) async {
    final payload = switch (request.url.path) {
      '/api/user' => {
        'data': {
          'id': 42,
          'name': 'Ayu API',
          'email': 'ayu@example.test',
          'phone': '+628123456789',
          'address': 'Kuranji, Padang',
        },
      },
      '/api/family-groups' => {'data': <Object>[]},
      '/api/family-memberships' => {'data': <Object>[]},
      '/api/risk-assessments' => {'data': <Object>[]},
      _ => {'message': 'Unexpected test request'},
    };
    final status = payload.containsKey('message') ? 404 : 200;
    return http.Response(jsonEncode(payload), status);
  }),
  tokenReader: () async => 'widget-test-token',
);

class _CompletedOnboardingStore implements OnboardingProgressStore {
  @override
  Future<bool> isComplete() async => true;

  @override
  Future<void> markComplete() async {}
}

ApiService _navigationApi() => ApiService(
  const FlutterSecureStorage(),
  client: MockClient((request) async {
    final payload = switch (request.url.path) {
      '/api/home' => {
        'data_type': 'unavailable',
        'weather': <String, dynamic>{},
        'weather_forecast': {'forecasts': <Object>[]},
        'statistics': <String, dynamic>{},
        'warning': {'status': 'unknown', 'active': false},
      },
      '/api/news' => {'data': <Object>[], 'data_type': 'unavailable'},
      '/api/shelters' => {'data': <Object>[], 'data_type': 'database'},
      _ => {'message': 'Unexpected test request'},
    };
    return http.Response(
      jsonEncode(payload),
      payload.containsKey('message') ? 404 : 200,
    );
  }),
  tokenReader: () async => null,
);

ApiService _newsPaginationApi() => ApiService(
  const FlutterSecureStorage(),
  client: MockClient((request) async {
    final articles = List.generate(
      12,
      (index) => {
        'id': index + 1,
        'title': 'Berita ${index + 1}',
        'summary': 'Ringkasan berita untuk uji pagination.',
        'published_at': '2026-11-16T09:00:00+07:00',
        'location': 'Padang',
        'source': 'Sumber uji',
      },
    );
    return http.Response(
      jsonEncode({'data': articles, 'data_type': 'database'}),
      200,
    );
  }),
  tokenReader: () async => null,
);

ApiService _familyApi({int createStatus = 201}) {
  Map<String, dynamic>? family;
  return ApiService(
    const FlutterSecureStorage(),
    client: MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path == '/api/family-memberships') {
        return http.Response(jsonEncode({'data': <Object>[]}), 200);
      }
      if (request.method == 'GET' && request.url.path == '/api/family-groups') {
        return http.Response(
          jsonEncode({
            'data': family == null ? <Object>[] : [family],
          }),
          200,
        );
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/family-groups') {
        if (createStatus == 422) {
          return http.Response(
            jsonEncode({
              'message': 'The name field is required.',
              'errors': {
                'name': ['Nama keluarga wajib diisi.'],
              },
            }),
            createStatus,
          );
        }
        if (createStatus >= 500) {
          return http.Response(
            jsonEncode({'message': 'Server error'}),
            createStatus,
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        family = {'id': 42, 'name': body['name'], 'members': <Object>[]};
        return http.Response(jsonEncode({'data': family}), 201);
      }
      return http.Response(
        jsonEncode({'message': 'Unexpected test request'}),
        404,
      );
    }),
    tokenReader: () async => 'widget-test-token',
  );
}

ApiService _reportSubmissionApi({required bool includeReportId}) => ApiService(
  const FlutterSecureStorage(),
  client: MockClient((request) async {
    if (request.method == 'GET' && request.url.path == '/api/reports') {
      return http.Response(jsonEncode({'data': <Object>[]}), 200);
    }
    if (request.method == 'POST' && request.url.path == '/api/reports') {
      return http.Response(
        jsonEncode({
          'data': {if (includeReportId) 'id': 73, 'status': 'submitted'},
        }),
        201,
      );
    }
    return http.Response(jsonEncode({'message': 'Unexpected request'}), 404);
  }),
  tokenReader: () async => 'widget-test-token',
);

Future<void> _openFamily(WidgetTester tester, ApiService api) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FamilyPage(
                    api: api,
                    loggedIn: true,
                    onLogin: () async {},
                  ),
                ),
              ),
              child: const Text('Open family'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open family'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('news pagination uses only pages backed by API data', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(1.5),
        ),
        child: MaterialApp(
          home: Scaffold(body: NewsPage(api: _newsPaginationApi())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Berita Terbaru'), findsOneWidget);
    expect(find.text('Semua Berita'), findsOneWidget);
    expect(find.text('Berita 1'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('3'),
      420,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(find.text('10'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Berita 6'),
      -420,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Berita 6'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weather forecast tiles match conditions and fit small screens', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final forecasts = [
      WeatherPeriod(
        localDateTime: '2026-11-16T09:00:00+07:00',
        temperature: 28,
        condition: 'Cerah Berawan',
      ),
      WeatherPeriod(
        localDateTime: '2026-11-16T12:00:00+07:00',
        temperature: 29,
        condition: 'Hujan Ringan',
      ),
      WeatherPeriod(
        localDateTime: '2026-11-16T15:00:00+07:00',
        temperature: 26,
        condition: 'Hujan Petir',
      ),
      WeatherPeriod(
        localDateTime: '2026-11-17T09:00:00+07:00',
        temperature: 27,
        condition: 'Cerah',
      ),
    ];

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
            home: WeatherDetailPage(
              weather: {
                'temperature': 28,
                'condition': 'Cerah Berawan',
                'location': 'Kota Padang',
                'humidity': 82,
                'wind_kmh': 8,
                'source': 'BMKG',
              },
              forecasts: forecasts,
              warning: {'status': 'unknown', 'active': false},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Data belum tersedia'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Cari lokasi'));
      await tester.pumpAndSettle();
      expect(find.text('Pencarian lokasi belum tersedia.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'five primary tabs stay readable and track selection on compact screens',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
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
            child: SiagaNowApp(
              onboardingStore: _CompletedOnboardingStore(),
              tokenReader: () async => null,
              apiService: _navigationApi(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Rute Evakuasi',
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Laporkan Bencana',
          ),
          findsOneWidget,
        );
        expect(find.text('Rute'), findsOneWidget);
        expect(find.text('Laporan'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Donasi'));
        await tester.pumpAndSettle();
        expect(find.text('Dukungan untuk kesiapsiagaan'), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Donasi' &&
                widget.properties.selected == true,
          ),
          findsOneWidget,
        );

        await tester.tap(find.text('Darurat'));
        await tester.pumpAndSettle();
        expect(find.text('Kontak Instansi'), findsWidgets);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'Layanan Darurat' &&
                widget.properties.selected == true,
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Family route loads empty state and returns without lifecycle error',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FamilyPage(
                        api: _api(),
                        loggedIn: true,
                        onLogin: () async {},
                      ),
                    ),
                  ),
                  child: const Text('Open family'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open family'));
      await tester.pumpAndSettle();
      expect(find.text('Belum ada grup keluarga'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Open family'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Family creation posts the name and reloads the created group', (
    tester,
  ) async {
    await _openFamily(tester, _familyApi());
    await tester.tap(find.text('Buat grup keluarga'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Keluarga Uji');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(find.text('Keluarga Uji'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open family'));
    await tester.pumpAndSettle();
    expect(find.text('Keluarga Uji'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Family creation validates a blank name before sending', (
    tester,
  ) async {
    await _openFamily(tester, _familyApi());
    await tester.tap(find.text('Buat grup keluarga'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(find.text('Nama keluarga wajib diisi.'), findsOneWidget);
    expect(find.text('Buat keluarga'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Family creation shows Laravel validation errors', (
    tester,
  ) async {
    await _openFamily(tester, _familyApi(createStatus: 422));
    await tester.tap(find.text('Buat grup keluarga'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Nama');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nama keluarga wajib diisi.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Family creation shows API errors without losing the form', (
    tester,
  ) async {
    await _openFamily(tester, _familyApi(createStatus: 500));
    await tester.tap(find.text('Buat grup keluarga'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Keluarga Uji');
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Server error'), findsOneWidget);
    expect(find.text('Coba lagi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Risk form fits compact and standard phone widths', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final viewport in [const Size(320, 640), const Size(375, 812)]) {
      tester.view.physicalSize = viewport;
      await tester.pumpWidget(
        MaterialApp(
          home: RiskAssessmentPage(
            api: _api(),
            loggedIn: true,
            onLogin: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Simpan pemeriksaan'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final rainfallDropdown = find.byWidgetPredicate(
        (widget) => widget is DropdownButtonFormField<String>,
      );
      expect(rainfallDropdown, findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
    'report form shows complete validation errors without sending while signed out',
    (tester) async {
      var loginRequested = false;
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: ReportPage(
            api: _api(),
            loggedIn: false,
            onLogin: () async => loginRequested = true,
          ),
        ),
      );

      await tester.tap(find.text('Kirim'));
      await tester.pumpAndSettle();

      expect(find.text('Masukkan judul minimal 4 karakter.'), findsOneWidget);
      expect(
        find.text('Masukkan titik antara -90.0 dan 90.0.'),
        findsOneWidget,
      );
      expect(
        find.text('Masukkan titik antara -180.0 dan 180.0.'),
        findsOneWidget,
      );
      expect(find.text('Deskripsi minimal 10 karakter.'), findsOneWidget);
      expect(loginRequested, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'report form has no preset impact and requires an explicit choice',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var loginRequested = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ReportPage(
            api: _api(),
            loggedIn: false,
            onLogin: () async => loginRequested = true,
          ),
        ),
      );
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .every((chip) => !chip.selected),
        isTrue,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nama kejadian/bencana'),
        'Banjir besar',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Latitude'),
        '-0.9',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Longitude'),
        '100.3',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ceritakan kondisi yang terlihat'),
        'Air mulai masuk ke rumah warga.',
      );
      await tester.tap(find.text('Kirim'));
      await tester.pumpAndSettle();
      expect(find.text('Pilih tingkat bencana.'), findsOneWidget);
      expect(loginRequested, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('report and login sheets fit compact screens with large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(320, 640), const Size(360, 740)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: ReportPage(api: _api(), loggedIn: false, onLogin: () async {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReportPage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(body: AuthSheet(api: _api())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lupa Kata Sandi? — Belum tersedia'), findsOneWidget);
      final forgotButton = tester.widget<TextButton>(
        find
            .ancestor(
              of: find.text('Lupa Kata Sandi? — Belum tersedia'),
              matching: find.byType(TextButton),
            )
            .first,
      );
      expect(forgotButton.onPressed, isNull);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'profile keeps API values visible on compact and standard phones',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      for (final viewport in [const Size(320, 640), const Size(402, 874)]) {
        tester.view.physicalSize = viewport;
        await tester.pumpWidget(
          MaterialApp(
            home: ProfilePage(
              api: _api(),
              onLogin: () {},
              onLogout: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Ayu API'), findsOneWidget);
        expect(find.text('ayu@example.test'), findsOneWidget);
        expect(find.text('+628123456789'), findsOneWidget);
        expect(find.text('Kuranji, Padang'), findsOneWidget);
        expect(find.text('Laporan Bencana Saya'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('profile uses the home header above normally scrolling content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(api: _api(), onLogin: () {}, onLogout: () async {}),
      ),
    );
    await tester.pumpAndSettle();

    const appBarKey = ValueKey('profile.standard-appbar');
    const bodyKey = ValueKey('profile.scroll-background');
    const waveKey = ValueKey('siaganow.header.wave');
    const overlayKey = ValueKey('siaganow.header.green-overlay');
    const content = ValueKey('profile.scroll-content');
    final appBarFinder = find.byKey(appBarKey);
    final bodyFinder = find.byKey(bodyKey);
    final waveFinder = find.byKey(waveKey);
    final overlayFinder = find.byKey(overlayKey);
    final contentFinder = find.byKey(content);
    final appBarPosition = tester.getRect(appBarFinder);
    final bodyPosition = tester.getRect(bodyFinder);
    final wavePosition = tester.getRect(waveFinder);
    final overlayPosition = tester.getRect(overlayFinder);
    final appBar = tester.widget<AppBar>(appBarFinder);
    final menuFinder = find.text('Informasi Donasi');
    final menuPosition = tester.getTopLeft(menuFinder);
    final overlayOpacity = tester.widget<Opacity>(
      find.descendant(of: overlayFinder, matching: find.byType(Opacity)),
    );
    final scrollableFinder = find.descendant(
      of: contentFinder,
      matching: find.byType(Scrollable),
    );
    final scrollable = tester.state<ScrollableState>(scrollableFinder.first);

    expect(appBar.toolbarHeight, 92);
    expect(scrollable.position.pixels, 0);
    expect(
      find.byKey(const ValueKey('profile.fixed-background')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('profile.fixed-header')), findsNothing);
    expect(wavePosition, overlayPosition);
    expect(overlayOpacity.opacity, .5);
    expect(
      tester.getTopLeft(contentFinder).dy,
      greaterThanOrEqualTo(appBarPosition.bottom),
    );
    await tester.drag(contentFinder, const Offset(0, -720));
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.getRect(appBarFinder), appBarPosition);
    expect(tester.getRect(bodyFinder), bodyPosition);
    expect(tester.getRect(waveFinder), wavePosition);
    expect(tester.getRect(overlayFinder), overlayPosition);
    expect(tester.getTopLeft(menuFinder), isNot(menuPosition));
    expect(find.text('Tentang SiagaNow'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header wave tint stays aligned behind scrolling content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 180,
                child: SiagaNowHeaderBackground(),
              ),
              Positioned.fill(
                child: ListView(
                  key: const ValueKey('header-scroll-content'),
                  children: [
                    for (var index = 0; index < 12; index++)
                      Container(
                        key: ValueKey('header-scroll-card-$index'),
                        height: 120,
                        margin: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                        color: Colors.white,
                        child: Center(child: Text('Kartu $index')),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final wave = find.byKey(const ValueKey('siaganow.header.wave'));
    final overlay = find.byKey(const ValueKey('siaganow.header.green-overlay'));
    final firstCard = find.byKey(const ValueKey('header-scroll-card-2'));
    final wavePosition = tester.getRect(wave);
    final overlayPosition = tester.getRect(overlay);
    final cardPosition = tester.getTopLeft(firstCard);
    final overlayOpacity = tester.widget<Opacity>(
      find.descendant(of: overlay, matching: find.byType(Opacity)),
    );

    expect(wavePosition, overlayPosition);
    expect(overlayOpacity.opacity, .5);
    await tester.drag(
      find.byKey(const ValueKey('header-scroll-content')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    expect(tester.getRect(wave), wavePosition);
    expect(tester.getRect(overlay), overlayPosition);
    expect(tester.getTopLeft(firstCard), isNot(cardPosition));
    expect(tester.takeException(), isNull);
  });

  testWidgets('report success requires a server report identifier', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final includeReportId in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(includeReportId),
          home: Scaffold(
            body: ReportPage(
              api: _reportSubmissionApi(includeReportId: includeReportId),
              loggedIn: true,
              onLogin: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView).first, const Offset(0, -420));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Laporan banjir uji');
      await tester.enterText(fields.at(1), '-0.95');
      await tester.enterText(fields.at(2), '100.4');
      await tester.enterText(fields.at(5), 'Air menggenangi jalan utama.');
      final lowestImpact = find.byKey(const ValueKey('report-impact-Rendah'));
      await tester.ensureVisible(lowestImpact);
      await tester.tap(lowestImpact);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .any((chip) => chip.selected),
        isTrue,
      );
      await tester.ensureVisible(find.text('Kirim'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kirim'));
      await tester.pump();
      if (includeReportId) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump(const Duration(milliseconds: 400));
      }

      if (includeReportId) {
        expect(find.text('Laporan Tersimpan'), findsOneWidget);
        expect(find.text('Lokasi kejadian'), findsOneWidget);
        expect(find.text('Laporan banjir uji'), findsOneWidget);
      } else {
        expect(find.text('Laporan Tersimpan'), findsNothing);
        expect(
          tester.widget<TextFormField>(fields.at(0)).controller!.text,
          'Laporan banjir uji',
        );
        expect(
          find.text(
            'Server belum mengonfirmasi bahwa laporan berhasil disimpan.',
          ),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('report success fits a compact phone and labels local fixtures', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ReportSuccessPage(
          onReturnHome: () {},
          shelter: ReportShelterInfo(
            name: 'Contoh Shelter Kuranji',
            location: 'Area Kuranji · titik koordinat latihan',
            simulation: true,
            distanceKm: 1.2,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Laporan Tersimpan'), findsOneWidget);
    expect(find.text('SHELTER SIMULASI'), findsOneWidget);
    expect(find.textContaining('1.2 km'), findsOneWidget);
    expect(find.text('Kembali Ke Beranda'), findsOneWidget);
    expect(
      tester.getRect(find.text('Kembali Ke Beranda')).bottom,
      lessThan(740),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('report status keeps its header fixed while content scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: ReportSuccessPage(
          onReturnHome: () {},
          shelter: ReportShelterInfo(
            name: 'Titik simulasi uji',
            location: List.filled(18, 'Informasi lokasi contoh').join(' '),
            simulation: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const header = ValueKey('report-status.fixed-header');
    final headerPosition = tester.getRect(find.byKey(header));
    final contentPosition = tester.getTopLeft(find.text('Laporan Tersimpan'));
    final scrollableFinder = find.descendant(
      of: find.byType(SingleChildScrollView),
      matching: find.byType(Scrollable),
    );
    final scrollable = tester.state<ScrollableState>(scrollableFinder.first);

    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byKey(header)), headerPosition);
    expect(
      tester.getTopLeft(find.text('Laporan Tersimpan')),
      isNot(contentPosition),
    );
    expect(tester.takeException(), isNull);
  });
}
