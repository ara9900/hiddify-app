import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/tiknet_theme.dart';
import 'package:hiddify/features/tiknet/login/tiknet_login_page.dart';

/// Shows a simple first frame (avoids black screen), then TikNetLoginPage.
/// If login page throws, user at least saw something.
class TikNetLoginWrapper extends StatefulWidget {
  const TikNetLoginWrapper({super.key});

  @override
  State<TikNetLoginWrapper> createState() => _TikNetLoginWrapperState();
}

class _TikNetLoginWrapperState extends State<TikNetLoginWrapper> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        backgroundColor: TikNetColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('TikNet', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: TikNetColors.onBackground)),
              const SizedBox(height: 16),
              const CircularProgressIndicator(color: TikNetColors.primary),
              const SizedBox(height: 16),
              Text('در حال بارگذاری…', style: TextStyle(color: TikNetColors.onSurfaceVariant, fontSize: 14)),
            ],
          ),
        ),
      );
    }
    return const TikNetLoginPage();
  }
}
