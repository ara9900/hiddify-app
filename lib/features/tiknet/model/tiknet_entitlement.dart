import 'package:hiddify/features/tiknet/service/tiknet_api.dart';

/// Why the customer may not use VPN / catalog free servers.
enum TikNetEntitlementBlock {
  /// Subscription calendar date / panel `is_expired` / days remaining.
  expired,

  /// `traffic_used_bytes >= traffic_limit_bytes` when a positive limit exists.
  trafficExhausted,

  /// Admin/reseller disabled or blocked the account.
  inactive,

  /// Panel says there is no active subscription order.
  noSubscription,
}

/// Client-side gate shared by connect UI, sync, and the server picker.
///
/// Personal nodes are also killed by Pasargard/Sanaei when volume/time ends or
/// the account is disabled. Catalog (emergency free) servers are *not* — so the
/// app must refuse connect and stop merging catalog configs whenever the user
/// is ineligible.
class TikNetEntitlement {
  const TikNetEntitlement._({
    required this.allowed,
    this.block,
    this.message = '',
    this.expireDate,
  });

  const TikNetEntitlement.allowed() : this._(allowed: true);

  factory TikNetEntitlement.blocked(
    TikNetEntitlementBlock block, {
    String message = '',
    DateTime? expireDate,
  }) {
    return TikNetEntitlement._(
      allowed: false,
      block: block,
      message: message,
      expireDate: expireDate,
    );
  }

  final bool allowed;
  final TikNetEntitlementBlock? block;
  final String message;
  final DateTime? expireDate;

  bool get blocksCatalog => !allowed;
  bool get blocksConnect => !allowed;
}

/// Evaluate [info] the same way the UI and sync must enforce.
///
/// Prefer explicit panel flags (`is_expired`, `is_active`, `status`, …) and fall
/// back to date / traffic maths so older panels keep working.
TikNetEntitlement evaluateTikNetEntitlement(TikNetUserInfo? info, {DateTime? now}) {
  if (info == null) return const TikNetEntitlement.allowed();
  final at = now ?? DateTime.now();

  if (info.isBlocked == true || info.isActive == false) {
    return TikNetEntitlement.blocked(
      TikNetEntitlementBlock.inactive,
      message: 'حساب شما غیرفعال یا مسدود شده است. برای پیگیری با پشتیبانی تماس بگیرید.',
    );
  }

  final status = (info.status ?? '').trim().toLowerCase();
  if (status.isNotEmpty && _inactiveStatuses.contains(status)) {
    return TikNetEntitlement.blocked(
      TikNetEntitlementBlock.inactive,
      message: 'حساب شما غیرفعال یا مسدود شده است. برای پیگیری با پشتیبانی تماس بگیرید.',
    );
  }

  final expiredByFlag = info.isExpired == true;
  final expiredByDate = info.expireDate != null && !at.isBefore(info.expireDate!);
  final expiredByDays = info.daysRemaining != null && info.daysRemaining! <= 0;
  if (expiredByFlag || expiredByDate || expiredByDays) {
    final when = info.expireDate;
    final msg = when != null
        ? 'اشتراک شما به پایان رسیده است.'
        : 'اشتراک شما منقضی شده است.';
    return TikNetEntitlement.blocked(
      TikNetEntitlementBlock.expired,
      message: msg,
      expireDate: when,
    );
  }

  final used = info.trafficUsedBytes;
  final limit = info.trafficLimitBytes;
  if (used != null && limit != null && limit > 0 && used >= limit) {
    return TikNetEntitlement.blocked(
      TikNetEntitlementBlock.trafficExhausted,
      message: 'حجم اشتراک شما تمام شده است. برای ادامه، اشتراک را تمدید کنید.',
    );
  }

  if (!info.hasSubscription) {
    return TikNetEntitlement.blocked(
      TikNetEntitlementBlock.noSubscription,
      message: 'اشتراک فعالی ندارید. برای اتصال، یک پلن فعال تهیه کنید.',
    );
  }

  return const TikNetEntitlement.allowed();
}

const _inactiveStatuses = {
  'disabled',
  'blocked',
  'banned',
  'suspended',
  'inactive',
  'deactivated',
  'rejected',
};
