import 'dart:math' as math;

import 'package:flutter/material.dart';

const _coats = [
  Color(0xFF7A4A2A),
  Color(0xFF3B2A22),
  Color(0xFFA0612F),
  Color(0xFF8D8D8D),
  Color(0xFF5A3A26),
  Color(0xFFB5793F),
  Color(0xFF2B2B2F),
  Color(0xFF946037),
];

const moodLabels = {
  'fired': '気合十分',
  'happy': 'ごきげん',
  'calm': '落ち着き',
  'restless': 'そわそわ',
  'sleepy': '眠そう',
};

/// 正面から見た馬の顔。表情(mood)で目・耳・口と小物が変わる。
/// 管理ページ(server/public/admin/admin.js の drawFace)と同じ形。
class HorseFace extends StatelessWidget {
  const HorseFace({super.key, required this.no, required this.mood, this.size = 44});
  final int no;
  final String mood;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '表情: ${moodLabels[mood] ?? ''}',
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: Color(0xFFDFEEE2), shape: BoxShape.circle),
        child: CustomPaint(painter: _FacePainter(no: no, mood: mood)),
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  _FacePainter({required this.no, required this.mood});
  final int no;
  final String mood;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 60);
    final coat = Paint()..color = _coats[(no - 1) % _coats.length];
    const darkColor = Color(0xFF241812);
    final dark = Paint()..color = darkColor;
    final line = Paint()
      ..color = darkColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final white = Paint()..color = Colors.white;

    // 耳(表情で向きが変わる)
    final (earDx, earDy) = switch (mood) {
      'fired' => (0.0, -1.0),
      'restless' => (-5.0, 2.0),
      'sleepy' => (-7.0, 5.0),
      _ => (-1.0, -1.0),
    };
    for (final side in [-1.0, 1.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(30 + side * 8, 14)
          ..lineTo(30 + side * (14 - earDx), 2 + earDy)
          ..lineTo(30 + side * 16, 16)
          ..close(),
        coat,
      );
    }
    // 頭と鼻づら
    canvas.drawOval(Rect.fromCenter(center: const Offset(30, 26), width: 30, height: 34), coat);
    canvas.drawOval(Rect.fromCenter(center: const Offset(30, 43), width: 24, height: 24), coat);
    // たてがみ(前髪)
    canvas.drawPath(
      Path()
        ..moveTo(24, 10)
        ..quadraticBezierTo(30, 4, 36, 10)
        ..quadraticBezierTo(32, 18, 30, 20)
        ..quadraticBezierTo(27, 16, 24, 10),
      dark,
    );
    // 鼻づらの色と鼻の穴
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(30, 45), width: 20, height: 18),
      Paint()..color = const Color(0x59FFEBD7),
    );
    for (final side in [-1.0, 1.0]) {
      canvas.drawOval(Rect.fromCenter(center: Offset(30 + side * 5, 44), width: 3.6, height: 5.2), dark);
    }

    // 目
    const eyeY = 27.0;
    for (final side in [-1.0, 1.0]) {
      final ex = 30 + side * 9;
      switch (mood) {
        case 'happy': // にっこり閉じた目
          canvas.drawArc(Rect.fromCircle(center: Offset(ex, eyeY + 1), radius: 3.2), math.pi * 1.1, math.pi * 0.8, false, line);
        case 'sleepy': // 半分閉じた目
          canvas.drawLine(Offset(ex - 3.2, eyeY + 1), Offset(ex + 3.2, eyeY + 1), line);
          canvas.drawArc(Rect.fromCircle(center: Offset(ex, eyeY + 1), radius: 3.2), math.pi * 0.15, math.pi * 0.7, false, line);
        case 'restless': // 見開いて横目
          canvas.drawCircle(Offset(ex, eyeY), 4, white);
          canvas.drawCircle(Offset(ex + 1.8, eyeY + 0.5), 1.6, dark);
        default:
          canvas.drawCircle(Offset(ex, eyeY), mood == 'fired' ? 2.8 : 2.4, dark);
          canvas.drawCircle(Offset(ex + 0.9, eyeY - 0.9), 0.8, white);
          if (mood == 'fired') {
            // つり上がった眉
            canvas.drawLine(
              Offset(ex + side * 5, eyeY - 7.5),
              Offset(ex - side * 4, eyeY - 4),
              Paint()
                ..color = darkColor
                ..strokeWidth = 2.4
                ..strokeCap = StrokeCap.round,
            );
          }
      }
    }

    // 口
    switch (mood) {
      case 'happy':
        canvas.drawArc(Rect.fromCircle(center: const Offset(30, 49), radius: 4.5), math.pi * 0.15, math.pi * 0.7, false, line);
      case 'fired':
        canvas.drawLine(const Offset(25, 51.5), const Offset(35, 51.5), line);
      case 'restless':
        canvas.drawPath(
          Path()
            ..moveTo(25, 51)
            ..quadraticBezierTo(27.5, 49, 30, 51)
            ..quadraticBezierTo(32.5, 53, 35, 51),
          line,
        );
      case 'sleepy':
        canvas.drawCircle(const Offset(30, 51), 1.6, line);
      default:
        canvas.drawLine(const Offset(26.5, 51), const Offset(33.5, 51), line);
    }

    // 小物
    switch (mood) {
      case 'fired': // 鼻息
        final puff = Paint()..color = const Color(0xEBFFFFFF);
        for (final side in [-1.0, 1.0]) {
          for (final (dx, dy, r) in [(12.0, 3.0, 3.4), (16.0, 1.0, 2.6), (19.5, 3.5, 2.0)]) {
            canvas.drawCircle(Offset(30 + side * dx, 44 + dy), r, puff);
          }
        }
      case 'restless': // 汗
        canvas.drawPath(
          Path()
            ..moveTo(49, 14)
            ..quadraticBezierTo(53.5, 21, 49, 23)
            ..quadraticBezierTo(44.5, 21, 49, 14),
          Paint()..color = const Color(0xFF6EC6FF),
        );
      case 'sleepy': // z z
        for (final (x, y, fontSize) in [(49.0, 13.0, 11.0), (55.0, 6.0, 8.0)]) {
          final z = TextPainter(
            text: TextSpan(
              text: 'z',
              style: TextStyle(color: const Color(0xFF5B6FA8), fontSize: fontSize, fontWeight: FontWeight.w800, height: 1),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          z.paint(canvas, Offset(x - z.width / 2, y - z.height / 2));
        }
      case 'happy': // ほっぺ
        final cheek = Paint()..color = const Color(0x73FF7878);
        for (final side in [-1.0, 1.0]) {
          canvas.drawOval(Rect.fromCenter(center: Offset(30 + side * 11.5, 33), width: 6, height: 4), cheek);
        }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.no != no || old.mood != mood;
}

/// 調子 1(絶不調)〜 5(絶好調)の表示(矢印・名前・色)。
/// 矢印は文字ではなくアイコンで出す(斜め矢印の文字は Android で絵文字になってしまう)。
(IconData arrow, String label, Color color) conditionDisplay(int cond) => switch (cond) {
      5 => (Icons.north, '絶好調', const Color(0xFFC62828)),
      4 => (Icons.north_east, '好調', const Color(0xFFE06A00)),
      2 => (Icons.south_east, '不調', const Color(0xFF2A6FBF)),
      1 => (Icons.south, '絶不調', const Color(0xFF283593)),
      _ => (Icons.east, '普通', const Color(0xFF5D6F62)),
    };
