import 'dart:async';
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
  Timer? _collapseTimer;
  bool _compact = false;

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

    _collapseTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _compact = true);
    });
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _compact
          ? _CompactTransferCapsule(
              key: const ValueKey('compact'),
              controller: _controller,
              style: _style,
              title: _title,
              subtitle: _subtitle,
              direction: widget.direction,
            )
          : _BlockingTransferIntro(
              key: const ValueKey('intro'),
              controller: _controller,
              style: _style,
              title: _title,
              subtitle: _subtitle,
              direction: widget.direction,
            ),
    );
  }
}

class _BlockingTransferIntro extends StatelessWidget {
  final Animation<double> controller;
  final TransferVisualStyle style;
  final String title;
  final String subtitle;
  final TransferVisualDirection direction;

  const _BlockingTransferIntro({
    super.key,
    required this.controller,
    required this.style,
    required this.title,
    required this.subtitle,
    required this.direction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        ModalBarrier(
          dismissible: false,
          color: cs.scrim.withValues(alpha: .38),
        ),
        Center(
          child: Material(
            color: Colors.transparent,
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
                    child: _TransferMotion(
                      animation: controller,
                      style: style,
                      direction: direction,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
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
      ],
    );
  }
}

class _CompactTransferCapsule extends StatelessWidget {
  final Animation<double> controller;
  final TransferVisualStyle style;
  final String title;
  final String subtitle;
  final TransferVisualDirection direction;

  const _CompactTransferCapsule({
    super.key,
    required this.controller,
    required this.style,
    required this.title,
    required this.subtitle,
    required this.direction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Material(
              elevation: 10,
              shadowColor: Colors.black.withValues(alpha: .18),
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(26),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      height: 52,
                      child: _TransferMotion(
                        animation: controller,
                        style: style,
                        direction: direction,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: const LinearProgressIndicator(minHeight: 4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      direction == TransferVisualDirection.sending
                          ? Icons.north_east_rounded
                          : Icons.south_west_rounded,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TransferMotion extends StatelessWidget {
  final Animation<double> animation;
  final TransferVisualStyle style;
  final TransferVisualDirection direction;
  final bool compact;

  const _TransferMotion({
    required this.animation,
    required this.style,
    required this.direction,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => CustomPaint(
        painter: _TransferPainter(
          progress: animation.value,
          style: style,
          direction: direction,
          primary: cs.primary,
          secondary: cs.tertiary,
          surface: cs.surfaceContainerHighest,
          onSurface: cs.onSurface,
          compact: compact,
        ),
        child: const SizedBox.expand(),
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
  final bool compact;

  const _TransferPainter({
    required this.progress,
    required this.style,
    required this.direction,
    required this.primary,
    required this.secondary,
    required this.surface,
    required this.onSurface,
    required this.compact,
  });

  double _x(double t, double left, double right) {
    final p = direction == TransferVisualDirection.sending ? t : 1 - t;
    return left + ((right - left) * p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final phoneWidth = compact ? 18.0 : 58.0;
    final phoneHeight = compact ? 34.0 : 104.0;
    final edge = compact ? 12.0 : 58.0;
    final left = edge;
    final right = size.width - edge;
    final centerY = size.height / 2;

    final phonePaint = Paint()..color = surface;
    final borderPaint = Paint()
      ..color = onSurface.withValues(alpha: .18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 1.2 : 2;

    for (final x in [left, right]) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, centerY),
          width: phoneWidth,
          height: phoneHeight,
        ),
        Radius.circular(compact ? 6 : 17),
      );
      canvas.drawRRect(rect, phonePaint);
      canvas.drawRRect(rect, borderPaint);
    }

    switch (style) {
      case TransferVisualStyle.packets:
        _paintPackets(canvas, left, right, centerY);
      case TransferVisualStyle.cards:
        _paintCards(canvas, left, right, centerY);
      case TransferVisualStyle.pulse:
        _paintPulse(canvas, left, right, centerY);
      case TransferVisualStyle.orbit:
        _paintOrbit(canvas, size, left, right, centerY);
    }
  }

  void _paintPackets(Canvas canvas, double left, double right, double y) {
    for (var i = 0; i < (compact ? 3 : 5); i++) {
      final t = (progress + i / (compact ? 3 : 5)) % 1;
      final x = _x(t, left + (compact ? 12 : 34), right - (compact ? 12 : 34));
      final dy = math.sin((t * math.pi * 2) + i) * (compact ? 3 : 10);
      canvas.drawCircle(
        Offset(x, y + dy),
        compact ? 2.5 : 5 + (i % 2) * 2,
        Paint()..color = i.isEven ? primary : secondary,
      );
    }
  }

  void _paintCards(Canvas canvas, double left, double right, double y) {
    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1;
      final x = _x(t, left + (compact ? 12 : 36), right - (compact ? 12 : 36));
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, y + math.sin(t * math.pi * 2) * (compact ? 3 : 8)),
          width: compact ? 8 : 30,
          height: compact ? 10 : 38,
        ),
        Radius.circular(compact ? 2.5 : 8),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = i.isEven ? primary : secondary,
      );
    }
  }

  void _paintPulse(Canvas canvas, double left, double right, double y) {
    canvas.drawLine(
      Offset(left + (compact ? 12 : 35), y),
      Offset(right - (compact ? 12 : 35), y),
      Paint()
        ..strokeWidth = compact ? 1.5 : 3
        ..strokeCap = StrokeCap.round
        ..color = primary.withValues(alpha: .28),
    );

    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1;
      final x = _x(t, left + (compact ? 12 : 35), right - (compact ? 12 : 35));
      canvas.drawCircle(
        Offset(x, y),
        compact ? 2.8 : 5,
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
    final width = compact ? size.width * .36 : size.width * .42;
    final height = compact ? 20.0 : 74.0;
    canvas.drawOval(
      Rect.fromCenter(center: mid, width: width, height: height),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 1.2 : 2
        ..color = onSurface.withValues(alpha: .14),
    );

    for (var i = 0; i < (compact ? 2 : 4); i++) {
      final a = ((progress + i / (compact ? 2 : 4)) * math.pi * 2) *
          (direction == TransferVisualDirection.sending ? 1 : -1);
      final p = Offset(
        mid.dx + math.cos(a) * width / 2,
        mid.dy + math.sin(a) * height / 2,
      );
      canvas.drawCircle(
        p,
        compact ? 2.5 : 6,
        Paint()..color = i.isEven ? primary : secondary,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TransferPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.style != style ||
        oldDelegate.direction != direction ||
        oldDelegate.compact != compact;
  }
}
