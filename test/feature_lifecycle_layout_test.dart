import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:siaga_now_mobile/main.dart';

ApiService _api() => ApiService(
  const FlutterSecureStorage(),
  client: MockClient((request) async {
    final payload = switch (request.url.path) {
      '/api/family-groups' => {'data': <Object>[]},
      '/api/risk-assessments' => {'data': <Object>[]},
      _ => {'message': 'Unexpected test request'},
    };
    final status = payload.containsKey('message') ? 404 : 200;
    return http.Response(jsonEncode(payload), status);
  }),
  tokenReader: () async => 'widget-test-token',
);

ApiService _familyApi({int createStatus = 201}) {
  Map<String, dynamic>? family;
  return ApiService(
    const FlutterSecureStorage(),
    client: MockClient((request) async {
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
}
