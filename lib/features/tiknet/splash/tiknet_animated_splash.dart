import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

/// Process-level flag: true after the cold-start splash finishes (or is skipped).
bool tikNetStartupSplashCompleted = false;

/// True while the app-root splash is covering the UI.
bool tikNetStartupSplashVisible = false;

/// Cinematic TikNet loader — pure motion, no static splash art.
class TikNetAnimatedSplash extends StatefulWidget {
  const TikNetAnimatedSplash({
    super.key,
    this.duration = const Duration(milliseconds: 3600),
    this.onFinished,
  });

  final Duration duration;
  final VoidCallback? onFinished;

  @override
  State<TikNetAnimatedSplash> createState() => _TikNetAnimatedSplashState();
}

class _TikNetAnimatedSplashState extends State<TikNetAnimatedSplash> with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _spinFast;
  late final AnimationController _pulse;
  late final AnimationController _progress;
  late final AnimationController _exit;

  late final Animation<double> _fadeOut;
  late final Animation<double> _heroIn;
  late final Animation<double> _fill;

  static const _bg = Color(0xFF020617);
  static const _cyan = Color(0xFF22D3EE);
  static const _blue = Color(0xFF3B82F6);
  static const _violet = Color(0xFF8B5CF6);
  static const _mint = Color(0xFF34D399);

  static const _hints = <String>[
    'در حال آماده‌سازی هسته امن…',
    'انتخاب بهترین مسیر…',
    'رمزنگاری اتصال…',
    'تقریباً آماده‌ایم…',
  ];

  @override
  void initState() {
    super.initState();
    tikNetStartupSplashVisible = true;

    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 9000))..repeat();
    _spinFast = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
    _progress = AnimationController(vsync: this, duration: widget.duration);
    _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));

    _fadeOut = CurvedAnimation(parent: _exit, curve: Curves.easeInOutCubic);
    _heroIn = CurvedAnimation(parent: _progress, curve: const Interval(0.0, 0.28, curve: Curves.easeOutBack));
    _fill = CurvedAnimation(parent: _progress, curve: const Interval(0.0, 0.92, curve: Curves.easeInOutCubic));

    _enterImmersive();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb) FlutterNativeSplash.remove();
    });

    _progress.forward().whenComplete(() async {
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
    _spin.dispose();
    _spinFast.dispose();
    _pulse.dispose();
    _progress.dispose();
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Material(
        color: _bg,
        child: AnimatedBuilder(
          animation: Listenable.merge([_spin, _spinFast, _pulse, _progress, _exit]),
          builder: (context, _) {
            final fill = _fill.value.clamp(0.0, 1.0);
            final pct = (fill * 100).round();
            final fade = 1.0 - _fadeOut.value;
            final pulse = _pulse.value;
            final hintIndex = (fill * _hints.length).floor().clamp(0, _hints.length - 1);
            final hero = _heroIn.value.clamp(0.0, 1.0);

            return Opacity(
              opacity: fade,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Aurora wash
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -0.15 + pulse * 0.05),
                        radius: 1.15,
                        colors: [
                          Color.lerp(_blue, _violet, pulse)!.withValues(alpha: 0.28),
                          _bg,
                        ],
                      ),
                    ),
                  ),
                  CustomPaint(
                    painter: _CosmicLoaderPainter(
                      spin: _spin.value,
                      spinFast: _spinFast.value,
                      pulse: pulse,
                      progress: fill,
                      cyan: _cyan,
                      blue: _blue,
                      violet: _violet,
                      mint: _mint,
                    ),
                  ),

                  // Hero cluster
                  Center(
                    child: Transform.translate(
                      offset: Offset(0, -28 * (1 - hero)),
                      child: Transform.scale(
                        scale: 0.78 + hero * 0.22,
                        child: Opacity(
                          opacity: hero,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 210,
                                height: 210,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Outer glow
                                    Transform.scale(
                                      scale: 0.95 + pulse * 0.08,
                                      child: Container(
                                        width: 160,
                                        height: 160,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: _cyan.withValues(alpha: 0.22 + pulse * 0.18),
                                              blurRadius: 48,
                                              spreadRadius: 8,
                                            ),
                                            BoxShadow(
                                              color: _violet.withValues(alpha: 0.12 + pulse * 0.1),
                                              blurRadius: 72,
                                              spreadRadius: 2,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // Core badge
                                    Container(
                                      width: 96,
                                      height: 96,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color.lerp(const Color(0xFF0F172A), _blue, 0.18)!,
                                            const Color(0xFF020617),
                                          ],
                                        ),
                                        border: Border.all(
                                          color: Color.lerp(_cyan, _mint, pulse)!.withValues(alpha: 0.7),
                                          width: 1.6,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.shield_moon_rounded,
                                        size: 46,
                                        color: Color.lerp(_cyan, Colors.white, pulse * 0.35),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              ShaderMask(
                                shaderCallback: (bounds) => LinearGradient(
                                  colors: [
                                    Colors.white,
                                    _cyan,
                                    Colors.white,
                                  ],
                                  stops: [
                                    0.0,
                                    0.45 + pulse * 0.2,
                                    1.0,
                                  ],
                                ).createShader(bounds),
                                child: const Text(
                                  'تیک‌نت',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 40,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.4,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'SECURE  ·  FAST  ·  LIMITLESS',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Bottom progress
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(32, 0, 32, 32 + bottom),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 420),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            child: Text(
                              _hints[hintIndex],
                              key: ValueKey(hintIndex),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _GlowProgressBar(progress: fill, cyan: _cyan, blue: _blue, violet: _violet),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                'در حال بارگذاری',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '$pct٪',
                                style: TextStyle(
                                  color: _cyan,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ],
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

class _GlowProgressBar extends StatelessWidget {
  const _GlowProgressBar({
    required this.progress,
    required this.cyan,
    required this.blue,
    required this.violet,
  });

  final double progress;
  final Color cyan;
  final Color blue;
  final Color violet;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 7,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.white.withValues(alpha: 0.07)),
            FractionallySizedBox(
              widthFactor: progress.clamp(0.03, 1.0),
              alignment: AlignmentDirectional.centerStart,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [violet, blue, cyan]),
                  boxShadow: [
                    BoxShadow(color: cyan.withValues(alpha: 0.55), blurRadius: 12, spreadRadius: 1),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CosmicLoaderPainter extends CustomPainter {
  _CosmicLoaderPainter({
    required this.spin,
    required this.spinFast,
    required this.pulse,
    required this.progress,
    required this.cyan,
    required this.blue,
    required this.violet,
    required this.mint,
  });

  final double spin;
  final double spinFast;
  final double pulse;
  final double progress;
  final Color cyan;
  final Color blue;
  final Color violet;
  final Color mint;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.40);
    final rnd = math.Random(11);

    // Stars
    final star = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < 56; i++) {
      final seed = rnd.nextDouble();
      final a = seed * math.pi * 2 + spin * (0.4 + seed);
      final r = 50.0 + rnd.nextDouble() * math.min(size.width, size.height) * 0.48;
      final twinkle = (math.sin(spinFast * math.pi * 2 + i * 0.7) + 1) / 2;
      star.color = Colors.white.withValues(alpha: 0.05 + twinkle * 0.28);
      canvas.drawCircle(
        center + Offset(math.cos(a) * r, math.sin(a) * r * 0.78),
        0.7 + rnd.nextDouble() * 1.6,
        star,
      );
    }

    void arc(double radius, double width, double start, double sweep, Color color, double alpha) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: alpha);
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, sweep, false, paint);
    }

    final base = 62.0 + pulse * 5;

    // Ghost rings
    arc(base + 6, 1.0, 0, math.pi * 2, blue, 0.10);
    arc(base + 28, 1.0, 0, math.pi * 2, violet, 0.08);

    // Orbiting arcs
    arc(base + 18, 2.4, spin * math.pi * 2, math.pi * 1.25, cyan, 0.65);
    arc(base + 36, 1.8, -spinFast * math.pi * 2, math.pi * 0.9, violet, 0.55);
    arc(base + 52, 1.5, spin * math.pi * 1.7 + 1.2, math.pi * 0.7, mint, 0.42);

    // Progress ring
    arc(
      base + 68,
      4.2,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.04, 1.0),
      cyan,
      0.88,
    );

    // Orbiting diamonds
    for (var i = 0; i < 3; i++) {
      final ang = spinFast * math.pi * 2 + i * (math.pi * 2 / 3);
      final orbit = base + 36.0;
      final p = center + Offset(math.cos(ang) * orbit, math.sin(ang) * orbit);
      final diamond = Paint()
        ..style = PaintingStyle.fill
        ..color = Color.lerp(cyan, mint, i / 3)!.withValues(alpha: 0.85);
      final path = Path()
        ..moveTo(p.dx, p.dy - 4.5)
        ..lineTo(p.dx + 3.2, p.dy)
        ..lineTo(p.dx, p.dy + 4.5)
        ..lineTo(p.dx - 3.2, p.dy)
        ..close();
      canvas.drawPath(path, diamond);
    }

    // Sweep glow
    final sweep = Paint()
      ..shader = ui.Gradient.sweep(
        center,
        [
          Colors.transparent,
          cyan.withValues(alpha: 0.0),
          cyan.withValues(alpha: 0.18),
          violet.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        const [0.0, 0.5, 0.68, 0.82, 1.0],
        TileMode.clamp,
        spin * math.pi * 2,
        spin * math.pi * 2 + math.pi * 2,
      );
    canvas.drawCircle(center, base + 74, sweep);
  }

  @override
  bool shouldRepaint(covariant _CosmicLoaderPainter oldDelegate) =>
      oldDelegate.spin != spin ||
      oldDelegate.spinFast != spinFast ||
      oldDelegate.pulse != pulse ||
      oldDelegate.progress != progress;
}
