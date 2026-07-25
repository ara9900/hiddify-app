/// Reward amount from GET /api/customer/referral.
class TikNetReferralRewardSpec {
  const TikNetReferralRewardSpec({
    required this.type,
    required this.amount,
  });

  final String type;
  final num amount;

  factory TikNetReferralRewardSpec.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const TikNetReferralRewardSpec(type: 'traffic_gb', amount: 0);
    }
    return TikNetReferralRewardSpec(
      type: (json['type'] as String?) ?? 'traffic_gb',
      amount: (json['amount'] as num?) ?? 0,
    );
  }

  String get labelFa {
    final n = amount % 1 == 0 ? amount.toInt().toString() : amount.toString();
    switch (type) {
      case 'days':
        return '$n روز';
      case 'traffic_gb':
      default:
        return '$n گیگ';
    }
  }
}

/// Stats from GET /api/customer/referral.
class TikNetReferralStats {
  const TikNetReferralStats({
    required this.invitedCount,
    required this.rewardedCount,
    required this.pendingCount,
  });

  final int invitedCount;
  final int rewardedCount;
  final int pendingCount;

  factory TikNetReferralStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const TikNetReferralStats(invitedCount: 0, rewardedCount: 0, pendingCount: 0);
    }
    return TikNetReferralStats(
      invitedCount: (json['invited_count'] as num?)?.toInt() ?? 0,
      rewardedCount: (json['rewarded_count'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pending_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Response from GET /api/customer/referral.
class TikNetReferralInfo {
  const TikNetReferralInfo({
    required this.referralCode,
    this.shareUrl,
    this.shareText,
    required this.canAttachReferrer,
    this.attachedReferrerCode,
    required this.stats,
    required this.referrerReward,
    required this.inviteeReward,
  });

  final String referralCode;
  final String? shareUrl;
  final String? shareText;
  final bool canAttachReferrer;
  final String? attachedReferrerCode;
  final TikNetReferralStats stats;
  final TikNetReferralRewardSpec referrerReward;
  final TikNetReferralRewardSpec inviteeReward;

  factory TikNetReferralInfo.fromJson(Map<String, dynamic> json) {
    final rewards = json['rewards'];
    final rewardsMap = rewards is Map ? Map<String, dynamic>.from(rewards) : <String, dynamic>{};
    return TikNetReferralInfo(
      referralCode: (json['referral_code'] as String?)?.trim() ?? '',
      shareUrl: (json['share_url'] as String?)?.trim(),
      shareText: (json['share_text'] as String?)?.trim(),
      canAttachReferrer: json['can_attach_referrer'] as bool? ?? false,
      attachedReferrerCode: (json['attached_referrer_code'] as String?)?.trim(),
      stats: TikNetReferralStats.fromJson(
        json['stats'] is Map ? Map<String, dynamic>.from(json['stats'] as Map) : null,
      ),
      referrerReward: TikNetReferralRewardSpec.fromJson(
        rewardsMap['referrer_on_first_purchase'] is Map
            ? Map<String, dynamic>.from(rewardsMap['referrer_on_first_purchase'] as Map)
            : null,
      ),
      inviteeReward: TikNetReferralRewardSpec.fromJson(
        rewardsMap['invitee_on_first_purchase'] is Map
            ? Map<String, dynamic>.from(rewardsMap['invitee_on_first_purchase'] as Map)
            : null,
      ),
    );
  }
}

/// Response from POST /api/customer/referral/attach.
class TikNetReferralAttachResult {
  const TikNetReferralAttachResult({
    required this.ok,
    this.attachedReferrerCode,
  });

  final bool ok;
  final String? attachedReferrerCode;

  factory TikNetReferralAttachResult.fromJson(Map<String, dynamic> json) {
    return TikNetReferralAttachResult(
      ok: json['ok'] as bool? ?? true,
      attachedReferrerCode: (json['attached_referrer_code'] as String?)?.trim(),
    );
  }
}
