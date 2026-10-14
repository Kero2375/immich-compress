import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/services/image_compression.service.dart';

void main() {
  group('ImageCompressionService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('image_compress_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('compresses image with default quality 80 and jpeg format', () async {
      String? capturedPath;
      String? capturedTargetPath;
      int? capturedQuality;
      CompressFormat? capturedFormat;
      bool? capturedKeepExif;
      int? capturedMinWidth;
      int? capturedMinHeight;

      final service = ImageCompressionService(
        getTempDir: () async => tempDir,
        compressAndGetFile: (
          path,
          targetPath, {
          int minWidth = 1920,
          int minHeight = 1080,
          int inSampleSize = 1,
          int quality = 95,
          int rotate = 0,
          bool autoCorrectionAngle = true,
          CompressFormat format = CompressFormat.jpeg,
          bool keepExif = false,
          int numberOfRetries = 0,
        }) async {
          capturedPath = path;
          capturedTargetPath = targetPath;
          capturedQuality = quality;
          capturedFormat = format;
          capturedKeepExif = keepExif;
          capturedMinWidth = minWidth;
          capturedMinHeight = minHeight;
          return XFile(targetPath);
        },
      );

      final inputFile = File('${tempDir.path}/test_photo.png');
      await inputFile.writeAsString('test');

      final result = await service.compressImage(file: inputFile);

      expect(result, isNotNull);
      expect(capturedPath, inputFile.absolute.path);
      expect(capturedTargetPath, contains('immich_compressed_'));
      expect(capturedTargetPath, endsWith('_test_photo.jpg'));
      expect(capturedQuality, 80);
      expect(capturedFormat, CompressFormat.jpeg);
      expect(capturedKeepExif, true);
      expect(capturedMinWidth, 1920);
      expect(capturedMinHeight, 1080);
    });

    test('respects custom quality and dimensions', () async {
      int? capturedQuality;
      int? capturedMinWidth;
      int? capturedMinHeight;

      final service = ImageCompressionService(
        getTempDir: () async => tempDir,
        compressAndGetFile: (
          path,
          targetPath, {
          int minWidth = 1920,
          int minHeight = 1080,
          int inSampleSize = 1,
          int quality = 95,
          int rotate = 0,
          bool autoCorrectionAngle = true,
          CompressFormat format = CompressFormat.jpeg,
          bool keepExif = false,
          int numberOfRetries = 0,
        }) async {
          capturedQuality = quality;
          capturedMinWidth = minWidth;
          capturedMinHeight = minHeight;
          return XFile(targetPath);
        },
      );

      final inputFile = File('${tempDir.path}/photo.jpg');
      await inputFile.writeAsString('test');

      final result = await service.compressImage(
        file: inputFile,
        quality: 65,
        minWidth: 4032,
        minHeight: 3024,
      );

      expect(result, isNotNull);
      expect(capturedQuality, 65);
      expect(capturedMinWidth, 4032);
      expect(capturedMinHeight, 3024);
    });

    test('returns null when compression fails', () async {
      final service = ImageCompressionService(
        getTempDir: () async => tempDir,
        compressAndGetFile: (
          path,
          targetPath, {
          int minWidth = 1920,
          int minHeight = 1080,
          int inSampleSize = 1,
          int quality = 95,
          int rotate = 0,
          bool autoCorrectionAngle = true,
          CompressFormat format = CompressFormat.jpeg,
          bool keepExif = false,
          int numberOfRetries = 0,
        }) async {
          return null;
        },
      );

      final inputFile = File('${tempDir.path}/broken.jpg');
      await inputFile.writeAsString('test');

      final result = await service.compressImage(file: inputFile);
      expect(result, isNull);
    });
  });
}
