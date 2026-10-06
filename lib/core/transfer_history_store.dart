
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class HistoryItem {
  final String id;
  final String peer;
  final String fileName;
  final int size;
  final bool sent;
  final bool success;
  final DateTime createdAt;
  final String? sourcePath;
  final String? peerFingerprint;

  const HistoryItem({
    required this.id,
    required this.peer,
    required this.fileName,
    required this.size,
    required this.sent,
    required this.success,
    required this.createdAt,
    this.sourcePath,
    this.peerFingerprint,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'peer': peer,
        'fileName': fileName,
        'size': size,
        'sent': sent,
        'success': success,
        'createdAt': createdAt.toIso8601String(),
        'sourcePath': sourcePath,
        'peerFingerprint': peerFingerprint,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> json) => HistoryItem(
        id: json['id'].toString(),
        peer: json['peer'].toString(),
        fileName: json['fileName'].toString(),
        size: int.tryParse('${json['size']}') ?? 0,
        sent: json['sent'] == true,
        success: json['success'] == true,
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
        sourcePath: json['sourcePath']?.toString(),
        peerFingerprint: json['peerFingerprint']?.toString(),
      );
}

class TransferHistoryStore {
  static const _key = 'transfer_history';

  Future<List<HistoryItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    return raw
        .map((e) => HistoryItem.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> add(HistoryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_key) ?? <String>[];
    items.insert(0, jsonEncode(item.toJson()));
    if (items.length > 100) {
      items.removeRange(100, items.length);
    }
    await prefs.setStringList(_key, items);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
