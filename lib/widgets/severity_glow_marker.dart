library;

import 'package:flutter/material.dart';

import '../utils/severity_score.dart';

class SeverityGlowMarker extends StatefulWidget {
  const SeverityGlowMarker({
    super.key,
    required this.severity01,
    this.baseSize = 18,
    this.pulse = true,
    this.showPinIcon = true,
  });

  final double severity01;
  final double baseSize;
  final bool pulse;
  final bool showPinIcon;

  @override
  State<SeverityGlowMarker> createState() => _SeverityGlowMarkerState();
}

class _SeverityGlowMarkerState extends State<SeverityGlowMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _t = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    if (widget.pulse) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant SeverityGlowMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulse != widget.pulse) {
      if (widget.pulse) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double s = widget.severity01.clamp(0.0, 1.0);
    final Color c = severityColor(s);
    final double outerR = glowRadiusPx(s);
    final double a = glowAlpha(s);

    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final double pulseMul = widget.pulse ? (0.92 + 0.16 * _t.value) : 1.0;
        final double pulseAlpha = widget.pulse ? (0.85 + 0.15 * _t.value) : 1.0;

        final double core = widget.baseSize;
        final double halo1 = outerR * pulseMul;
        final double halo2 = (outerR * 0.68) * (pulseMul * 0.98);

        return SizedBox(
          width: halo1 * 2,
          height: halo1 * 2,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // Soft outer glow
              Container(
                width: halo1 * 2,
                height: halo1 * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: c.withValues(alpha: a * pulseAlpha),
                      blurRadius: halo1,
                      spreadRadius: halo1 * 0.12,
                    ),
                  ],
                ),
              ),
              // Inner glow
              Container(
                width: halo2 * 2,
                height: halo2 * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: c.withValues(alpha: (a + 0.12).clamp(0.0, 0.65) * pulseAlpha),
                      blurRadius: halo2 * 0.9,
                      spreadRadius: halo2 * 0.08,
                    ),
                  ],
                ),
              ),
              // Core marker
              Container(
                width: core,
                height: core,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: c, width: 3),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: widget.showPinIcon
                    ? Icon(
                        Icons.place,
                        size: core * 0.72,
                        color: c,
                      )
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

