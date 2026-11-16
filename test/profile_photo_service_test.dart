import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:siaga_now_mobile/services/profile_photo_service.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory storageDirectory;
  late ProfilePhotoService service;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'siaganow-profile-photo-test-',
    );
    storageDirectory = Directory('${temporaryDirectory.path}/saved');
    service = ProfilePhotoService(
      directoryProvider: () async => storageDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('saves photo persistently, replaces it, and deletes it', () async {
    final first = File('${temporaryDirectory.path}/first.png');
    await File('assets/images/siaganow-nature-emblem.png').copy(first.path);

    final saved = await service.savePhoto(first);
    expect((await service.loadSavedPhoto())?.path, saved.path);
    expect(await saved.readAsBytes(), await first.readAsBytes());

    final replacement = File('${temporaryDirectory.path}/replacement.jpg');
    await File('assets/images/news_flood_damage.jpg').copy(replacement.path);
    final replaced = await service.savePhoto(replacement);
    expect(replaced.path, endsWith('profile_photo.jpg'));
    expect((await service.loadSavedPhoto())?.path, replaced.path);
    expect(await saved.exists(), isFalse);

    await service.deletePhoto();
    expect(await service.loadSavedPhoto(), isNull);
  });

  test('rejects unsupported, mismatched, and oversized files', () async {
    final unsupported = File('${temporaryDirectory.path}/photo.webp');
    await unsupported.writeAsBytes(const [0x01]);
    await expectLater(
      service.validatePhoto(unsupported),
      throwsA(isA<ProfilePhotoException>()),
    );

    final mismatched = File('${temporaryDirectory.path}/photo.png');
    await mismatched.writeAsBytes(const [0xFF, 0xD8, 0xFF, 0x01]);
    await expectLater(
      service.validatePhoto(mismatched),
      throwsA(isA<ProfilePhotoException>()),
    );

    final invalidImage = File('${temporaryDirectory.path}/invalid.png');
    await invalidImage.writeAsBytes(const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);
    await expectLater(
      service.validatePhoto(invalidImage),
      throwsA(isA<ProfilePhotoException>()),
    );

    final oversized = File('${temporaryDirectory.path}/large.jpg');
    await oversized.writeAsBytes(
      List<int>.filled(ProfilePhotoService.maxFileSizeBytes + 1, 0),
    );
    await expectLater(
      service.validatePhoto(oversized),
      throwsA(isA<ProfilePhotoException>()),
    );
  });
}
