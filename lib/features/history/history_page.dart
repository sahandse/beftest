import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  String _timeText(DateTime date) {
    final d = date.toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _dateText(DateTime date) {
    final d = date.toLocal();
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  String _sectionFor(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final local = date.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'امروز';
    if (diff == 1) return 'دیروز';
    return 'قدیمی‌تر';
  }

  Map<String, List<HistoryItem>> _grouped(List<HistoryItem> items) {
    final map = <String, List<HistoryItem>>{
      'امروز': [],
      'دیروز': [],
      'قدیمی‌تر': [],
    };
    for (final item in items) {
      map[_sectionFor(item.createdAt)]!.add(item);
    }
    return map;
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

    HapticFeedback.lightImpact();
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
    final groups = _grouped(visible);

    return Scaffold(
      appBar: AppBar(
        title: const Text('تاریخچه'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'پاک کردن تاریخچه',
              onPressed: () async {
                HapticFeedback.mediumImpact();
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
                          onSelected: (_) {
                            HapticFeedback.selectionClick();
                            setState(() => _filter = filter);
                          },
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                      ? const _HistoryEmptyState()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
                          children: [
                            for (final entry in groups.entries)
                              if (entry.value.isNotEmpty) ...[
                                _SectionTitle(
                                  title: entry.key,
                                  count: entry.value.length,
                                ),
                                const SizedBox(height: 8),
                                ...entry.value.asMap().entries.map(
                                      (indexed) => _TimelineItem(
                                        item: indexed.value,
                                        first: indexed.key == 0,
                                        last:
                                            indexed.key == entry.value.length - 1,
                                        sizeText: _sizeText(indexed.value.size),
                                        dateText:
                                            _dateText(indexed.value.createdAt),
                                        timeText:
                                            _timeText(indexed.value.createdAt),
                                        retrying:
                                            _retryingId == indexed.value.id,
                                        canRetry:
                                            indexed.value.sent &&
                                                indexed.value.sourcePath != null &&
                                                widget.onRetry != null,
                                        onRetry: () => _retry(indexed.value),
                                      ),
                                    ),
                                const SizedBox(height: 18),
                              ],
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;

  const _SectionTitle({
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            '$count',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final HistoryItem item;
  final bool first;
  final bool last;
  final String sizeText;
  final String dateText;
  final String timeText;
  final bool retrying;
  final bool canRetry;
  final VoidCallback onRetry;

  const _TimelineItem({
    required this.item,
    required this.first,
    required this.last,
    required this.sizeText,
    required this.dateText,
    required this.timeText,
    required this.retrying,
    required this.canRetry,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = item.success
        ? item.sent
            ? Icons.north_east_rounded
            : Icons.south_west_rounded
        : Icons.error_outline_rounded;

    final bubble = item.success
        ? item.sent
            ? cs.primaryContainer
            : cs.secondaryContainer
        : cs.errorContainer;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: first ? Colors.transparent : cs.outlineVariant,
                  ),
                ),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: bubble,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 19),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: last ? Colors.transparent : cs.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 5),
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${item.peer} • $sizeText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$dateText • $timeText',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (canRetry)
                    IconButton.filledTonal(
                      tooltip: 'ارسال دوباره',
                      onPressed: retrying ? null : onRetry,
                      icon: retrying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                              ),
                            )
                          : const Icon(Icons.replay_rounded),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.primaryContainer.withValues(alpha: .45),
                  ),
                ),
                Transform.rotate(
                  angle: -.18,
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      size: 34,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'هنوز انتقالی نداری',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'ارسال‌ها و دریافت‌های بعدی اینجا به شکل تایم‌لاین دیده می‌شوند.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
