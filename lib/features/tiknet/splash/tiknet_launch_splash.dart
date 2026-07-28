import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddify/utils/shamsi_date_format.dart';

/// True once the cold-start launch splash has finished (or was skipped).
bool tikNetLaunchSplashDone = false;

/// Premium cold-start splash: aurora backdrop, orbiting energy ring, animated
/// brand mark and a shimmering progress loader.
///
/// Purely an overlay — the app boots and routes underneath, so this never gates
/// startup work. It removes itself after [duration] plus a short exit fade.
class TikNetLaunchSplash extends StatefulWidget {
  const TikNetLaunchSplash({
    super.key,
    required this.onFinished,
    this.duration = const Duration(milliseconds: 2100),
  });

  final VoidCallback onFinished;
  final Duration duration;

  @override
  State<TikNetLaunchSplash> createState() => _TikNetLaunchSplashState();
}

class _TikNetLaunchSplashState extends State<TikNetLaunchSplash> with TickerProviderStateMixin {
  late final AnimationController _loop;
  late final AnimationController _progress;
  late final AnimationController _exit;

  late final Animation<double> _fill;
  late final Animation<double> _markIn;
  late final Animation<double> _wordIn;
  late final Animation<double> _fade;
  late final Animation<double> _zoom;

  static const _deep = Color(0xFF020617);

  static const _hints = <String>[
    'راه‌اندازی هستهٔ امن',
    'برقراری مسیر رمزنگاری‌شده',
    'سنجش سریع‌ترین سرورها',
    'آماده‌سازی اتصال',
  ];

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 7000))..repeat();
    _progress = AnimationController(vsync: this, duration: widget.duration);
    _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));

    _fill = CurvedAnimation(parent: _progress, curve: Curves.easeInOutCubic);
    _markIn = CurvedAnimation(
      parent: _progress,
      curve: const Interval(0, 0.3, curve: Curves.easeOutBack),
    );
    _wordIn = CurvedAnimation(
      parent: _progress,
      curve: const Interval(0.12, 0.45, curve: Curves.easeOutCubic),
    );
    _fade = CurvedAnimation(parent: _exit, curve: Curves.easeOutCubic);
    _zoom = Tween(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _exit, curve: Curves.easeInCubic),
    );

    _progress.forward().whenComplete(() async {
      if (!mounted) return;
      await _exit.forward();
      if (!mounted) return;
      tikNetLaunchSplashDone = true;
      widget.onFinished();
    });
  }

  @override
  void dispose() {
    _loop.dispose();
    _progress.dispose();
    _exit.dispose();
    super.dispose();
  }

  String get _hint {
    final i = (_fill.value * _hints.length).floor().clamp(0, _hints.length - 1);
    return _hints[i];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_loop, _progress, _exit]),
      builder: (context, _) {
        final percent = (_fill.value * 100).round().clamp(0, 100);
        return Opacity(
          opacity: 1 - _fade.value,
          child: Transform.scale(
            scale: _zoom.value,
            // The splash sits above the router, outside any Material ancestor,
            // where Flutter paints its debug double-underline on every Text.
            child: DefaultTextStyle(
              style: const TextStyle(
                decoration: TextDecoration.none,
                fontWeight: FontWeight.w400,
                color: Color(0xFFE2E8F0),
              ),
              child: DecoratedBox(
                decoration: const BoxDecoration(color: _deep),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _AuroraPainter(t: _loop.value),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.scale(
                            scale: 0.7 + 0.3 * _markIn.value,
                            child: Opacity(
                              opacity: _markIn.value.clamp(0, 1),
                              child: SizedBox(
                                width: 168,
                                height: 168,
                                child: CustomPaint(
                                  painter: _MarkPainter(t: _loop.value, pulse: _fill.value),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          Opacity(
                            opacity: _wordIn.value.clamp(0, 1),
                            child: Transform.translate(
                              offset: Offset(0, 14 * (1 - _wordIn.value)),
                              child: _Wordmark(shimmer: _loop.value),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Opacity(
                            opacity: (_wordIn.value * 0.75).clamp(0, 1),
                            child: const Text(
                              'اتصال امن، بدون دردسر',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 13,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 64,
                      child: Column(
                        children: [
                          _ProgressBar(value: _fill.value, shimmer: _loop.value),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                toPersianDigits('$percent٪'),
                                style: const TextStyle(
                                  color: Color(0xFFE2E8F0),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF475569), shape: BoxShape.circle)),
                              const SizedBox(width: 10),
                              Text(
                                _hint,
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Soft drifting aurora blobs + faint star field.
class _AuroraPainter extends CustomPainter {
  _AuroraPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final angle = t * 2 * math.pi;

    void blob(Offset center, double radius, Color color) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.34), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: radius))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
      );
    }

    blob(
      Offset(size.width * (0.24 + 0.06 * math.sin(angle)), size.height * (0.24 + 0.04 * math.cos(angle))),
      size.width * 0.55,
      _TikNetSplashPalette.indigo,
    );
    blob(
      Offset(size.width * (0.8 + 0.05 * math.cos(angle * 0.8)), size.height * (0.68 + 0.05 * math.sin(angle * 0.8))),
      size.width * 0.5,
      _TikNetSplashPalette.violet,
    );
    blob(
      Offset(size.width * 0.5, size.height * (0.92 + 0.03 * math.sin(angle * 1.2))),
      size.width * 0.45,
      _TikNetSplashPalette.cyan,
    );

    // Star field — deterministic so it doesn't jitter between frames.
    final rnd = math.Random(7);
    final star = Paint()..color = Colors.white;
    for (var i = 0; i < 46; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      final phase = rnd.nextDouble() * 2 * math.pi;
      final twinkle = 0.25 + 0.55 * (0.5 + 0.5 * math.sin(angle * 2 + phase));
      canvas.drawCircle(Offset(dx, dy), rnd.nextDouble() * 1.1 + 0.4, star..color = Colors.white.withValues(alpha: twinkle * 0.5));
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}

/// Orbiting rings around a gradient signal glyph.
class _MarkPainter extends CustomPainter {
  _MarkPainter({required this.t, required this.pulse});

  final double t;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final angle = t * 2 * math.pi;
    final r = size.width / 2;

    // Static guide rings.
    for (final f in const [1.0, 0.82]) {
      canvas.drawCircle(
        center,
        r * f,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.06),
      );
    }

    // Sweeping arcs (outer clockwise, inner counter-clockwise).
    void sweep(double radius, double start, double extent, double width, Color color) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        extent,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..shader = SweepGradient(
            startAngle: start,
            endAngle: start + extent,
            colors: [color.withValues(alpha: 0), color],
            transform: GradientRotation(start),
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    sweep(r, angle, math.pi * 0.9, 3, _TikNetSplashPalette.cyan);
    sweep(r * 0.82, -angle * 1.35, math.pi * 0.7, 2.5, _TikNetSplashPalette.violet);

    // Orbiting dot on the outer ring.
    final dot = Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle));
    canvas.drawCircle(dot, 4.5, Paint()..color = Colors.white);
    canvas.drawCircle(
      dot,
      11,
      Paint()
        ..color = _TikNetSplashPalette.cyan.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Core disc with breathing glow.
    final breathe = 0.5 + 0.5 * math.sin(angle * 2);
    final coreR = r * 0.6;
    canvas.drawCircle(
      center,
      coreR + 6 + 4 * breathe,
      Paint()
        ..color = _TikNetSplashPalette.indigo.withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawCircle(
      center,
      coreR,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4F46E5), Color(0xFF0EA5E9)],
        ).createShader(Rect.fromCircle(center: center, radius: coreR)),
    );

    // Signal glyph: three arcs growing with load progress + base dot.
    final glyph = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    final base = Offset(center.dx, center.dy + coreR * 0.42);
    for (var i = 0; i < 3; i++) {
      final lit = pulse >= (i + 1) / 4;
      glyph
        ..strokeWidth = 3.4 - i * 0.2
        ..color = Colors.white.withValues(alpha: lit ? 0.95 : 0.28);
      final radius = coreR * (0.34 + i * 0.24);
      canvas.drawArc(
        Rect.fromCircle(center: base, radius: radius),
        math.pi * 1.22,
        math.pi * 0.56,
        false,
        glyph,
      );
    }
    canvas.drawCircle(base, 3.4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.t != t || old.pulse != pulse;
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.shimmer});

  final double shimmer;

  @override
  Widget build(BuildContext context) {
    // Sweep a bright band across the letters.
    final x = shimmer * 3 - 1;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment(x - 0.6, 0),
        end: Alignment(x + 0.6, 0),
        colors: const [
          Color(0xFF93C5FD),
          Colors.white,
          Color(0xFF93C5FD),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(bounds),
      child: const Text(
        'TikNet',
        style: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w800,
          letterSpacing: 3,
          color: Colors.white,
          height: 1.1,
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.shimmer});

  final double value;
  final double shimmer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 196,
        height: 5,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0x1FFFFFFF)),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.02, 1),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _TikNetSplashPalette.indigo,
                        _TikNetSplashPalette.cyan,
                      ],
                    ),
                  ),
                ),
              ),
              // Highlight glint travelling along the bar.
              Align(
                alignment: Alignment(shimmer * 2.4 - 1.2, 0),
                child: Container(
                  width: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.55),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

abstract class _TikNetSplashPalette {
  static const indigo = Color(0xFF6366F1);
  static const cyan = Color(0xFF22D3EE);
  static const violet = Color(0xFFA855F7);
}
