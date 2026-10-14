import 'package:immich_mobile/domain/models/store.model.dart';

enum Setting<T> {
  advancedTroubleshooting<bool>(StoreKey.advancedTroubleshooting, false),
  compressAndUploadQuality<int>(StoreKey.compressAndUploadQuality, 80),
  showCompressAndUploadButton<bool>(StoreKey.showCompressAndUploadButton, true),
  compressByDefault<bool>(StoreKey.compressByDefault, false),
  compressBackgroundBackup<int>(StoreKey.compressBackgroundBackup, 0);

  const Setting(this.storeKey, this.defaultValue);

  final StoreKey<T> storeKey;
  final T defaultValue;
}
