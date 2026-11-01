import 'package:flutter/material.dart';

const tipCarNavy = Color(0xff102a56);
const tipCarOrange = Color(0xfff28c28);
const tipCarGreen = Color(0xff138a50);

class TipCarBrand extends StatelessWidget {
  final bool compact;
  const TipCarBrand({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 38 : 64,
          height: compact ? 38 : 64,
          decoration: BoxDecoration(
            color: const Color(0xfff1f5fb),
            borderRadius: BorderRadius.circular(compact ? 12 : 20),
          ),
          padding: EdgeInsets.all(compact ? 5 : 9),
          child: CustomPaint(painter: _TipCarMarkPainter()),
        ),
        SizedBox(width: compact ? 9 : 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'TIP CAR',
              style: TextStyle(
                color: tipCarNavy,
                fontSize: compact ? 19 : 30,
                fontWeight: FontWeight.w900,
                letterSpacing: compact ? 1.2 : 2,
                height: 1,
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 5),
              const Text(
                'Ride Together, Travel Better',
                style: TextStyle(
                  color: Color(0xff64748b),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .3,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _TipCarMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = tipCarNavy
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .095
      ..strokeCap = StrokeCap.round;
    final route = Path()
      ..moveTo(size.width * .12, size.height * .82)
      ..cubicTo(size.width * .35, size.height * .66, size.width * .16,
          size.height * .38, size.width * .48, size.height * .25)
      ..cubicTo(size.width * .72, size.height * .14, size.width * .65,
          size.height * .58, size.width * .9, size.height * .16);
    canvas.drawPath(route, road);

    final colors = [const Color(0xffff9933), Colors.white, tipCarGreen];
    for (var i = 0; i < colors.length; i++) {
      final paint = Paint()..color = colors[i];
      canvas.drawCircle(
        Offset(size.width * .12, size.height * (.82 - i * .025)),
        size.width * .09,
        paint,
      );
    }
    canvas.drawCircle(
      Offset(size.width * .9, size.height * .16),
      size.width * .105,
      Paint()..color = tipCarOrange,
    );

    final car = Paint()
      ..color = tipCarNavy
      ..style = PaintingStyle.fill;
    final carBody = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * .34, size.height * .61,
          size.width * .48, size.height * .22),
      Radius.circular(size.width * .07),
    );
    canvas.drawRRect(carBody, car);
    final roof = Path()
      ..moveTo(size.width * .44, size.height * .61)
      ..lineTo(size.width * .53, size.height * .49)
      ..lineTo(size.width * .72, size.height * .49)
      ..lineTo(size.width * .79, size.height * .61)
      ..close();
    canvas.drawPath(roof, car);
    final glass = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(size.width * .45, size.height * .84),
        size.width * .075, glass);
    canvas.drawCircle(Offset(size.width * .72, size.height * .84),
        size.width * .075, glass);
    canvas.drawCircle(Offset(size.width * .45, size.height * .84),
        size.width * .035, car);
    canvas.drawCircle(Offset(size.width * .72, size.height * .84),
        size.width * .035, car);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
