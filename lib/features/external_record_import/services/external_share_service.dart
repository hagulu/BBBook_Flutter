import 'package:flutter/services.dart';

import '../models/external_import_models.dart';

class ExternalShareService {
  const ExternalShareService();

  static const _methodChannel = MethodChannel(
    'com.hagulu.nook.bbbook/external_import',
  );
  static const _eventChannel = EventChannel(
    'com.hagulu.nook.bbbook/external_import/events',
  );

  Stream<ExternalImportFileReference> get files =>
      _eventChannel.receiveBroadcastStream().map(
        (value) => ExternalImportFileReference.fromPlatformMap(
          Map<Object?, Object?>.from(value as Map),
        ),
      );

  Future<ExternalImportFileReference?> initialFile() async {
    final value = await _methodChannel.invokeMethod<Object?>(
      'getInitialSharedFile',
    );
    if (value == null) return null;
    return ExternalImportFileReference.fromPlatformMap(
      Map<Object?, Object?>.from(value as Map),
    );
  }
}
