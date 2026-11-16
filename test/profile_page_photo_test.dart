import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:siaga_now_mobile/main.dart';
import 'package:siaga_now_mobile/services/profile_photo_service.dart';

ApiService _profileApi() => ApiService(
  const FlutterSecureStorage(),
  client: MockClient((request) async {
    if (request.method == 'GET' && request.url.path == '/api/user') {
      return http.Response(
        '{"data":{"id":42,"name":"Ayu API","email":"ayu@example.test"}}',
        200,
      );
    }
    return http.Response('{"message":"Unexpected request"}', 404);
  }),
  tokenReader: () async => 'widget-test-token',
);

void main() {
  late Directory temporaryDirectory;
  late ProfilePhotoService photoService;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'siaganow-profile-page-test-',
    );
    final storageDirectory = Directory('${temporaryDirectory.path}/saved');
    photoService = ProfilePhotoService(
      directoryProvider: () async => storageDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  testWidgets('profile gradient and edit dialog keep text readable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(
          api: _profileApi(),
          onLogin: () {},
          onLogout: () async {},
          photoService: photoService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final background = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('profile.scroll-background')),
    );
    final gradient =
        (background.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(gradient.colors.first, const Color(0xFF24785D));
    expect(gradient.colors.last, const Color(0xFFCDEBDD));

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.backgroundColor?.a, 1.0);
    expect(
      find.text(
        'Nama, email, nomor telepon, dan alamat ditampilkan dari akun server. Anda dapat mengelola foto profil di perangkat ini.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ganti Foto Profil'), findsOneWidget);
    expect(find.text('Hapus Foto Profil'), findsOneWidget);
    expect(find.text('Tutup'), findsOneWidget);

    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
