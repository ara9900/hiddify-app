import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/tiknet/model/tiknet_entitlement.dart';
import 'package:hiddify/features/tiknet/service/tiknet_api.dart';

TikNetUserInfo _info({
  bool hasSubscription = true,
  DateTime? expireDate,
  bool? isExpired,
  int? daysRemaining,
  int? trafficUsedBytes,
  int? trafficLimitBytes,
  bool? isActive,
  bool? isBlocked,
  String? status,
}) {
  return TikNetUserInfo(
    username: 'u',
    hasSubscription: hasSubscription,
    expireDate: expireDate,
    isExpired: isExpired,
    daysRemaining: daysRemaining,
    trafficUsedBytes: trafficUsedBytes,
    trafficLimitBytes: trafficLimitBytes,
    isActive: isActive,
    isBlocked: isBlocked,
    status: status,
  );
}

void main() {
  final now = DateTime(2026, 7, 30, 12);

  test('allows active subscribed user', () {
    final e = evaluateTikNetEntitlement(
      _info(expireDate: DateTime(2026, 8, 30), trafficUsedBytes: 1, trafficLimitBytes: 10),
      now: now,
    );
    expect(e.allowed, isTrue);
    expect(e.blocksCatalog, isFalse);
  });

  test('blocks when expire date passed', () {
    final e = evaluateTikNetEntitlement(
      _info(expireDate: DateTime(2026, 7, 1)),
      now: now,
    );
    expect(e.allowed, isFalse);
    expect(e.block, TikNetEntitlementBlock.expired);
    expect(e.blocksCatalog, isTrue);
  });

  test('blocks when is_expired flag set', () {
    final e = evaluateTikNetEntitlement(_info(isExpired: true), now: now);
    expect(e.block, TikNetEntitlementBlock.expired);
  });

  test('blocks when traffic exhausted', () {
    final e = evaluateTikNetEntitlement(
      _info(
        expireDate: DateTime(2026, 8, 30),
        trafficUsedBytes: 100,
        trafficLimitBytes: 100,
      ),
      now: now,
    );
    expect(e.block, TikNetEntitlementBlock.trafficExhausted);
    expect(e.blocksConnect, isTrue);
    expect(e.blocksCatalog, isTrue);
  });

  test('does not treat unlimited traffic as exhausted', () {
    final e = evaluateTikNetEntitlement(
      _info(
        expireDate: DateTime(2026, 8, 30),
        trafficUsedBytes: 999,
        trafficLimitBytes: 0,
      ),
      now: now,
    );
    expect(e.allowed, isTrue);
  });

  test('blocks inactive / blocked account', () {
    expect(
      evaluateTikNetEntitlement(_info(isActive: false), now: now).block,
      TikNetEntitlementBlock.inactive,
    );
    expect(
      evaluateTikNetEntitlement(_info(isBlocked: true), now: now).block,
      TikNetEntitlementBlock.inactive,
    );
    expect(
      evaluateTikNetEntitlement(_info(status: 'suspended'), now: now).block,
      TikNetEntitlementBlock.inactive,
    );
  });

  test('blocks when no subscription', () {
    final e = evaluateTikNetEntitlement(_info(hasSubscription: false), now: now);
    expect(e.block, TikNetEntitlementBlock.noSubscription);
    expect(e.blocksCatalog, isTrue);
  });

  test('parses is_active / is_blocked / status from json', () {
    final info = TikNetUserInfo.fromJson({
      'username': 'a',
      'has_subscription': true,
      'is_active': false,
      'is_blocked': true,
      'status': 'banned',
      'traffic_used_bytes': 5,
      'traffic_limit_bytes': 10,
    });
    expect(info.isActive, isFalse);
    expect(info.isBlocked, isTrue);
    expect(info.status, 'banned');
    expect(evaluateTikNetEntitlement(info, now: now).block, TikNetEntitlementBlock.inactive);
  });

  test('blocks catalog and connect together for every block reason', () {
    for (final info in [
      _info(expireDate: DateTime(2026, 7, 1)),
      _info(expireDate: DateTime(2026, 8, 30), trafficUsedBytes: 10, trafficLimitBytes: 10),
      _info(isActive: false),
      _info(hasSubscription: false),
    ]) {
      final e = evaluateTikNetEntitlement(info, now: now);
      expect(e.allowed, isFalse);
      expect(e.blocksCatalog, isTrue);
      expect(e.blocksConnect, isTrue);
    }
  });

  test('reads active/banned aliases from json', () {
    final info = TikNetUserInfo.fromJson({
      'username': 'a',
      'has_subscription': true,
      'active': false,
      'banned': true,
    });
    expect(info.isActive, isFalse);
    expect(info.isBlocked, isTrue);
  });
}
