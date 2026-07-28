import 'package:flutter/material.dart';
import 'package:hiddify/features/tiknet/login/tiknet_login_page.dart';

/// Login entry — open the form immediately (no brand splash delay).
class TikNetSplashScreen extends StatelessWidget {
  const TikNetSplashScreen({super.key, this.duration = Duration.zero});

  /// Kept for call-site compatibility; unused (splash delay removed).
  final Duration duration;

  @override
  Widget build(BuildContext context) => const TikNetLoginPage();
}
