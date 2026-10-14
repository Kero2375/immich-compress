import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final imageCompressionServiceProvider = Provider<ImageCompressionService>((ref) {
  return const ImageCompressionService();
});

typedef CompressAndGetFileFn =
    Future<XFile?> Function(
      String path,
      String targetPath, {
      int minWidth,
      int minHeight,
      int inSampleSize,
      int quality,
      int rotate,
      bool autoCorrectionAngle,
      CompressFormat format,
      bool keepExif,
      int numberOfRetries,
    });

class ImageCompressionService {
  static final _logger = Logger('ImageCompressionService');
  final CompressAndGetFileFn _compressAndGetFile;
  final Future<Directory> Function() _getTempDir;

  const ImageCompressionService({CompressAndGetFileFn? compressAndGetFile, Future<Directory> Function()? getTempDir})
    : _compressAndGetFile = compressAndGetFile ?? FlutterImageCompress.compressAndGetFile,
      _getTempDir = getTempDir ?? getTemporaryDirectory;

  Future<File?> compressImage({required File file, int quality = 80, int? minWidth, int? minHeight}) async {
    final tempDir = await _getTempDir();
    final uniqueId = DateTime.now().microsecondsSinceEpoch;
    final baseName = p.basenameWithoutExtension(file.path);
    final targetPath = p.join(tempDir.path, 'immich_compressed_${uniqueId}_$baseName.jpg');

    final result = await _compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: quality,
      format: CompressFormat.jpeg,
      keepExif: true,
      minWidth: minWidth ?? 1920,
      minHeight: minHeight ?? 1080,
    );

    if (result == null) {
      return null;
    }

    return File(result.path);
  }

  /// Computes SHA-1 hash of a file returned as base64 (matching Immich checksum format)
  Future<String> computeSha1(File file) async {
    final digest = await sha1.bind(file.openRead()).first;
    return base64Encode(digest.bytes);
  }

  /// Replaces the local image on device external storage with the compressed image.
  /// Preserves the original file modification timestamp.
  Future<File?> replaceLocalImage({required File originalFile, required File compressedFile}) async {
    try {
      if (!originalFile.existsSync()) {
        _logger.warning("Original file does not exist at ${originalFile.path}");
        return null;
      }
      final originalModTime = originalFile.lastModifiedSync();
      final originalExt = p.extension(originalFile.path).toLowerCase();

      if (originalExt == '.jpg' || originalExt == '.jpeg') {
        final replaced = await compressedFile.copy(originalFile.path);
        try {
          await replaced.setLastModified(originalModTime);
        } catch (_) {}
        _logger.info("Successfully replaced local JPEG at ${originalFile.path}");
        return replaced;
      } else {
        final newPath = p.setExtension(originalFile.path, '.jpg');
        final newFile = await compressedFile.copy(newPath);
        try {
          await newFile.setLastModified(originalModTime);
        } catch (_) {}
        try {
          await originalFile.delete();
        } catch (e) {
          _logger.warning("Could not delete original non-JPEG file after replacement: $e");
        }
        _logger.info("Successfully replaced non-JPEG local file with $newPath");
        return newFile;
      }
    } catch (e, st) {
      _logger.severe("Failed to replace local image at ${originalFile.path}: $e", st);
      return null;
    }
  }
}
