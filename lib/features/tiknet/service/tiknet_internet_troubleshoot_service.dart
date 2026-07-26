import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/settings/data/battery_optimization_repository.dart';
import 'package:hiddify/features/tiknet/service/tiknet_diagnostic_log.dart';
import 'package:hiddify/features/tiknet/service/tiknet_platform_diagnostics.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum TikNetTroubleshootStatus { ok, fail, warn, info }

enum TikNetTroubleshootSettingsTarget {
  none,
  date,
  vpn,
  apn,
  privateDns,
  wireless,
  battery,
  airplane,
}

class TikNetTroubleshootItem {
  const TikNetTroubleshootItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.status,
    this.settingsTarget = TikNetTroubleshootSettingsTarget.none,
  });

  final String id;
  final String title;
  final String detail;
  final TikNetTroubleshootStatus status;
  final TikNetTroubleshootSettingsTarget settingsTarget;
}

final tikNetInternetTroubleshootServiceProvider = Provider<TikNetInternetTroubleshootService>(
  (ref) => TikNetInternetTroubleshootService(ref),
);

class TikNetInternetTroubleshootService {
  TikNetInternetTroubleshootService(this._ref);

  final Ref _ref;

  static const _probeHost = 'www.gstatic.com';
  static const _probeUrl = 'https://www.gstatic.com/generate_204';

  Future<List<TikNetTroubleshootItem>> runChecks() async {
    final items = <TikNetTroubleshootItem>[];
    final native = await TikNetPlatformDiagnostics.getNetworkDiagnostics();

    if (Platform.isAndroid && native != null) {
      items.addAll(_androidNativeChecks(native));
    } else if (!Platform.isAndroid) {
      items.add(
        const TikNetTroubleshootItem(
          id: 'platform',
          title: 'پلتفرم',
          detail: 'بررسی کامل تنظیمات سیستم فقط روی اندروید در دسترس است. تست دسترسی اینترنت انجام می‌شود.',
          status: TikNetTroubleshootStatus.info,
        ),
      );
    } else {
      items.add(
        const TikNetTroubleshootItem(
          id: 'native',
          title: 'خواندن تنظیمات سیستم',
          detail: 'نتوانستیم وضعیت شبکه را از سیستم بخوانیم.',
          status: TikNetTroubleshootStatus.warn,
        ),
      );
    }

    items.add(await _dnsLookupCheck());
    items.add(await _httpReachabilityAndClockCheck(native));

    if (Platform.isAndroid) {
      items.add(await _batteryCheck(native));
      items.add(_apnManualHint());
      items.add(_alwaysOnVpnHint(native));
    }

    TikNetDiagnosticLog.i('diag', 'internet troubleshoot done', {
      'count': items.length,
      'fails': items.where((e) => e.status == TikNetTroubleshootStatus.fail).length,
    });
    return items;
  }

  bool get _tikNetVpnActive {
    if (_ref.read(tikNetUrlTestProbeActiveProvider)) return true;
    if (!(_ref.read(Preferences.startedByUser))) return false;
    return _ref.read(connectionNotifierProvider).valueOrNull is Connected;
  }

  List<TikNetTroubleshootItem> _androidNativeChecks(TikNetNativeNetworkSnapshot n) {
    final out = <TikNetTroubleshootItem>[];

    out.add(
      TikNetTroubleshootItem(
        id: 'airplane',
        title: 'حالت هواپیما',
        detail: n.airplaneMode ? 'حالت هواپیما روشن است و اینترنت قطع می‌شود.' : 'حالت هواپیما خاموش است.',
        status: n.airplaneMode ? TikNetTroubleshootStatus.fail : TikNetTroubleshootStatus.ok,
        settingsTarget: TikNetTroubleshootSettingsTarget.airplane,
      ),
    );

    final transport = <String>[
      if (n.isWifi) 'وای‌فای',
      if (n.isCellular) 'دیتای موبایل',
      if (n.isEthernet) 'اترنت',
      if (n.isVpn) 'VPN',
    ];
    out.add(
      TikNetTroubleshootItem(
        id: 'network',
        title: 'اتصال شبکه',
        detail: !n.hasInternet
            ? 'سیستم شبکه فعالی با قابلیت اینترنت گزارش نکرد.'
            : n.validated
                ? 'شبکه فعال است (${transport.isEmpty ? 'نامشخص' : transport.join(' + ')}).'
                : 'شبکه هست ولی هنوز validate نشده (احتمال captive portal یا قطع موقت).',
        status: !n.hasInternet
            ? TikNetTroubleshootStatus.fail
            : n.validated
                ? TikNetTroubleshootStatus.ok
                : TikNetTroubleshootStatus.warn,
        settingsTarget: TikNetTroubleshootSettingsTarget.wireless,
      ),
    );

    out.add(
      TikNetTroubleshootItem(
        id: 'auto_time',
        title: 'ساعت خودکار',
        detail: n.autoTime
            ? 'ساعت خودکار روشن است.'
            : 'ساعت خودکار خاموش است؛ اختلاف ساعت باعث خطای SSL می‌شود.',
        status: n.autoTime ? TikNetTroubleshootStatus.ok : TikNetTroubleshootStatus.fail,
        settingsTarget: TikNetTroubleshootSettingsTarget.date,
      ),
    );

    final dnsMode = n.privateDnsMode.toLowerCase();
    final privateDnsOff = dnsMode.isEmpty || dnsMode == 'off' || dnsMode == 'unknown';
    final privateDnsOk = privateDnsOff || dnsMode == 'opportunistic';
    out.add(
      TikNetTroubleshootItem(
        id: 'private_dns',
        title: 'DNS خصوصی',
        detail: privateDnsOff
            ? 'DNS خصوصی خاموش / خودکار است.'
            : dnsMode == 'hostname' || dnsMode == 'provider'
                ? 'DNS خصوصی روی «${n.privateDnsSpecifier ?? dnsMode}» تنظیم شده؛ اگر فیلتر/مسدود باشد اینترنت مختل می‌شود.'
                : 'حالت DNS: $dnsMode${n.privateDnsSpecifier != null ? ' (${n.privateDnsSpecifier})' : ''}',
        status: privateDnsOk ? TikNetTroubleshootStatus.ok : TikNetTroubleshootStatus.warn,
        settingsTarget: TikNetTroubleshootSettingsTarget.privateDns,
      ),
    );

    final ours = _tikNetVpnActive;
    if (n.isVpn && ours) {
      out.add(
        const TikNetTroubleshootItem(
          id: 'vpn_active',
          title: 'VPN فعال',
          detail: 'VPN فعال مربوط به خود TikNet است — طبیعی است.',
          status: TikNetTroubleshootStatus.ok,
          settingsTarget: TikNetTroubleshootSettingsTarget.vpn,
        ),
      );
    } else if (n.isVpn) {
      out.add(
        const TikNetTroubleshootItem(
          id: 'vpn_active',
          title: 'VPN فعال',
          detail: 'یک VPN دیگر روی گوشی فعال است. اگر «همیشه روشن» باشد ممکن است TikNet نتواند وصل شود.',
          status: TikNetTroubleshootStatus.warn,
          settingsTarget: TikNetTroubleshootSettingsTarget.vpn,
        ),
      );
    } else {
      out.add(
        const TikNetTroubleshootItem(
          id: 'vpn_active',
          title: 'VPN فعال',
          detail: 'VPN دیگری روی شبکهٔ فعلی دیده نشد.',
          status: TikNetTroubleshootStatus.ok,
          settingsTarget: TikNetTroubleshootSettingsTarget.vpn,
        ),
      );
    }

    return out;
  }

  Future<TikNetTroubleshootItem> _dnsLookupCheck() async {
    try {
      final result = await InternetAddress.lookup(_probeHost).timeout(const Duration(seconds: 5));
      if (result.isEmpty) {
        return const TikNetTroubleshootItem(
          id: 'dns',
          title: 'DNS / رزولوشن دامنه',
          detail: 'نام دامنه resolve نشد.',
          status: TikNetTroubleshootStatus.fail,
          settingsTarget: TikNetTroubleshootSettingsTarget.privateDns,
        );
      }
      return const TikNetTroubleshootItem(
        id: 'dns',
        title: 'DNS / رزولوشن دامنه',
        detail: 'دامنه www.gstatic.com با موفقیت resolve شد.',
        status: TikNetTroubleshootStatus.ok,
      );
    } catch (e) {
      return TikNetTroubleshootItem(
        id: 'dns',
        title: 'DNS / رزولوشن دامنه',
        detail: 'خطا در resolve دامنه: $e',
        status: TikNetTroubleshootStatus.fail,
        settingsTarget: TikNetTroubleshootSettingsTarget.privateDns,
      );
    }
  }

  Future<TikNetTroubleshootItem> _httpReachabilityAndClockCheck(TikNetNativeNetworkSnapshot? native) async {
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          followRedirects: false,
          validateStatus: (_) => true,
        ),
      );
      final started = DateTime.now();
      final res = await dio.getUri(Uri.parse(_probeUrl));
      final elapsed = DateTime.now().difference(started).inMilliseconds;

      var clockDetail = '';
      final dateHeader = res.headers.value('date');
      if (dateHeader != null && dateHeader.isNotEmpty) {
        try {
          final server = HttpDate.parse(dateHeader);
          final skew = DateTime.now().toUtc().difference(server.toUtc()).inSeconds.abs();
          if (skew > 120) {
            return TikNetTroubleshootItem(
              id: 'http',
              title: 'دسترسی اینترنت و ساعت',
              detail: 'اینترنت پاسخ داد (${elapsed}ms) ولی اختلاف ساعت حدود ${skew}s است — SSL ممکن است خراب شود.',
              status: TikNetTroubleshootStatus.fail,
              settingsTarget: TikNetTroubleshootSettingsTarget.date,
            );
          }
          clockDetail = ' · اختلاف ساعت OK';
        } catch (_) {
          // Ignore unparsable Date headers.
        }
      }

      if (res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 400) {
        final simHint = native?.isCellular == true ? ' (شبکه موبایل)' : '';
        return TikNetTroubleshootItem(
          id: 'http',
          title: 'دسترسی اینترنت',
          detail: 'پینگ HTTP به دامنهٔ تست موفق بود (${elapsed}ms)$simHint$clockDetail.',
          status: TikNetTroubleshootStatus.ok,
        );
      }
      return TikNetTroubleshootItem(
        id: 'http',
        title: 'دسترسی اینترنت',
        detail: 'پاسخ غیرمنتظره از دامنهٔ تست (کد ${res.statusCode}).',
        status: TikNetTroubleshootStatus.warn,
        settingsTarget: TikNetTroubleshootSettingsTarget.wireless,
      );
    } catch (e) {
      return TikNetTroubleshootItem(
        id: 'http',
        title: 'دسترسی اینترنت',
        detail: 'نتوانستیم به دامنهٔ تست وصل شویم. دیتای سیم‌کارت/وای‌فای را بررسی کنید. ($e)',
        status: TikNetTroubleshootStatus.fail,
        settingsTarget: TikNetTroubleshootSettingsTarget.wireless,
      );
    }
  }

  Future<TikNetTroubleshootItem> _batteryCheck(TikNetNativeNetworkSnapshot? native) async {
    var ignoring = native?.ignoringBatteryOptimizations;
    ignoring ??= await BatteryOptimizationRepositoryImpl().isIgnoringBatteryOptimizations();
    final ok = ignoring == true;
    return TikNetTroubleshootItem(
      id: 'battery',
      title: 'بهینه‌سازی باتری',
      detail: ok
          ? 'محدودیت بهینه‌سازی باتری برای TikNet برداشته شده (یا لازم نیست).'
          : 'بهینه‌سازی باتری ممکن است سرویس VPN را در پس‌زمینه قطع کند.',
      status: ok ? TikNetTroubleshootStatus.ok : TikNetTroubleshootStatus.warn,
      settingsTarget: TikNetTroubleshootSettingsTarget.battery,
    );
  }

  TikNetTroubleshootItem _apnManualHint() {
    return const TikNetTroubleshootItem(
      id: 'apn',
      title: 'پروکسی APN سیم‌کارت',
      detail:
          'اپ نمی‌تواند فیلد پروکسی APN را بخواند. در تنظیمات APN مطمئن شوید فیلد Proxy خالی است؛ پر بودن آن اینترنت را قطع می‌کند.',
      status: TikNetTroubleshootStatus.info,
      settingsTarget: TikNetTroubleshootSettingsTarget.apn,
    );
  }

  TikNetTroubleshootItem _alwaysOnVpnHint(TikNetNativeNetworkSnapshot? native) {
    final app = native?.alwaysOnVpnApp;
    final lockdown = native?.alwaysOnVpnLockdown == true;
    final ourPackageHint = app != null && (app.contains('tik') || app.contains('hiddify'));
    if (app != null && app.isNotEmpty) {
      if (ourPackageHint || _tikNetVpnActive) {
        return TikNetTroubleshootItem(
          id: 'always_on',
          title: 'VPN همیشه روشن',
          detail: 'Always-on مربوط به TikNet است ($app) — اگر عمداً روشن کرده‌اید مشکلی نیست.',
          status: TikNetTroubleshootStatus.info,
          settingsTarget: TikNetTroubleshootSettingsTarget.vpn,
        );
      }
      return TikNetTroubleshootItem(
        id: 'always_on',
        title: 'VPN همیشه روشن',
        detail: lockdown
            ? 'Always-on VPN با قفل فعال است ($app) و ممکن است مانع اتصال TikNet شود.'
            : 'Always-on VPN روی $app تنظیم شده؛ اگر مال اپ دیگری است آن را خاموش کنید.',
        status: TikNetTroubleshootStatus.warn,
        settingsTarget: TikNetTroubleshootSettingsTarget.vpn,
      );
    }
    return const TikNetTroubleshootItem(
      id: 'always_on',
      title: 'VPN همیشه روشن',
      detail:
          'اگر اپ دیگری Always-on VPN دارد، TikNet نمی‌تواند وصل شود. در تنظیمات VPN گوشی بررسی کنید (گاهی سیستم اجازهٔ خواندن این مقدار را نمی‌دهد).',
      status: TikNetTroubleshootStatus.info,
      settingsTarget: TikNetTroubleshootSettingsTarget.vpn,
    );
  }
}
