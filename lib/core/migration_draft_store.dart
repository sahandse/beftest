import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class MigrationDraft {
  final List<String> paths;
  final DateTime createdAt;

  const MigrationDraft({
    required this.paths,
    required this.createdAt,
  });
}

class MigrationDraftStore {
  static const _pathsKey = 'migration_draft_paths';
  static const _createdKey = 'migration_draft_created_at';

  Future<void> save(List<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pathsKey, paths);
    await prefs.setString(
      _createdKey,
      DateTime.now().toIso8601String(),
    );
  }

  Future<MigrationDraft?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_pathsKey) ?? const <String>[];
    if (raw.isEmpty) return null;

    final existing = <String>[];
    for (final path in raw) {
      if (await File(path).exists()) {
        existing.add(path);
      }
    }

    if (existing.isEmpty) {
      await clear();
      return null;
    }

    final created = DateTime.tryParse(
          prefs.getString(_createdKey) ?? '',
        ) ??
        DateTime.now();

    if (DateTime.now().difference(created) > const Duration(days: 7)) {
      await clear();
      return null;
    }

    if (existing.length != raw.length) {
      await save(existing);
    }

    return MigrationDraft(
      paths: existing,
      createdAt: created,
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pathsKey);
    await prefs.remove(_createdKey);
  }
}
