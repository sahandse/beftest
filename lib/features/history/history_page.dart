import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/transfer_history_store.dart';

enum HistoryFilter { all, sent, received, failed }

class HistoryPage extends StatefulWidget {
  final Future<void> Function(HistoryItem item)? onRetry;

  const HistoryPage({
    super.key,
    this.onRetry,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _store = TransferHistoryStore();
  List<HistoryItem> _items = const [];
  HistoryFilter _filter = HistoryFilter.all;
  bool _loading = true;
  String? _retryingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _store.load();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  List<HistoryItem> get _visible {
    switch (_filter) {
      case HistoryFilter.all:
        return _items;
      case HistoryFilter.sent:
        return _items.where((item) => item.sent).toList();
      case HistoryFilter.received:
        return _items.where((item) => !item.sent).toList();
      case HistoryFilter.failed:
        return _items.where((item) => !item.success).toList();
    }
  }

  String _filterLabel(HistoryFilter filter) {
    switch (filter) {
      case HistoryFilter.all:
        return 'همه';
      case HistoryFilter.sent:
        return 'ارسال';
      case HistoryFilter.received:
        return 'دریافت';
      case HistoryFilter.failed:
        return 'ناموفق';
    }
  }

  String _sizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  String _dateText(DateTime date) {
    final d = date.toLocal();
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/'
        '${d.day.toString().padLeft(2, '0')}  '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  Future<bool> _canRetry(HistoryItem item) async {
    final path = item.sourcePath;
    if (!item.sent || path == null || path.isEmpty) return false;
    return File(path).exists();
  }

  Future<void> _retry(HistoryItem item) async {
    final callback = widget.onRetry;
    if (callback == null) return;

    if (!await _canRetry(item)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فایل اصلی دیگر روی گوشی پیدا نشد.')),
      );
      return;
    }

    setState(() => _retryingId = item.id);
    try {
      await callback(item);
    } finally {
      if (mounted) setState(() => _retryingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تاریخچه انتقال'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'پاک‌کردن تاریخچه',
              onPressed: () async {
                await _store.clear();
                await _load();
              },
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: HistoryFilter.values
                    .map(
                      (filter) => Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text(_filterLabel(filter)),
                          selected: _filter == filter,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.history_rounded, size: 56),
                                SizedBox(height: 12),
                                Text(
                                  'چیزی اینجا نیست',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = visible[index];
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Icon(
                                    item.success
                                        ? (item.sent
                                            ? Icons.north_east_rounded
                                            : Icons.south_west_rounded)
                                        : Icons.error_outline_rounded,
                                  ),
                                ),
                                title: Text(
                                  item.fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${item.peer} • ${_sizeText(item.size)}\n'
                                  '${_dateText(item.createdAt)}',
                                ),
                                isThreeLine: true,
                                trailing: item.sent &&
                                        item.sourcePath != null &&
                                        widget.onRetry != null
                                    ? IconButton(
                                        tooltip: 'ارسال دوباره',
                                        onPressed: _retryingId == item.id
                                            ? null
                                            : () => _retry(item),
                                        icon: _retryingId == item.id
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2.4,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.replay_rounded,
                                              ),
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
