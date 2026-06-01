/// Panel-driven in-app update metadata (GET /api/customer/app-update).
class TikNetAppUpdateInfo {
  const TikNetAppUpdateInfo({
    required this.enabled,
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.force,
    required this.changelog,
    required this.sha256,
  });

  final bool enabled;
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final bool force;
  final String changelog;
  final String sha256;

  static TikNetAppUpdateInfo disabled() => const TikNetAppUpdateInfo(
        enabled: false,
        versionCode: 0,
        versionName: '',
        apkUrl: '',
        force: false,
        changelog: '',
        sha256: '',
      );

  static TikNetAppUpdateInfo? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final update = json['update'];
    if (update is! Map<String, dynamic>) return null;
    final enabled = update['enabled'] as bool? ?? false;
    if (!enabled) return disabled();
    final versionCode = (update['version_code'] as num?)?.toInt() ?? 0;
    final apkUrl = (update['apk_url'] as String?)?.trim() ?? '';
    if (versionCode <= 0 || apkUrl.isEmpty) return disabled();
    return TikNetAppUpdateInfo(
      enabled: true,
      versionCode: versionCode,
      versionName: (update['version_name'] as String?)?.trim() ?? '',
      apkUrl: apkUrl,
      force: update['force'] as bool? ?? false,
      changelog: (update['changelog'] as String?)?.trim() ?? '',
      sha256: ((update['sha256'] as String?) ?? '').trim().toLowerCase(),
    );
  }

  bool get isNewerThanInstalled => enabled && versionCode > 0;
}
