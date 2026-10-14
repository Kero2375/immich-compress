import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/actions/action.widget.dart';
import 'package:immich_mobile/presentation/actions/upload.action.dart';
import 'package:immich_mobile/providers/backup/asset_upload_progress.provider.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:immich_ui/immich_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../../../service.mocks.dart';
import '../../factories/local_asset_factory.dart';
import '../../factories/remote_asset_factory.dart';
import '../presentation_context.dart';

void main() {
  late PresentationContext context;
  late MockForegroundUploadService uploadService;

  setUp(() async {
    context = await PresentationContext.create();
    uploadService = context.service.upload;
  });

  tearDown(() async {
    await context.dispose();
  });

  List<Override> uploadOverrides() => [
    foregroundUploadServiceProvider.overrideWithValue(uploadService),
    toastServiceProvider.overrideWithValue(context.service.toast),
  ];

  Future<void> pumpUpload(
    WidgetTester tester,
    Set<BaseAsset> selection, {
    bool showProgress = false,
    UploadCompressionMode? mode,
  }) =>
      tester.pumpTestWidget(
        context,
        ActionIconButton(
          action: UploadAction(source: .timeline, showProgress: showProgress, mode: mode),
        ),
        overrides: [...context.selected(selection), ...uploadOverrides()],
      );

  Future<void> settleUpload(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const .new(seconds: 2));
    await tester.pumpAndSettle();
  }

  void answerUploadWith({Set<String> succeeded = const {}, Set<String> failed = const {}, Completer<void>? until}) {
    when(
      () => uploadService.uploadManual(
        any(),
        cancelToken: any(named: 'cancelToken'),
        callbacks: any(named: 'callbacks'),
        compressionMode: any(named: 'compressionMode'),
      ),
    ).thenAnswer((invocation) async {
      if (until != null) {
        await until.future;
      }
      final callbacks = invocation.namedArguments[#callbacks] as UploadCallbacks;
      for (final id in succeeded) {
        callbacks.onSuccess?.call(id, id);
      }
      for (final id in failed) {
        callbacks.onError?.call(id, 'boom');
      }
    });
  }

  group('UploadAction', () {
    testWidgets('uploads the selected local assets', (tester) async {
      final asset = LocalAssetFactory.create();
      answerUploadWith(succeeded: {asset.id});

      await pumpUpload(tester, {asset});
      await tester.tap(find.byType(ImmichIconButton));
      await settleUpload(tester);

      final uploaded =
          verify(
                () => uploadService.uploadManual(
                  captureAny(),
                  cancelToken: any(named: 'cancelToken'),
                  callbacks: any(named: 'callbacks'),
                  compressionMode: any(named: 'compressionMode'),
                ),
              ).captured.single
              as List<LocalAsset>;
      expect(uploaded.map((a) => a.id), [asset.id]);
    });

    testWidgets('ignores assets that are already backed up', (tester) async {
      final notBackedUp = LocalAssetFactory.create();
      answerUploadWith(succeeded: {notBackedUp.id});

      await pumpUpload(tester, {notBackedUp, LocalAssetFactory.create(remoteId: 'already-there')});
      await tester.tap(find.byType(ImmichIconButton));
      await settleUpload(tester);

      final uploaded =
          verify(
                () => uploadService.uploadManual(
                  captureAny(),
                  cancelToken: any(named: 'cancelToken'),
                  callbacks: any(named: 'callbacks'),
                  compressionMode: any(named: 'compressionMode'),
                ),
              ).captured.single
              as List<LocalAsset>;
      expect(uploaded.map((a) => a.id), [notBackedUp.id]);
    });

    testWidgets('reports an error when an asset fails to upload', (tester) async {
      final asset = LocalAssetFactory.create();
      answerUploadWith(failed: {asset.id});

      await pumpUpload(tester, {asset});
      await tester.tap(find.byType(ImmichIconButton));
      await settleUpload(tester);

      final message = verify(() => context.service.toast.error(captureAny())).captured.single as String;
      expect(message, StaticTranslations.instance.scaffold_body_error_occurred);
    });

    testWidgets('treats a cancelled upload as deliberate, not a failure', (tester) async {
      final asset = LocalAssetFactory.create();
      when(
        () => uploadService.uploadManual(
          any(),
          cancelToken: any(named: 'cancelToken'),
          callbacks: any(named: 'callbacks'),
          compressionMode: any(named: 'compressionMode'),
        ),
      ).thenAnswer((invocation) async {
        (invocation.namedArguments[#cancelToken] as Completer<void>).complete();
      });

      await pumpUpload(tester, {asset});
      await tester.tap(find.byType(ImmichIconButton));
      await settleUpload(tester);

      verifyNever(() => context.service.toast.error(any()));
    });

    testWidgets('shows the progress dialog while uploading and closes it after', (tester) async {
      final asset = LocalAssetFactory.create();
      final uploading = Completer<void>();
      answerUploadWith(succeeded: {asset.id}, until: uploading);

      await pumpUpload(tester, {asset}, showProgress: true);
      await tester.tap(find.byType(ImmichIconButton));
      await tester.pump();

      expect(find.text(StaticTranslations.instance.uploading), findsOneWidget);

      uploading.complete();
      await settleUpload(tester);

      expect(find.text(StaticTranslations.instance.uploading), findsNothing);
    });

    testWidgets('shows no dialog when not asked to', (tester) async {
      final asset = LocalAssetFactory.create();
      answerUploadWith(succeeded: {asset.id});

      await pumpUpload(tester, {asset});
      await tester.tap(find.byType(ImmichIconButton));
      await tester.pump();

      expect(find.text(StaticTranslations.instance.uploading), findsNothing);
      await settleUpload(tester);
    });

    testWidgets('is hidden for a remote asset, which has nothing to upload', (tester) async {
      await pumpUpload(tester, {RemoteAssetFactory.create()});

      expect(find.byType(ImmichIconButton), findsNothing);
    });

    testWidgets('is hidden when every local asset is already backed up', (tester) async {
      await pumpUpload(tester, {LocalAssetFactory.create(remoteId: 'already-there')});

      expect(find.byType(ImmichIconButton), findsNothing);
    });

    testWidgets('uploads with compressAndReplace mode by default', (tester) async {
      final asset = LocalAssetFactory.create();
      answerUploadWith(succeeded: {asset.id});

      await pumpUpload(tester, {asset});
      await tester.tap(find.byType(ImmichIconButton));
      await settleUpload(tester);

      verify(
        () => uploadService.uploadManual(
          any(),
          cancelToken: any(named: 'cancelToken'),
          callbacks: any(named: 'callbacks'),
          compressionMode: UploadCompressionMode.compressAndReplace,
        ),
      ).called(1);
    });

    testWidgets('uploads with original mode when specified', (tester) async {
      final asset = LocalAssetFactory.create();
      answerUploadWith(succeeded: {asset.id});

      await pumpUpload(tester, {asset}, mode: UploadCompressionMode.original);
      await tester.tap(find.byType(ImmichIconButton));
      await settleUpload(tester);

      verify(
        () => uploadService.uploadManual(
          any(),
          cancelToken: any(named: 'cancelToken'),
          callbacks: any(named: 'callbacks'),
          compressionMode: UploadCompressionMode.original,
        ),
      ).called(1);
    });

    testWidgets('uploads with compressAndKeep mode when specified', (tester) async {
      final asset = LocalAssetFactory.create();
      answerUploadWith(succeeded: {asset.id});

      await pumpUpload(tester, {asset}, mode: UploadCompressionMode.compressAndKeep);
      await tester.tap(find.byType(ImmichIconButton));
      await settleUpload(tester);

      verify(
        () => uploadService.uploadManual(
          any(),
          cancelToken: any(named: 'cancelToken'),
          callbacks: any(named: 'callbacks'),
          compressionMode: UploadCompressionMode.compressAndKeep,
        ),
      ).called(1);
    });

    testWidgets('shows options modal on long press and uploads with selected option', (tester) async {
      final asset = LocalAssetFactory.create();
      answerUploadWith(succeeded: {asset.id});

      await pumpUpload(tester, {asset});
      await tester.longPress(find.byType(ImmichIconButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(StaticTranslations.instance.upload_options), findsOneWidget);
      expect(find.text(StaticTranslations.instance.upload_and_compress_replace), findsOneWidget);
      expect(find.text(StaticTranslations.instance.upload_original), findsOneWidget);
      expect(find.text(StaticTranslations.instance.upload_compressed_keep_original), findsOneWidget);

      await tester.tap(find.text(StaticTranslations.instance.upload_original));
      await settleUpload(tester);

      verify(
        () => uploadService.uploadManual(
          any(),
          cancelToken: any(named: 'cancelToken'),
          callbacks: any(named: 'callbacks'),
          compressionMode: UploadCompressionMode.original,
        ),
      ).called(1);
    });
  });

  group('uploadAssets', () {
    testWidgets('clears the tracked progress once the upload settles', (tester) async {
      final asset = LocalAssetFactory.create();
      answerUploadWith(succeeded: {asset.id});

      late WidgetRef capturedRef;
      await tester.pumpTestWidget(
        context,
        Consumer(
          builder: (_, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
        overrides: uploadOverrides(),
      );

      await uploadAssets(tester.element(find.byType(SizedBox)), capturedRef, [asset]);
      await settleUpload(tester);

      expect(capturedRef.read(assetUploadProgressProvider), isEmpty);
      expect(capturedRef.read(manualUploadCancelTokenProvider), isNull);
    });
  });
}
