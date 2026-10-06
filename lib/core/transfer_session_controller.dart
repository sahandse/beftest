import 'package:flutter/foundation.dart';

import '../network/transfer_models.dart';

class TransferQueueViewItem {
  final String id;
  final String fileName;
  final int size;
  final int sent;
  final TransferStatus status;
  final double bytesPerSecond;
  final Duration? eta;

  const TransferQueueViewItem({
    required this.id,
    required this.fileName,
    required this.size,
    required this.sent,
    required this.status,
    required this.bytesPerSecond,
    required this.eta,
  });

  double get progress => size <= 0 ? 0 : (sent / size).clamp(0, 1);

  TransferQueueViewItem copyWith({
    int? sent,
    TransferStatus? status,
    double? bytesPerSecond,
    Duration? eta,
    bool clearEta = false,
  }) {
    return TransferQueueViewItem(
      id: id,
      fileName: fileName,
      size: size,
      sent: sent ?? this.sent,
      status: status ?? this.status,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      eta: clearEta ? null : (eta ?? this.eta),
    );
  }
}

class TransferSessionController extends ChangeNotifier {
  final TransferRuntimeControl runtimeControl = TransferRuntimeControl();

  final Map<String, TransferQueueViewItem> _items = {};
  final Map<String, int> _lastBytes = {};
  final Map<String, DateTime> _lastTimes = {};

  String _peer = '';
  bool _active = false;
  bool _paused = false;
  bool _cancelled = false;

  String get peer => _peer;
  bool get isActive => _active;
  bool get isPaused => _paused;
  bool get isCancelled => _cancelled;

  List<TransferQueueViewItem> get items =>
      _items.values.toList(growable: false);

  double get overallProgress {
    final total = _items.values.fold<int>(0, (sum, item) => sum + item.size);
    final sent = _items.values.fold<int>(0, (sum, item) => sum + item.sent);
    return total <= 0 ? 0 : (sent / total).clamp(0, 1);
  }

  double get totalSpeed => _items.values.fold<double>(
        0,
        (sum, item) => sum + item.bytesPerSecond,
      );

  Duration? get overallEta {
    final speed = totalSpeed;
    if (speed <= 0) return null;
    final remaining = _items.values.fold<int>(
      0,
      (sum, item) => sum + (item.size - item.sent).clamp(0, item.size),
    );
    return Duration(seconds: (remaining / speed).ceil());
  }

  void start({
    required String peer,
    required List<TransferFile> files,
  }) {
    _peer = peer;
    _active = true;
    _paused = false;
    _cancelled = false;
    _items
      ..clear()
      ..addEntries(
        files.map(
          (file) => MapEntry(
            file.id,
            TransferQueueViewItem(
              id: file.id,
              fileName: file.fileName,
              size: file.size,
              sent: 0,
              status: TransferStatus.waiting,
              bytesPerSecond: 0,
              eta: null,
            ),
          ),
        ),
      );
    _lastBytes.clear();
    _lastTimes.clear();
    notifyListeners();
  }

  void updateProgress(String fileId, int sent, int total) {
    final current = _items[fileId];
    if (current == null) return;

    final now = DateTime.now();
    final previousBytes = _lastBytes[fileId] ?? 0;
    final previousTime = _lastTimes[fileId] ?? now;
    final elapsedMs = now.difference(previousTime).inMilliseconds;

    double speed = current.bytesPerSecond;
    if (elapsedMs >= 250) {
      final delta = sent - previousBytes;
      speed = delta <= 0 ? 0 : delta / (elapsedMs / 1000);
      _lastBytes[fileId] = sent;
      _lastTimes[fileId] = now;
    }

    final remaining = (total - sent).clamp(0, total);
    final eta = speed <= 0
        ? null
        : Duration(seconds: (remaining / speed).ceil());

    _items[fileId] = current.copyWith(
      sent: sent,
      status: TransferStatus.transferring,
      bytesPerSecond: speed,
      eta: eta,
      clearEta: eta == null,
    );
    notifyListeners();
  }

  void updateStatus(String fileId, TransferStatus status) {
    final current = _items[fileId];
    if (current == null) return;

    _items[fileId] = current.copyWith(
      status: status,
      sent: status == TransferStatus.completed ? current.size : current.sent,
      bytesPerSecond: status == TransferStatus.completed ? 0 : null,
      clearEta: status != TransferStatus.transferring,
    );
    notifyListeners();
  }

  void pause() {
    if (!_active || _cancelled) return;
    _paused = true;
    runtimeControl.pause();
    notifyListeners();
  }

  void resume() {
    if (!_active || _cancelled) return;
    _paused = false;
    runtimeControl.resume();
    notifyListeners();
  }

  void cancel() {
    if (!_active) return;
    _cancelled = true;
    _paused = false;
    runtimeControl.cancel();
    for (final entry in _items.entries.toList()) {
      if (entry.value.status == TransferStatus.waiting ||
          entry.value.status == TransferStatus.transferring) {
        _items[entry.key] = entry.value.copyWith(
          status: TransferStatus.cancelled,
          bytesPerSecond: 0,
          clearEta: true,
        );
      }
    }
    notifyListeners();
  }

  void finish() {
    _active = false;
    _paused = false;
    notifyListeners();
  }

  void clear() {
    _peer = '';
    _active = false;
    _paused = false;
    _cancelled = false;
    _items.clear();
    _lastBytes.clear();
    _lastTimes.clear();
    notifyListeners();
  }
}
