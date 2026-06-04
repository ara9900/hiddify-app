import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
/// Branded loading state for TikNet (avoids empty gray screens on slow work).
class TikNetLoadingView extends StatefulWidget {
  const TikNetLoadingView({
    super.key,
    required this.message,
    this.subtitle,
    this.showListSkeleton = false,
    this.skeletonRows = 6,
  });

  final String message;
  final String? subtitle;
  final bool showListSkeleton;
  final int skeletonRows;

  @override
  State<TikNetLoadingView> createState() => _TikNetLoadingViewState();
}

class _TikNetLoadingViewState extends State<TikNetLoadingView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: TikNetColors.background,
      child: Column(
        children: [
          const Gap(32),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.rotate(
                angle: _controller.value * 2 * math.pi,
                child: child,
              );
            },
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    TikNetColors.primary,
                    TikNetColors.primary.withValues(alpha: 0.15),
                    TikNetColors.connected.withValues(alpha: 0.5),
                    TikNetColors.primary,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: DecoratedBox(
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: TikNetColors.surface),
                  child: Icon(Icons.shield_rounded, color: TikNetColors.primary.withValues(alpha: 0.9), size: 26),
                ),
              ),
            ),
          ),
          const Gap(20),
          Text(
            widget.message,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          if (widget.subtitle != null) ...[
            const Gap(8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                widget.subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(color: TikNetColors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          if (widget.showListSkeleton) ...[
            const Gap(28),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.skeletonRows,
                separatorBuilder: (_, _) => const Gap(10),
                itemBuilder: (_, index) => _SkeletonRow(delay: index * 0.08),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}

class _SkeletonRow extends StatefulWidget {
  const _SkeletonRow({required this.delay});

  final double delay;

  @override
  State<_SkeletonRow> createState() => _SkeletonRowState();
}

class _SkeletonRowState extends State<_SkeletonRow> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    Future<void>.delayed(Duration(milliseconds: (widget.delay * 400).round()), () {
      if (mounted) _pulse.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = _pulse.value;
        return Opacity(
          opacity: 0.35 + t * 0.45,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: TikNetColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: TikNetColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: TikNetColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const Gap(14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 12, width: 140, decoration: BoxDecoration(color: TikNetColors.surfaceVariant, borderRadius: BorderRadius.circular(6))),
                      const Gap(8),
                      Container(height: 10, width: 90, decoration: BoxDecoration(color: TikNetColors.surfaceVariant.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(6))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Loading tailored for per-app proxy (many installed apps).
class TikNetPerAppProxyLoadingView extends StatelessWidget {
  const TikNetPerAppProxyLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const TikNetLoadingView(
      message: 'در حال بارگذاری اپ‌ها',
      subtitle: 'لیست برنامه‌های نصب‌شده روی گوشی در حال آماده‌سازی است…',
      showListSkeleton: true,
      skeletonRows: 8,
    );
  }
}

class TikNetEmptyHint extends StatelessWidget {
  const TikNetEmptyHint({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: TikNetColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: TikNetColors.primary),
            ),
            const Gap(20),
            Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const Gap(10),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(color: TikNetColors.onSurfaceVariant, height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const Gap(24), action!],
          ],
        ),
      ),
    );
  }
}
