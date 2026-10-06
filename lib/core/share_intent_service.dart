import 'package:flutter/services.dart';

class ShareIntentService {
  static const MethodChannel _channel =
      MethodChannel('ir.befrest/share_intent');

  void Function(List<String> paths)? _onShared;

  Future<void> start(
    void Function(List<String> paths) onShared,
  ) async {
    _onShared = onShared;

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'sharedFiles') return;
      final raw = call.arguments;
      if (raw is! List) return;

      final paths = raw
          .map((item) => item?.toString() ?? '')
          .where((path) => path.trim().isNotEmpty)
          .toList(growable: false);

      if (paths.isNotEmpty) {
        _onShared?.call(paths);
      }
    });

    final initial =
        await _channel.invokeMethod<List<dynamic>>('getInitialSharedFiles');
    final paths = (initial ?? const <dynamic>[])
        .map((item) => item?.toString() ?? '')
        .where((path) => path.trim().isNotEmpty)
        .toList(growable: false);

    if (paths.isNotEmpty) {
      onShared(paths);
    }
  }

  Future<void> dispose() async {
    _onShared = null;
    _channel.setMethodCallHandler(null);
  }
}
