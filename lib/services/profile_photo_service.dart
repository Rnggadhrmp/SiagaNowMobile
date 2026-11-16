import 'dart:io';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class ProfilePhotoException implements Exception {
  const ProfilePhotoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Keeps a validated profile photo in app-private storage on this device.
class ProfilePhotoService {
  ProfilePhotoService({
    ImagePicker? picker,
    Future<Directory> Function()? directoryProvider,
  }) : _picker = picker ?? ImagePicker(),
       _directoryProvider = directoryProvider ?? _applicationDirectory;

  static const maxFileSizeBytes = 10 * 1024 * 1024;
  static const _fileBaseName = 'profile_photo';

  final ImagePicker _picker;
  final Future<Directory> Function() _directoryProvider;

  Future<XFile?> pickFromGallery() => _picker.pickImage(
    source: ImageSource.gallery,
    requestFullMetadata: false,
  );

  Future<File?> loadSavedPhoto() async {
    final directory = await _directoryProvider();
    for (final extension in const ['jpg', 'png']) {
      final file = File('${directory.path}/$_fileBaseName.$extension');
      if (await file.exists()) return file;
    }
    return null;
  }

  Future<File> savePhoto(File source) async {
    final extension = await _validate(source);
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    final destination = File('${directory.path}/$_fileBaseName.$extension');
    final temporary = File('${destination.path}.tmp');
    try {
      await source.copy(temporary.path);
      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    for (final otherExtension in const ['jpg', 'png']) {
      if (otherExtension == extension) continue;
      final oldFile = File('${directory.path}/$_fileBaseName.$otherExtension');
      if (await oldFile.exists()) await oldFile.delete();
    }
    return destination;
  }

  Future<void> validatePhoto(File source) async {
    await _validate(source);
  }

  Future<void> deletePhoto() async {
    final directory = await _directoryProvider();
    for (final extension in const ['jpg', 'png']) {
      final file = File('${directory.path}/$_fileBaseName.$extension');
      if (await file.exists()) await file.delete();
    }
  }

  Future<String> _validate(File file) async {
    if (!await file.exists()) {
      throw const ProfilePhotoException('File foto tidak ditemukan.');
    }
    final size = await file.length();
    if (size == 0 || size > maxFileSizeBytes) {
      throw const ProfilePhotoException(
        'Ukuran foto harus lebih dari 0 dan maksimal 10 MB.',
      );
    }
    final extension = file.path.split('.').last.toLowerCase();
    if (extension != 'jpg' && extension != 'jpeg' && extension != 'png') {
      throw const ProfilePhotoException(
        'Format foto harus JPG, JPEG, atau PNG.',
      );
    }
    final header = await file
        .openRead(0, 8)
        .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    final isJpeg =
        header.length >= 3 &&
        header[0] == 0xFF &&
        header[1] == 0xD8 &&
        header[2] == 0xFF;
    const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    final isPng =
        header.length >= pngSignature.length &&
        List<int>.generate(
              pngSignature.length,
              (index) => header[index],
            ).toString() ==
            pngSignature.toString();
    if ((extension == 'png' && !isPng) ||
        ((extension == 'jpg' || extension == 'jpeg') && !isJpeg)) {
      throw const ProfilePhotoException(
        'Isi file tidak sesuai dengan format foto yang dipilih.',
      );
    }
    ui.Codec? codec;
    ui.FrameInfo? frame;
    try {
      codec = await ui.instantiateImageCodec(
        await file.readAsBytes(),
        targetWidth: 512,
        targetHeight: 512,
      );
      frame = await codec.getNextFrame();
      if (frame.image.width == 0 || frame.image.height == 0) {
        throw const ProfilePhotoException('File foto tidak dapat dibuka.');
      }
    } on ProfilePhotoException {
      rethrow;
    } catch (_) {
      throw const ProfilePhotoException('File foto tidak dapat dibuka.');
    } finally {
      frame?.image.dispose();
      codec?.dispose();
    }
    return extension == 'jpeg' ? 'jpg' : extension;
  }

  static Future<Directory> _applicationDirectory() async {
    final root = await getApplicationSupportDirectory();
    return Directory('${root.path}/profile');
  }
}
