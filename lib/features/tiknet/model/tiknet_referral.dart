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

/// One milestone tier from panel settings / referral payload.
class TikNetReferralMilestone {
  const TikNetReferralMilestone({
    required this.invitesRequired,
    required this.trafficGb,
    required this.bonusDays,
    this.title,
  });

  final int invitesRequired;
  final num trafficGb;
  final int bonusDays;
  final String? title;

  factory TikNetReferralMilestone.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const TikNetReferralMilestone(invitesRequired: 0, trafficGb: 0, bonusDays: 0);
    }
    return TikNetReferralMilestone(
      invitesRequired: (json['invites_required'] as num?)?.toInt() ??
          (json['target'] as num?)?.toInt() ??
          (json['invites'] as num?)?.toInt() ??
          0,
      trafficGb: (json['traffic_gb'] as num?) ?? (json['traffic'] as num?) ?? 0,
      bonusDays: (json['bonus_days'] as num?)?.toInt() ?? (json['days'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?)?.trim(),
    );
  }

  String get rewardCaptionFa {
    final parts = <String>[];
    if (trafficGb > 0) {
      final n = trafficGb % 1 == 0 ? trafficGb.toInt().toString() : trafficGb.toString();
      parts.add('$n گیگ');
    }
    if (bonusDays > 0) {
      parts.add('$bonusDays روز');
    }
    if (parts.isEmpty) return '';
    return 'جایزه: ${parts.join(' + ')}';
  }
}

/// Progress toward the current milestone.
class TikNetReferralProgress {
  const TikNetReferralProgress({
    required this.rewardedCount,
    required this.currentMilestoneIndex,
    required this.currentTarget,
    this.currentLabel,
    required this.progressRatio,
    this.rewardCaption,
    required this.completedAll,
    this.nextMilestone,
  });

  final int rewardedCount;
  final int currentMilestoneIndex;
  final int currentTarget;
  final String? currentLabel;
  final double progressRatio;
  final String? rewardCaption;
  final bool completedAll;
  final TikNetReferralMilestone? nextMilestone;

  factory TikNetReferralProgress.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const TikNetReferralProgress(
        rewardedCount: 0,
        currentMilestoneIndex: 0,
        currentTarget: 0,
        progressRatio: 0,
        completedAll: false,
      );
    }
    final next = json['next_milestone'];
    final ratio = (json['progress_ratio'] as num?)?.toDouble() ?? 0;
    return TikNetReferralProgress(
      rewardedCount: (json['rewarded_count'] as num?)?.toInt() ?? 0,
      currentMilestoneIndex: (json['current_milestone_index'] as num?)?.toInt() ?? 0,
      currentTarget: (json['current_target'] as num?)?.toInt() ??
          (json['target'] as num?)?.toInt() ??
          (next is Map ? (next['invites_required'] as num?)?.toInt() : null) ??
          0,
      currentLabel: (json['current_label'] as String?)?.trim() ?? (json['label'] as String?)?.trim(),
      progressRatio: ratio.clamp(0.0, 1.0),
      rewardCaption: (json['reward_caption'] as String?)?.trim() ?? (json['prize_caption'] as String?)?.trim(),
      completedAll: json['completed_all'] as bool? ?? false,
      nextMilestone: next is Map
          ? TikNetReferralMilestone.fromJson(Map<String, dynamic>.from(next))
          : null,
    );
  }

  /// Fallback label when panel omits current_label.
  String labelFa({required int rewarded, required int target}) {
    final fromApi = (currentLabel ?? '').trim();
    if (fromApi.isNotEmpty) return fromApi;
    if (target <= 0) return '';
    return '$rewarded از $target';
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
    this.progress,
    this.milestones = const [],
  });

  final String referralCode;
  final String? shareUrl;
  final String? shareText;
  final bool canAttachReferrer;
  final String? attachedReferrerCode;
  final TikNetReferralStats stats;
  final TikNetReferralRewardSpec referrerReward;
  final TikNetReferralRewardSpec inviteeReward;
  final TikNetReferralProgress? progress;
  final List<TikNetReferralMilestone> milestones;

  factory TikNetReferralInfo.fromJson(Map<String, dynamic> json) {
    final rewards = json['rewards'];
    final rewardsMap = rewards is Map ? Map<String, dynamic>.from(rewards) : <String, dynamic>{};
    final milestonesRaw = json['milestones'] ?? json['referral_milestones'] ?? rewardsMap['milestones'];
    final milestones = milestonesRaw is List
        ? milestonesRaw
            .whereType<Map>()
            .map((e) => TikNetReferralMilestone.fromJson(Map<String, dynamic>.from(e)))
            .where((m) => m.invitesRequired > 0)
            .toList()
        : const <TikNetReferralMilestone>[];
    final progressRaw = json['progress'] ?? json['milestone_progress'];
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
      progress: progressRaw is Map
          ? TikNetReferralProgress.fromJson(Map<String, dynamic>.from(progressRaw))
          : null,
      milestones: milestones,
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
