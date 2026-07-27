import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/router/go_router/refresh_listenable.dart';
import 'package:hiddify/features/tiknet/login/tiknet_login_page.dart';

/// TikNet branded splash — cinematic loading before login.
class TikNetSplashScreen extends StatefulWidget {
  const TikNetSplashScreen({super.key, this.duration = const Duration(milliseconds: 4200)});

  final Duration duration;

  @override
  State<TikNetSplashScreen> createState() => _TikNetSplashScreenState();
}

class _TikNetSplashScreenState extends State<TikNetSplashScreen> with TickerProviderStateMixin {
  late bool _showLogin;
  late final AnimationController _master;
  late final AnimationController _pulse;
  late final AnimationController _exit;
  late final Animation<double> _progress;
  late final Animation<double> _fadeOut;

  static const _bg = Color(0xFF020617);
  static const _cyan = Color(0xFF38BDF8);
  static const _blue = Color(0xFF3B82F6);

  @override
  void initState() {
    super.initState();
    _showLogin = pendingTikNetLoginLink != null && pendingTikNetLoginLink!.isNotEmpty;

    _master = AnimationController(vsync: this, duration: widget.duration);
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);
    _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

    _progress = CurvedAnimation(parent: _master, curve: const Interval(0.0, 0.88, curve: Curves.easeInOutCubic));
    _fadeOut = CurvedAnimation(parent: _exit, curve: Curves.easeInOut);

    if (_showLogin) {
      _restoreSystemUi();
      return;
    }

    _enterImmersive();
    _master.forward().whenComplete(() async {
      if (!mounted) return;
      await _exit.forward();
      if (!mounted) return;
      _restoreSystemUi();
      setState(() => _showLogin = true);
    });
  }

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  void _restoreSystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
  }

  @override
  void dispose() {
    _master.dispose();
    _pulse.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showLogin) return const TikNetLoginPage();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: AnimatedBuilder(
          animation: Listenable.merge([_master, _pulse, _exit]),
          builder: (context, _) {
            final pulse = 0.97 + (_pulse.value * 0.03);
            final glow = 0.35 + (_pulse.value * 0.45);
            final progress = _progress.value;
            final fade = 1.0 - _fadeOut.value;

            return Opacity(
              opacity: fade,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Base art
                  Transform.scale(
                    scale: pulse,
                    child: Image.asset(
                      'assets/images/tiknet_splash.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),

                  // Soft vignette so status/nav areas stay cinematic
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x66020617),
                          Color(0x00020617),
                          Color(0x00020617),
                          Color(0x99020617),
                        ],
                        stops: [0.0, 0.18, 0.72, 1.0],
                      ),
                    ),
                  ),

                  // Energy particles + scan beam
                  CustomPaint(
                    painter: _SplashFxPainter(
                      t: _master.value,
                      pulse: _pulse.value,
                      color: _cyan,
                    ),
                  ),

                  // Center glow pulse over the shield
                  IgnorePointer(
                    child: Align(
                      alignment: const Alignment(0, -0.12),
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _blue.withValues(alpha: 0.18 * glow),
                              blurRadius: 80,
                              spreadRadius: 24,
                            ),
                            BoxShadow(
                              color: _cyan.withValues(alpha: 0.12 * glow),
                              blurRadius: 40,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Animated loading strip (covers baked-in bar)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 0, 28, 22),
                        child: _LoadingStrip(progress: progress, accent: _cyan),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LoadingStrip extends StatelessWidget {
  const _LoadingStrip({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).clamp(0, 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.verified_rounded, size: 16, color: accent.withValues(alpha: 0.95)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'اتصال در بهترین مسیر...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            Text(
              '$pct%',
              style: TextStyle(
                color: accent.withValues(alpha: 0.95),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 8,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Colors.white.withValues(alpha: 0.08)),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.02, 1.0),
                  alignment: AlignmentDirectional.centerStart,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0x8C38BDF8),
                          Color(0xFF38BDF8),
                          Color(0xFF60A5FA),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.65),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
                // Moving highlight on the fill
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.02, 1.0),
                  alignment: AlignmentDirectional.centerStart,
                  child: Align(
                    alignment: AlignmentDirectional((progress * 2 - 1).clamp(-1.0, 1.0), 0),
                    child: Container(
                      width: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.55),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SplashFxPainter extends CustomPainter {
  _SplashFxPainter({required this.t, required this.pulse, required this.color});

  final double t;
  final double pulse;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(42);
    final paint = Paint()..style = PaintingStyle.fill;

    // Floating particles
    for (var i = 0; i < 28; i++) {
      final seedX = rnd.nextDouble();
      final seedY = rnd.nextDouble();
      final speed = 0.15 + rnd.nextDouble() * 0.35;
      final y = (seedY + t * speed) % 1.0;
      final x = seedX + math.sin((t + seedY) * math.pi * 2) * 0.02;
      final r = 0.8 + rnd.nextDouble() * 1.8;
      final alpha = (0.15 + rnd.nextDouble() * 0.45) * (0.55 + pulse * 0.45);
      paint.color = color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x * size.width, y * size.height), r, paint);
    }

    // Vertical energy beam
    final beamX = size.width * 0.5;
    final beamPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(beamX, 0),
        Offset(beamX, size.height),
        [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.10 + pulse * 0.08),
          color.withValues(alpha: 0.0),
        ],
        const [0.05, 0.45, 0.95],
      );
    canvas.drawRect(Rect.fromCenter(center: Offset(beamX, size.height * 0.42), width: 10, height: size.height * 0.7), beamPaint);

    // Horizontal scan line
    final scanY = size.height * (0.18 + (t * 0.64) % 0.64);
    final scanPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, scanY - 18),
        Offset(0, scanY + 18),
        [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.18),
          color.withValues(alpha: 0.0),
        ],
      );
    canvas.drawRect(Rect.fromLTWH(0, scanY - 18, size.width, 36), scanPaint);
  }

  @override
  bool shouldRepaint(covariant _SplashFxPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.pulse != pulse || oldDelegate.color != color;
}
