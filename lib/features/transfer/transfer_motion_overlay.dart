import 'dart:math' as math;

import 'package:flutter/material.dart';

enum TransferVisualDirection { sending, receiving }

enum TransferVisualStyle { packets, cards, pulse, orbit }

class TransferMotionOverlay extends StatefulWidget {
  final String peer;
  final TransferVisualDirection direction;
  final int itemCount;

  const TransferMotionOverlay({
    super.key,
    required this.peer,
    required this.direction,
    required this.itemCount,
  });

  @override
  State<TransferMotionOverlay> createState() => _TransferMotionOverlayState();
}

class _TransferMotionOverlayState extends State<TransferMotionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final TransferVisualStyle _style;

  @override
  void initState() {
    super.initState();
    _style = TransferVisualStyle.values[
      math.Random.secure().nextInt(TransferVisualStyle.values.length)
    ];
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _title => widget.direction == TransferVisualDirection.sending
      ? 'در حال ارسال'
      : 'در حال دریافت';

  String get _subtitle => widget.direction == TransferVisualDirection.sending
      ? '${widget.itemCount} مورد به ${widget.peer}'
      : '${widget.itemCount} مورد از ${widget.peer}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return IgnorePointer(
      child: ColoredBox(
        color: cs.scrim.withValues(alpha: .34),
        child: Center(
          child: Container(
            width: math.min(MediaQuery.sizeOf(context).width - 30, 430),
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(34),
              boxShadow: [
                BoxShadow(
                  blurRadius: 32,
                  offset: const Offset(0, 14),
                  color: Colors.black.withValues(alpha: .16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 150,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => CustomPaint(
                      painter: _TransferPainter(
                        progress: _controller.value,
                        style: _style,
                        direction: widget.direction,
                        primary: cs.primary,
                        secondary: cs.tertiary,
                        surface: cs.surfaceContainerHighest,
                        onSurface: cs.onSurface,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: const LinearProgressIndicator(minHeight: 6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TransferPainter extends CustomPainter {
  final double progress;
  final TransferVisualStyle style;
  final TransferVisualDirection direction;
  final Color primary;
  final Color secondary;
  final Color surface;
  final Color onSurface;

  const _TransferPainter({
    required this.progress,
    required this.style,
    required this.direction,
    required this.primary,
    required this.secondary,
    required this.surface,
    required this.onSurface,
  });

  double _x(double t, double left, double right) {
    final p = direction == TransferVisualDirection.sending ? t : 1 - t;
    return left + ((right - left) * p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = 58.0;
    final right = size.width - 58;
    final centerY = size.height / 2;

    final phonePaint = Paint()..color = surface;
    final borderPaint = Paint()
      ..color = onSurface.withValues(alpha: .18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final x in [left, right]) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, centerY),
          width: 58,
          height: 104,
        ),
        const Radius.circular(17),
      );
      canvas.drawRRect(rect, phonePaint);
      canvas.drawRRect(rect, borderPaint);
      canvas.drawCircle(
        Offset(x, centerY + 36),
        3,
        Paint()..color = onSurface.withValues(alpha: .34),
      );
    }

    switch (style) {
      case TransferVisualStyle.packets:
        _paintPackets(canvas, size, left, right, centerY);
      case TransferVisualStyle.cards:
        _paintCards(canvas, size, left, right, centerY);
      case TransferVisualStyle.pulse:
        _paintPulse(canvas, size, left, right, centerY);
      case TransferVisualStyle.orbit:
        _paintOrbit(canvas, size, left, right, centerY);
    }
  }

  void _paintPackets(
    Canvas canvas,
    Size size,
    double left,
    double right,
    double y,
  ) {
    for (var i = 0; i < 5; i++) {
      final t = (progress + i / 5) % 1;
      final x = _x(t, left + 34, right - 34);
      final dy = math.sin((t * math.pi * 2) + i) * 10;
      canvas.drawCircle(
        Offset(x, y + dy),
        5 + (i % 2) * 2,
        Paint()..color = i.isEven ? primary : secondary,
      );
    }
  }

  void _paintCards(
    Canvas canvas,
    Size size,
    double left,
    double right,
    double y,
  ) {
    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1;
      final x = _x(t, left + 36, right - 36);
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, y + math.sin(t * math.pi * 2) * 8),
          width: 30,
          height: 38,
        ),
        const Radius.circular(8),
      );
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((t - .5) * .25);
      canvas.translate(-x, -y);
      canvas.drawRRect(
        rect,
        Paint()..color = i.isEven ? primary : secondary,
      );
      canvas.restore();
    }
  }

  void _paintPulse(
    Canvas canvas,
    Size size,
    double left,
    double right,
    double y,
  ) {
    final line = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = primary.withValues(alpha: .28);
    canvas.drawLine(
      Offset(left + 35, y),
      Offset(right - 35, y),
      line,
    );

    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1;
      final x = _x(t, left + 35, right - 35);
      final r = 8 + 10 * (1 - ((t - .5).abs() * 2));
      canvas.drawCircle(
        Offset(x, y),
        r.clamp(6, 18).toDouble(),
        Paint()..color = secondary.withValues(alpha: .20),
      );
      canvas.drawCircle(
        Offset(x, y),
        5,
        Paint()..color = secondary,
      );
    }
  }

  void _paintOrbit(
    Canvas canvas,
    Size size,
    double left,
    double right,
    double y,
  ) {
    final mid = Offset(size.width / 2, y);
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = onSurface.withValues(alpha: .14);
    canvas.drawOval(
      Rect.fromCenter(center: mid, width: size.width * .42, height: 74),
      orbitPaint,
    );

    for (var i = 0; i < 4; i++) {
      final a = ((progress + i / 4) * math.pi * 2) *
          (direction == TransferVisualDirection.sending ? 1 : -1);
      final p = Offset(
        mid.dx + math.cos(a) * size.width * .21,
        mid.dy + math.sin(a) * 37,
      );
      canvas.drawCircle(
        p,
        6,
        Paint()..color = i.isEven ? primary : secondary,
      );
    }

    final arrowX = _x(progress, left + 34, right - 34);
    canvas.drawCircle(
      Offset(arrowX, y),
      7,
      Paint()..color = primary,
    );
  }

  @override
  bool shouldRepaint(covariant _TransferPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.style != style ||
        oldDelegate.direction != direction;
  }
}
