import 'package:flutter/material.dart';
import 'package:hiddify/utils/shamsi_date_format.dart';

/// Small latency / health badge for server rows.
class TikNetPingChip extends StatelessWidget {
  const TikNetPingChip({
    super.key,
    required this.label,
    required this.color,
    this.compact = false,
  });

  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final display = label.contains(RegExp(r'\d'))
        ? label.replaceAllMapped(RegExp(r'\d+'), (m) => toPersianDigits(m.group(0)!))
        : label;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 4 : 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.speed_rounded, size: compact ? 12 : 14, color: color),
          const SizedBox(width: 4),
          Text(
            display,
            style: TextStyle(
              color: color,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
