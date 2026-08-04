import 'package:flutter/material.dart';

/// 用于触发衣物背景去除的自绘魔法棒；不依赖 Material 图标字体。
class CutoutWandButton extends StatefulWidget {
  const CutoutWandButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  State<CutoutWandButton> createState() => _CutoutWandButtonState();
}

class _CutoutWandButtonState extends State<CutoutWandButton> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '去除背景',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: SizedBox(
        width: 24,
        height: 24,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          scale: _pressed ? .78 : 1,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 90),
            opacity: _pressed ? .95 : .62,
            child: const CustomPaint(painter: _CutoutWandPainter()),
          ),
        ),
      ),
    ),
  );
}

class _CutoutWandPainter extends CustomPainter {
  const _CutoutWandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 28, size.height / 28);
    final wand = Path()
      ..moveTo(7, 20)
      ..lineTo(20, 7);
    final star = Path()
      ..moveTo(20, 2)
      ..lineTo(20, 12)
      ..moveTo(15, 7)
      ..lineTo(25, 7);
    final smallStar = Path()
      ..moveTo(7, 4)
      ..lineTo(7, 10)
      ..moveTo(4, 7)
      ..lineTo(10, 7);
    final outline = Paint()
      ..color = Colors.white.withValues(alpha: .9)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.8;
    final fill = Paint()
      ..color = Colors.black.withValues(alpha: .85)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.8;
    canvas.drawPath(wand, outline);
    canvas.drawPath(star, outline);
    canvas.drawPath(smallStar, outline);
    canvas.drawPath(wand, fill);
    canvas.drawPath(star, fill);
    canvas.drawPath(smallStar, fill);
  }

  @override
  bool shouldRepaint(covariant _CutoutWandPainter oldDelegate) => false;
}

