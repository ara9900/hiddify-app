import 'package:circle_flags/circle_flags.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';

/// Circular country flag for TikNet server list (falls back to globe icon).
class TikNetCountryFlag extends StatelessWidget {
  const TikNetCountryFlag({
    super.key,
    this.countryCode,
    this.size = 40,
    this.personal = false,
  });

  final String? countryCode;
  final double size;
  final bool personal;

  @override
  Widget build(BuildContext context) {
    final code = (countryCode ?? '').trim().toUpperCase();
    if (personal || code.isEmpty) {
      return _iconBadge(Icons.vpn_key_rounded, TikNetColors.primary);
    }
    final flagCode = code == 'IR' ? 'ir' : code.toLowerCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: TikNetColors.border, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: CircleFlag(
        flagCode,
        size: size,
      ),
    );
  }

  Widget _iconBadge(IconData icon, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, color: color, size: size * 0.48),
    );
  }
}
