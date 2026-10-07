import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_settings.dart';
import '../../core/app_inventory_service.dart';
import '../../core/share_intent_service.dart';
import '../../core/storage_guard.dart';
import '../../core/trusted_devices_store.dart';
import '../../core/tls_identity.dart';
import '../../core/transfer_background_service.dart';
import '../../core/transfer_notifications.dart';
import '../../core/transfer_session_controller.dart';
import '../../core/transfer_history_store.dart';
import '../../network/discovery_service.dart';
import '../../network/nearby_device.dart';
import '../../network/transfer_server.dart';
import '../../network/transfer_service.dart';
import '../receive/receive_page.dart';
import '../history/history_page.dart';
import '../send/send_page.dart';
import '../send/apps_picker_page.dart';
import '../settings/settings_page.dart';

class HomePage extends StatefulWidget {
  final AppSettings settings;

  const HomePage({
    super.key,
    required this.settings,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _discovery = DiscoveryService();
  final _server = TransferServer();
  late final TlsIdentity _identity;
  late final TransferService _transfer;
  final _historyStore = TransferHistoryStore();
  final _uuid = const Uuid();
  final _shareIntent = ShareIntentService();
  final _trustedDevices = TrustedDevicesStore();
  final _transferSession = TransferSessionController();

  List<NearbyDevice> _devices = const [];
  Set<String> _trustedFingerprints = <String>{};
  Map<String, String> _pendingRelativePaths = const {};
  String? _networkError;

  @override
  void initState() {
    super.initState();
    _discovery.devicesStream.listen((devices) {
      if (!mounted) return;
      setState(() => _devices = devices);
    });
    TransferBackgroundService.initialize();
    _refreshTrustedFingerprints();
    _initializeSecureTransfer();
  }

  Future<void> _refreshTrustedFingerprints() async {
    final devices = await _trustedDevices.load();
    if (!mounted) return;
    setState(() {
      _trustedFingerprints =
          devices.map((device) => device.fingerprint).toSet();
    });
  }

  Future<void> _initializeSecureTransfer() async {
    _identity = await const TlsIdentityStore().loadOrCreate();
    await widget.settings.setFingerprint(_identity.fingerprint);
    _transfer = TransferService(identity: _identity);
    await _startNetwork();
    await _startShareIntent();
    if (mounted) setState(() {});
  }

  Future<void> _startShareIntent() async {
    await _shareIntent.start((paths) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openSend(sharedPaths: paths);
      });
    });
  }

  Future<void> _startNetwork() async {
    _server.onIncomingRequest = (incoming) async {
      if (!mounted) return false;

      final storage = await StorageGuard.checkForIncoming(incoming.totalSize);
      if (!mounted) return false;

      if (storage.known && !storage.enough) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.storage_rounded),
            title: const Text('فضای کافی نیست'),
            content: Text(
              'برای این انتقال حداقل ${_sizeText(storage.requiredBytes)} فضا لازم است، '
              'اما فقط ${_sizeText(storage.freeBytes)} فضای آزاد داری.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('باشه'),
              ),
            ],
          ),
        );
        return false;
      }

      if (widget.settings.isQuickReceiveActive) {
        return true;
      }

      if (incoming.senderFingerprint.isNotEmpty &&
          await _trustedDevices.contains(incoming.senderFingerprint)) {
        return true;
      }

      if (!mounted) return false;
      final decision = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.move_to_inbox_rounded),
          title: Text('دریافت از ${incoming.senderAlias}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${incoming.files.length} فایل'),
              const SizedBox(height: 6),
              Text('حجم کل: ${_sizeText(incoming.totalSize)}'),
              if (storage.known) ...[
                const SizedBox(height: 6),
                Text('فضای آزاد: ${_sizeText(storage.freeBytes)}'),
              ],
              const SizedBox(height: 14),
              ...incoming.files.take(4).map(
                    (file) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        '• ${file.fileName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 0),
              child: const Text('رد'),
            ),
            TextButton(
              onPressed: incoming.senderFingerprint.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, 2),
              child: const Text('اعتماد و دریافت'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 1),
              icon: const Icon(Icons.download_rounded),
              label: const Text('دریافت'),
            ),
          ],
        ),
      );

      if (decision == 2 && incoming.senderFingerprint.isNotEmpty) {
        await _trustedDevices.trust(
          fingerprint: incoming.senderFingerprint,
          alias: incoming.senderAlias,
        );
        await _refreshTrustedFingerprints();
        return true;
      }

      return decision == 1;
    };

    _server.onAppUpdateRequest = (request) async {
      if (!mounted) return false;

      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.system_update_alt_rounded),
          title: Text('ارسال بروزرسانی به ${request.senderAlias}؟'),
          content: Text(
            '${request.packageNames.length} برنامه برای بروزرسانی درخواست شده. '
            'فقط APK همین موارد ارسال می‌شود.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('رد'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.upload_rounded),
              label: const Text('تأیید ارسال'),
            ),
          ],
        ),
      );

      return approved ?? false;
    };

    _server.onIncomingComplete = (event) async {
      if (event.success) {
        HapticFeedback.mediumImpact();
      }
      await _historyStore.add(
        HistoryItem(
          id: _uuid.v4(),
          peer: event.senderAlias,
          fileName: event.fileName,
          size: event.size,
          sent: false,
          success: event.success,
          createdAt: DateTime.now(),
        ),
      );
    };

    try {
      await _server.start(
        alias: widget.settings.alias,
        identity: _identity,
        pin: widget.settings.pinEnabled ? widget.settings.pin : null,
      );
      await _discovery.start(
        alias: widget.settings.alias,
        fingerprint: _identity.fingerprint,
        identity: _identity,
      );
      if (mounted) {
        setState(() => _networkError = null);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _networkError = error.toString());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'شبکه محلی بفرست راه‌اندازی نشد؛ Wi‑Fi را بررسی کن و دوباره تلاش کن.',
            ),
          ),
        );
      });
    }
  }

  Future<void> _restartNetwork() async {
    await _server.stop();
    await _startNetwork();
  }

  Future<String?> _askText() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('متن یا لینک'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            hintText: 'متن یا لینک را وارد کن',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('ادامه'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<List<String>> _pickPaths(SendCategory category) async {
    if (category == SendCategory.photos) {
      final images = await ImagePicker().pickMultiImage(
        requestFullMetadata: false,
      );
      return images.map((image) => image.path).toList(growable: false);
    }

    if (category == SendCategory.apps) {
      final path = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => const AppsPickerPage(),
        ),
      );
      return path == null || path.isEmpty ? const [] : [path];
    }

    if (category == SendCategory.text) {
      final text = await _askText();
      if (text == null || text.isEmpty) return const [];
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/befrest-text-${DateTime.now().millisecondsSinceEpoch}.txt',
      );
      await file.writeAsString(text);
      return [file.path];
    }

    if (category == SendCategory.folders) {
      final folder = await FilePicker.getDirectoryPath();
      if (folder == null) return const [];
      final dir = Directory(folder);
      final rootName = dir.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      final files = await dir
          .list(recursive: true, followLinks: false)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();

      final rootPrefix = dir.path.endsWith(Platform.pathSeparator)
          ? dir.path
          : '${dir.path}${Platform.pathSeparator}';
      final relative = <String, String>{};

      for (final file in files) {
        final path = file.path;
        final child = path.startsWith(rootPrefix)
            ? path.substring(rootPrefix.length)
            : path.split(Platform.pathSeparator).last;
        relative[path] =
            [rootName, child].join(Platform.pathSeparator);
      }

      _pendingRelativePaths = relative;
      return files.map((file) => file.path).toList(growable: false);
    }

    FileType type = FileType.any;
    List<String>? extensions;
    switch (category) {
      case SendCategory.photos:
        type = FileType.any;
      case SendCategory.videos:
        type = FileType.video;
      case SendCategory.music:
        type = FileType.audio;
      case SendCategory.documents:
        type = FileType.custom;
        extensions = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt'];
      case SendCategory.apps:
        type = FileType.custom;
        extensions = ['apk'];
      case SendCategory.files:
      case SendCategory.folders:
      case SendCategory.text:
        type = FileType.any;
    }

    final result = await FilePicker.pickFiles(
      type: type,
      allowedExtensions: extensions,
    );

    return result
        .map((file) => file.path)
        .whereType<String>()
        .toList(growable: false);
  }

  Future<String?> _askForPin() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('PIN دستگاه'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'PIN را وارد کن'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('ادامه'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _sendTo(
    NearbyDevice device,
    SendCategory category, {
    String? pin,
    List<String>? providedPaths,
  }) async {
    final paths = providedPaths ?? await _pickPaths(category);
    if (paths.isEmpty) return;

    try {
      final files = await _transfer.buildFiles(
        paths,
        relativePaths: _pendingRelativePaths,
      );
      _pendingRelativePaths = const {};
      _transferSession.start(
        peer: device.alias,
        files: files,
      );
      try {
        await TransferBackgroundService.start(
          peer: device.alias,
          filesCount: files.length,
        );
      } catch (_) {
        // Background notification must never block the actual transfer.
      }
      final sent = <String, int>{};

      await _transfer.send(
        device: device,
        alias: widget.settings.alias,
        fingerprint: widget.settings.fingerprint,
        files: files,
        pin: pin,
        onProgress: (id, value, fileTotal) {
          sent[id] = value;
          _transferSession.updateProgress(id, value, fileTotal);
          String currentName = 'در حال انتقال';
          for (final file in files) {
            if (file.id == id) {
              currentName = file.fileName;
              break;
            }
          }
          TransferBackgroundService.updateProgress(
            fileName: currentName,
            sent: value,
            total: fileTotal,
          );
        },
        onStatus: _transferSession.updateStatus,
        control: _transferSession.runtimeControl,
      );

      for (final file in files) {
        await _historyStore.add(
          HistoryItem(
            id: _uuid.v4(),
            peer: device.alias,
            fileName: file.fileName,
            size: file.size,
            sent: true,
            success: true,
            createdAt: DateTime.now(),
            sourcePath: file.file.path,
            peerFingerprint: device.fingerprint,
          ),
        );
      }

      await TransferNotifications.completed(
        peer: device.alias,
        filesCount: files.length,
      );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ارسال به ${device.alias} کامل شد')),
      );
    } catch (error) {
      if (error.toString().contains('PIN_REQUIRED') && mounted) {
        final entered = await _askForPin();
        if (entered != null && entered.isNotEmpty) {
          await _sendTo(
            device,
            category,
            pin: entered,
            providedPaths: providedPaths,
          );
          return;
        }
      }
      await TransferNotifications.failed(peer: device.alias);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_transferErrorMessage(error))),
        );
      }
    } finally {
      _transferSession.finish();
      try {
        await TransferBackgroundService.stop();
      } catch (_) {
        // Transfer result is independent from notification cleanup.
      }
    }
  }

  Future<List<PeerAppUpdate>> _checkPeerAppUpdates(
    NearbyDevice device,
  ) async {
    return _transfer.checkAppUpdates(
      device: device,
      alias: widget.settings.alias,
      fingerprint: widget.settings.fingerprint,
    );
  }

  Future<void> _receivePeerAppUpdates(
    NearbyDevice device,
    List<PeerAppUpdate> updates,
    void Function(
      PeerAppUpdate update,
      int received,
      int? total,
    ) onProgress,
  ) async {
    final files = await _transfer.receiveAppUpdates(
      device: device,
      alias: widget.settings.alias,
      fingerprint: widget.settings.fingerprint,
      updates: updates,
      onProgress: onProgress,
    );

    for (final file in files) {
      final stat = await file.stat();
      await _historyStore.add(
        HistoryItem(
          id: _uuid.v4(),
          peer: device.alias,
          fileName: file.uri.pathSegments.last,
          size: stat.size,
          sent: false,
          success: true,
          createdAt: DateTime.now(),
          peerFingerprint: device.fingerprint,
        ),
      );
    }

    if (files.isNotEmpty) {
      HapticFeedback.mediumImpact();
    }
  }

  Future<void> _retryHistoryItem(HistoryItem item) async {
    final path = item.sourcePath;
    if (path == null || path.isEmpty || !await File(path).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فایل اصلی دیگر پیدا نشد.')),
      );
      return;
    }

    NearbyDevice? device;
    final fingerprint = item.peerFingerprint;
    if (fingerprint != null && fingerprint.isNotEmpty) {
      for (final candidate in _devices) {
        if (candidate.fingerprint == fingerprint) {
          device = candidate;
          break;
        }
      }
    }

    device ??= _devices.cast<NearbyDevice?>().firstWhere(
          (candidate) => candidate?.alias == item.peer,
          orElse: () => null,
        );

    if (device == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${item.peer} الان نزدیک نیست.')),
      );
      return;
    }

    await _sendTo(
      device,
      SendCategory.files,
      providedPaths: [path],
    );
  }

  String _transferErrorMessage(Object error) {
    final value = error.toString();

    if (error is HandshakeException ||
        value.contains('CERTIFICATE') ||
        value.contains('Handshake')) {
      return 'اتصال امن با دستگاه مقصد برقرار نشد. هر دو گوشی را یک‌بار ببند و دوباره باز کن.';
    }

    if (error is SocketException ||
        value.contains('Connection refused') ||
        value.contains('timed out') ||
        value.contains('Network is unreachable')) {
      return 'دستگاه مقصد در شبکه در دسترس نیست. هر دو گوشی باید روی یک Wi‑Fi یا Hotspot مشترک باشند.';
    }

    if (value.contains('403') || value.contains('FORBIDDEN')) {
      return 'دریافت روی دستگاه مقصد رد شد.';
    }

    if (value.contains('CHECKSUM_MISMATCH')) {
      return 'فایل کامل نرسید؛ دوباره ارسال کن.';
    }

    return 'انتقال انجام نشد. اتصال دو گوشی را بررسی کن و دوباره بزن.';
  }

  String _sizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  void _openHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: HistoryPage(
            onRetry: _retryHistoryItem,
          ),
        ),
      ),
    );
  }

  void _openSend({List<String> sharedPaths = const []}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: SendPage(
            devices: _devices,
            sessionController: _transferSession,
            trustedFingerprints: _trustedFingerprints,
            onOpenHistory: _openHistory,
            onCheckAppUpdates: _checkPeerAppUpdates,
            onReceiveAppUpdates: _receivePeerAppUpdates,
            onSend: _sendTo,
            sharedPaths: sharedPaths,
            onSendShared: (device, paths) => _sendTo(
              device,
              SendCategory.files,
              providedPaths: paths,
            ),
          ),
        ),
      ),
    );
  }

  void _openReceive() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: ReceivePage(settings: widget.settings),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _shareIntent.dispose();
    _transferSession.dispose();
    _discovery.dispose();
    _server.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final horizontal = size.width >= 720;

    final receive = _ActionPane(
      title: 'دریافت',
      subtitle: 'گوشی را آماده دریافت کن',
      icon: Icons.south_west_rounded,
      background: cs.primaryContainer,
      foreground: cs.onPrimaryContainer,
      onTap: _openReceive,
    );

    final send = _ActionPane(
      title: 'ارسال',
      subtitle: _devices.isEmpty
          ? 'فایل را مستقیم بفرست'
          : '${_devices.length} دستگاه نزدیک',
      icon: Icons.north_east_rounded,
      background: cs.tertiaryContainer,
      foreground: cs.onTertiaryContainer,
      onTap: _openSend,
      accent: true,
    );

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'بفرست',
                            style: TextStyle(
                              fontSize: 29,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.7,
                            ),
                          ),
                          Text(
                            'بدون اینترنت • مستقیم • ساده',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'تاریخچه',
                      onPressed: _openHistory,
                      icon: const Icon(Icons.history_rounded),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'تنظیمات',
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SettingsPage(
                              settings: widget.settings,
                              onNetworkRestart: _restartNetwork,
                            ),
                          ),
                        );
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
              ),
              if (_networkError != null) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        color: cs.onErrorContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'اتصال شبکه محلی آماده نیست. Wi‑Fi را روشن کن و از تنظیمات «راه‌اندازی دوباره شبکه» را بزن.',
                          style: TextStyle(
                            color: cs.onErrorContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Expanded(
                child: horizontal
                    ? Row(
                        children: [
                          Expanded(child: receive),
                          const SizedBox(width: 12),
                          Expanded(child: send),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(child: receive),
                          const SizedBox(height: 12),
                          Expanded(child: send),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionPane extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;
  final bool accent;

  const _ActionPane({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.accent = false,
  });

  @override
  State<_ActionPane> createState() => _ActionPaneState();
}

class _ActionPaneState extends State<_ActionPane> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _activate() {
    HapticFeedback.lightImpact();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.only(
      topRight: const Radius.circular(42),
      topLeft: Radius.circular(widget.accent ? 24 : 42),
      bottomRight: Radius.circular(widget.accent ? 24 : 42),
      bottomLeft: const Radius.circular(42),
    );

    return AnimatedScale(
      scale: _pressed ? .985 : 1,
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOutCubic,
      child: Material(
        color: widget.background,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _activate,
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          child: Stack(
            children: [
              Positioned(
                left: -28,
                bottom: -42,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: .82, end: 1),
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) => Transform.scale(
                    scale: value,
                    child: child,
                  ),
                  child: Icon(
                    widget.icon,
                    size: 210,
                    color: widget.foreground.withValues(alpha: .075),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 24,
                end: 24,
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: widget.foreground.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    widget.icon,
                    color: widget.foreground,
                    size: 31,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: widget.foreground,
                        fontSize: 34,
                        height: .98,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.7,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        color: widget.foreground.withValues(alpha: .76),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: widget.foreground.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'باز کردن',
                                style: TextStyle(
                                  color: widget.foreground,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.arrow_back_rounded,
                                size: 17,
                                color: widget.foreground,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
