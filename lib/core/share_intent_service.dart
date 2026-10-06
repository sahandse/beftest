import 'dart:async';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareIntentService {
  StreamSubscription<List<SharedMediaFile>>? _subscription;

  Future<void> start(
    void Function(List<String> paths) onShared,
  ) async {
    _subscription?.cancel();

    _subscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen((files) {
      final paths = files
          .map((file) => file.path)
          .where((path) => path.trim().isNotEmpty)
          .toList(growable: false);
      if (paths.isNotEmpty) onShared(paths);
    });

    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    final paths = initial
        .map((file) => file.path)
        .where((path) => path.trim().isNotEmpty)
        .toList(growable: false);

    if (paths.isNotEmpty) {
      onShared(paths);
      await ReceiveSharingIntent.instance.reset();
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
  }
}
