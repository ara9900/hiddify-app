import 'package:flutter/material.dart';
import 'package:hiddify/features/tiknet/login/tiknet_login_page.dart';

/// TikNet branded splash — shown for [duration] before login.
class TikNetSplashScreen extends StatefulWidget {
  const TikNetSplashScreen({super.key, this.duration = const Duration(seconds: 3)});

  final Duration duration;

  @override
  State<TikNetSplashScreen> createState() => _TikNetSplashScreenState();
}

class _TikNetSplashScreenState extends State<TikNetSplashScreen> {
  bool _showLogin = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.duration, () {
      if (mounted) setState(() => _showLogin = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showLogin) return const TikNetLoginPage();

    return Scaffold(
      body: SizedBox.expand(
        child: Image.asset(
          'assets/images/tiknet_splash.png',
          fit: BoxFit.cover,
          alignment: Alignment.center,
        ),
      ),
    );
  }
}
