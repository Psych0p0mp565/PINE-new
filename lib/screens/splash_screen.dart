// Splash/loading screen: pineapple + magnifying glass logo, PINE-A-PIC, tagline, loading bar.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Taglines for the splash screen (first is primary; others available for reuse).
const List<String> kSplashTaglines = <String>[
  'Snap. Detect. Protect.',
  'Take a pic, save your crop.',
  'Pineapple pest detection at your fingertips.',
  'Spot mealybugs in a snap.',
];

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const _PineappleMagnifierLogo(),
                const SizedBox(height: 20),
                const Text(
                  'PINYA-PIC',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  kSplashTaglines.first,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textMedium,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 32),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: double.infinity,
                    height: 6,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryGreen,
                      ),
                      minHeight: 6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stylized pineapple with magnifying glass overlay.
class _PineappleMagnifierLogo extends StatelessWidget {
  const _PineappleMagnifierLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: CustomPaint(
        painter: _PineappleMagnifierPainter(),
      ),
    );
  }
}

class _PineappleMagnifierPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double cx = w / 2;
    final double bodyTop = h * 0.28;
    final double bodyBottom = h * 0.92;
    final double bodyHeight = bodyBottom - bodyTop;

    // Pineapple body (rounded yellow with hex hint)
    final RRect bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, bodyTop, w * 0.76, bodyHeight),
      const Radius.circular(20),
    );
    final Paint bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          Color(0xFFFFE082),
          Color(0xFFFFD54F),
          Color(0xFFFFCA28),
        ],
      ).createShader(bodyRect.outerRect);
    canvas.drawRRect(bodyRect, bodyPaint);

    // Hexagon pattern hint (simplified: small circles)
    final Paint hexPaint = Paint()
      ..color = const Color(0xFFE0A000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const double hexStep = 14;
    for (double y = bodyTop + 12; y < bodyBottom - 8; y += hexStep * 0.86) {
      for (double x = w * 0.18; x < w * 0.82; x += hexStep) {
        final double dx = (y - bodyTop).floor() ~/ (hexStep * 0.86) % 2 == 0
            ? 0
            : hexStep / 2;
        if (bodyRect.outerRect.contains(Offset(x + dx, y))) {
          canvas.drawCircle(Offset(x + dx, y), 2, hexPaint);
        }
      }
    }

    // Crown (green leaves)
    final Paint crownPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          Color(0xFF2E7D32),
          Color(0xFF1B5E20),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, bodyTop + 10));
    final Path crownPath = Path();
    crownPath.moveTo(cx - 28, bodyTop + 8);
    crownPath.lineTo(cx - 14, 4);
    crownPath.lineTo(cx, bodyTop);
    crownPath.lineTo(cx + 14, 4);
    crownPath.lineTo(cx + 28, bodyTop + 8);
    crownPath.lineTo(cx + 18, bodyTop + 6);
    crownPath.lineTo(cx, 14);
    crownPath.lineTo(cx - 18, bodyTop + 6);
    crownPath.close();
    canvas.drawPath(crownPath, crownPaint);
    final Paint crownStroke = Paint()
      ..color = const Color(0xFF1B5E20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(crownPath, crownStroke);

    // Magnifying glass lens (circle, slightly overlapping body)
    final double lensCenterX = cx + 18;
    final double lensCenterY = bodyTop + bodyHeight * 0.35;
    const double lensRadius = 26;
    final Paint lensFramePaint = Paint()
      ..color = const Color(0xFF9E9E9E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(
        Offset(lensCenterX, lensCenterY), lensRadius, lensFramePaint);
    final Paint lensFillPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(lensCenterX, lensCenterY), lensRadius - 2, lensFillPaint);

    // Magnifying glass handle
    const double handleAngle = -math.pi / 4;
    const double handleLength = 32;
    final double handleEndX =
        lensCenterX + math.cos(handleAngle) * (lensRadius + handleLength);
    final double handleEndY =
        lensCenterY + math.sin(handleAngle) * (lensRadius + handleLength);
    final Paint handlePaint = Paint()
      ..color = const Color(0xFF757575)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(
        lensCenterX + math.cos(handleAngle) * lensRadius,
        lensCenterY + math.sin(handleAngle) * lensRadius,
      ),
      Offset(handleEndX, handleEndY),
      handlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
