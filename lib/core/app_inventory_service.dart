import 'package:flutter/services.dart';
import 'package:installed_apps/installed_apps.dart';

class InstalledAppVersion {
  final String packageName;
  final String name;
  final String versionName;
  final int versionCode;

  const InstalledAppVersion({
    required this.packageName,
    required this.name,
    required this.versionName,
    required this.versionCode,
  });

  Map<String, dynamic> toJson() => {
        'packageName': packageName,
        'name': name,
        'versionName': versionName,
        'versionCode': versionCode,
      };

  factory InstalledAppVersion.fromJson(Map<String, dynamic> json) {
    return InstalledAppVersion(
      packageName: (json['packageName'] ?? '').toString(),
      name: (json['name'] ?? json['packageName'] ?? '').toString(),
      versionName: (json['versionName'] ?? '').toString(),
      versionCode: int.tryParse('${json['versionCode'] ?? 0}') ?? 0,
    );
  }
}

class PeerAppUpdate {
  final String packageName;
  final String name;
  final String currentVersion;
  final int currentVersionCode;
  final String remoteVersion;
  final int remoteVersionCode;
  final int? size;

  const PeerAppUpdate({
    required this.packageName,
    required this.name,
    required this.currentVersion,
    required this.currentVersionCode,
    required this.remoteVersion,
    required this.remoteVersionCode,
    this.size,
  });

  factory PeerAppUpdate.fromJson(Map<String, dynamic> json) {
    return PeerAppUpdate(
      packageName: (json['packageName'] ?? '').toString(),
      name: (json['name'] ?? json['packageName'] ?? '').toString(),
      currentVersion: (json['currentVersion'] ?? '').toString(),
      currentVersionCode:
          int.tryParse('${json['currentVersionCode'] ?? 0}') ?? 0,
      remoteVersion: (json['remoteVersion'] ?? '').toString(),
      remoteVersionCode:
          int.tryParse('${json['remoteVersionCode'] ?? 0}') ?? 0,
      size: int.tryParse('${json['size'] ?? ''}'),
    );
  }
}

class AppInventoryService {
  static const _channel = MethodChannel('ir.befrest/app_export');

  Future<List<InstalledAppVersion>> loadInstalledVersions() async {
    final apps = await InstalledApps.getInstalledApps(
      excludeSystemApps: true,
      excludeNonLaunchableApps: true,
      withIcon: false,
      detectPlatformType: false,
    );

    return apps
        .map(
          (app) => InstalledAppVersion(
            packageName: app.packageName,
            name: app.name,
            versionName: app.versionName,
            versionCode: app.versionCode,
          ),
        )
        .where((app) => app.packageName.isNotEmpty && app.versionCode > 0)
        .toList(growable: false);
  }

  Future<String?> exportApk(InstalledAppVersion app) async {
    try {
      return await _channel.invokeMethod<String>(
        'exportApk',
        {
          'packageName': app.packageName,
          'label': app.name,
          'version': app.versionName,
        },
      );
    } on PlatformException {
      return null;
    }
  }
}
