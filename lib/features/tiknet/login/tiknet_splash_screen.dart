import 'package:flutter/material.dart';
import 'package:hiddify/core/router/go_router/refresh_listenable.dart';
import 'package:hiddify/features/tiknet/login/tiknet_login_page.dart';
import 'package:hiddify/features/tiknet/splash/tiknet_animated_splash.dart';

/// Login entry. Cold-start brand animation lives in [TikNetAnimatedSplash] (App overlay).
/// This route only shows a short splash when the overlay already finished / was skipped,
/// then opens the login form.
class TikNetSplashScreen extends StatefulWidget {
  const TikNetSplashScreen({super.key, this.duration = const Duration(milliseconds: 600)});

  final Duration duration;

  @override
  State<TikNetSplashScreen> createState() => _TikNetSplashScreenState();
}

class _TikNetSplashScreenState extends State<TikNetSplashScreen> {
  late bool _showLogin;

  @override
  void initState() {
    super.initState();
    // Skip when opening from a login deep link (Telegram bot), or when the
    // app-root cinematic splash already covered branding.
    final deepLink = pendingTikNetLoginLink != null && pendingTikNetLoginLink!.isNotEmpty;
    _showLogin = deepLink || tikNetStartupSplashCompleted || tikNetStartupSplashVisible;
    if (_showLogin) return;
    Future<void>.delayed(widget.duration, () {
      if (mounted) setState(() => _showLogin = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showLogin) return const TikNetLoginPage();

    return const Scaffold(
      backgroundColor: Color(0xFF020617),
      body: SizedBox.expand(
        child: ColoredBox(color: Color(0xFF020617)),
      ),
    );
  }
}
