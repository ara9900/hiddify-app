import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

/// Process-level flag: true after the cold-start cinematic splash finishes (or is skipped).
bool tikNetStartupSplashCompleted = false;

/// True while the app-root cinematic splash is covering the UI.
bool tikNetStartupSplashVisible = false;

/// Full-screen TikNet splash animation (particles + progress). Used as App overlay on every cold start.
class TikNetAnimatedSplash extends StatefulWidget {
  const TikNetAnimatedSplash({
    super.key,
    this.duration = const Duration(milliseconds: 3200),
    this.onFinished,
  });

  final Duration duration;
  final VoidCallback? onFinished;

  @override
  State<TikNetAnimatedSplash> createState() => _TikNetAnimatedSplashState();
}

class _TikNetAnimatedSplashState extends State<TikNetAnimatedSplash> with TickerProviderStateMixin {
  late final AnimationController _master;
  late final AnimationController _pulse;
  late final AnimationController _exit;
  late final Animation<double> _progress;
  late final Animation<double> _fadeOut;

  static const bg = Color(0xFF020617);
  static const cyan = Color(0xFF38BDF8);
  static const blue = Color(0xFF3B82F6);

  @override
  void initState() {
    super.initState();
    tikNetStartupSplashVisible = true;
    _master = AnimationController(vsync: this, duration: widget.duration);
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(reverse: true);
    _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
    _progress = CurvedAnimation(parent: _master, curve: const Interval(0.0, 0.9, curve: Curves.easeInOutCubic));
    _fadeOut = CurvedAnimation(parent: _exit, curve: Curves.easeInOut);

    _enterImmersive();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb) FlutterNativeSplash.remove();
    });
    _master.forward().whenComplete(() async {
      if (!mounted) return;
      await _exit.forward();
      if (!mounted) return;
      _finish();
    });
  }

  void _finish() {
    tikNetStartupSplashVisible = false;
    tikNetStartupSplashCompleted = true;
    _restoreSystemUi();
    widget.onFinished?.call();
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Material(
        color: bg,
        child: AnimatedBuilder(
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
                  Transform.scale(
                    scale: pulse,
                    child: Image.asset(
                      'assets/images/tiknet_splash.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x88020617),
                          Color(0x00020617),
                          Color(0x00020617),
                          Color(0xAA020617),
                        ],
                        stops: [0.0, 0.16, 0.7, 1.0],
                      ),
                    ),
                  ),
                  CustomPaint(
                    painter: TikNetSplashFxPainter(
                      t: _master.value,
                      pulse: _pulse.value,
                      color: cyan,
                    ),
                  ),
                  IgnorePointer(
                    child: Align(
                      alignment: const Alignment(0, -0.12),
                      child: Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: blue.withValues(alpha: 0.22 * glow),
                              blurRadius: 90,
                              spreadRadius: 28,
                            ),
                            BoxShadow(
                              color: cyan.withValues(alpha: 0.14 * glow),
                              blurRadius: 44,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(28, 0, 28, 28 + MediaQuery.paddingOf(context).bottom),
                      child: TikNetSplashLoadingStrip(progress: progress, accent: cyan),
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

class TikNetSplashLoadingStrip extends StatelessWidget {
  const TikNetSplashLoadingStrip({required this.progress, required this.accent, super.key});

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

class TikNetSplashFxPainter extends CustomPainter {
  TikNetSplashFxPainter({required this.t, required this.pulse, required this.color});

  final double t;
  final double pulse;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(42);
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < 36; i++) {
      final seedX = rnd.nextDouble();
      final seedY = rnd.nextDouble();
      final speed = 0.12 + rnd.nextDouble() * 0.4;
      final y = (seedY + t * speed) % 1.0;
      final x = seedX + math.sin((t + seedY) * math.pi * 2) * 0.025;
      final r = 0.7 + rnd.nextDouble() * 2.2;
      final alpha = (0.12 + rnd.nextDouble() * 0.5) * (0.5 + pulse * 0.5);
      paint.color = color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x * size.width, y * size.height), r, paint);
    }

    final beamX = size.width * 0.5;
    final beamPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(beamX, 0),
        Offset(beamX, size.height),
        [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.12 + pulse * 0.1),
          color.withValues(alpha: 0.0),
        ],
        const [0.05, 0.45, 0.95],
      );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(beamX, size.height * 0.42), width: 12, height: size.height * 0.72),
      beamPaint,
    );

    final scanY = size.height * (0.14 + (t * 0.7) % 0.7);
    final scanPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, scanY - 22),
        Offset(0, scanY + 22),
        [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.22),
          color.withValues(alpha: 0.0),
        ],
      );
    canvas.drawRect(Rect.fromLTWH(0, scanY - 22, size.width, 44), scanPaint);
  }

  @override
  bool shouldRepaint(covariant TikNetSplashFxPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.pulse != pulse || oldDelegate.color != color;
}
