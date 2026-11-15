import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'horse_colors.dart';

/// コースと馬を描く。8 レーンを縦に並べ、馬は左から右へ走る。
class RaceTrack extends StatelessWidget {
  const RaceTrack({super.key, required this.progress, this.myHorse, this.animMs = 0});

  /// progress[馬番-1] は進み具合(0.0〜1.0)
  final List<double> progress;

  /// 自分が賭けた馬番(レーンを強調する)
  final int? myHorse;

  /// 脚の動きに使う経過時間
  final int animMs;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CustomPaint(
        painter: _TrackPainter(progress: progress, myHorse: myHorse, animMs: animMs),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({required this.progress, required this.myHorse, required this.animMs});
  final List<double> progress;
  final int? myHorse;
  final int animMs;

  @override
  void paint(Canvas canvas, Size size) {
    final lanes = math.max(progress.length, 1);
    final laneH = size.height / lanes;
    final horseSize = math.min(laneH * 0.8, size.width * 0.16);
    final startX = horseSize + 6;
    final goalX = size.width - 22;

    final fill = Paint();
    for (var i = 0; i < lanes; i++) {
      final mine = myHorse == i + 1;
      fill.color = mine
          ? const Color(0xFF3FA95C)
          : (i.isEven ? const Color(0xFF2F8F4A) : const Color(0xFF2A8444));
      canvas.drawRect(Rect.fromLTWH(0, i * laneH, size.width, laneH), fill);
    }
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i < lanes; i++) {
      canvas.drawLine(Offset(0, i * laneH), Offset(size.width, i * laneH), line);
    }
    // 自分の馬のレーンの枠と印
    final my = myHorse;
    if (my != null && my >= 1 && my <= lanes) {
      final rect = Rect.fromLTWH(1.5, (my - 1) * laneH + 1.5, size.width - 3, laneH - 3);
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFFFFD54A),
      );
      final label = TextPainter(
        text: const TextSpan(
          text: 'あなたの馬',
          style: TextStyle(color: Color(0xFFFFE9A0), fontSize: 11, fontWeight: FontWeight.w800, locale: Locale('ja', 'JP')),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(size.width - label.width - 30, (my - 1) * laneH + 4));
    }
    // スタート線
    canvas.drawLine(
      Offset(startX, 0),
      Offset(startX, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..strokeWidth = 2,
    );
    // ゴール線(市松模様)
    final sq = math.max(5.0, laneH / 6);
    var row = 0;
    for (var y = 0.0; y < size.height; y += sq, row++) {
      for (var c = 0; c < 2; c++) {
        fill.color = (row + c).isEven ? Colors.white : const Color(0xFF111111);
        canvas.drawRect(Rect.fromLTWH(goalX + c * sq, y, sq, sq), fill);
      }
    }

    for (var i = 0; i < progress.length; i++) {
      final p = progress[i].clamp(0.0, 1.0);
      final x = startX + (goalX - startX) * p;
      final y = i * laneH + laneH / 2;
      _drawHorse(canvas, x, y, horseSize, i + 1, p > 0 && p < 1 ? animMs : 0);
    }
  }

  /// 右向きの馬。鼻先が x に来るように描く(管理ページと同じ形)。
  void _drawHorse(Canvas canvas, double x, double y, double size, int no, int runMs) {
    final s = size / 60;
    final running = runMs != 0;
    final phase = runMs / 110 + no;
    final bob = running ? math.sin(phase) * 2.2 : 0.0;
    canvas.save();
    canvas.translate(x - 58 * s, y + bob * s);
    canvas.scale(s);
    const body = Color(0xFF6B4426);
    const dark = Color(0xFF3F2613);

    final stroke = Paint()
      ..color = dark
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    double swing(double offset) => running ? math.sin(phase + offset) * 9 : 0;
    for (final (lx, off) in [(12.0, 0.0), (18.0, math.pi), (38.0, math.pi / 2), (44.0, -math.pi / 2)]) {
      canvas.drawLine(Offset(lx, 8), Offset(lx + swing(off), 24), stroke);
    }
    // しっぽ
    canvas.drawPath(
      Path()
        ..moveTo(6, -4)
        ..quadraticBezierTo(-6, -2 + (running ? math.sin(phase) * 3 : 4), -4, 10),
      stroke,
    );
    // 胴
    final fill = Paint()..color = body;
    canvas.drawOval(Rect.fromCenter(center: const Offset(28, 0), width: 46, height: 22), fill);
    // 首と頭
    canvas.drawPath(
      Path()
        ..moveTo(40, -6)
        ..lineTo(50, -20)
        ..lineTo(60, -14)
        ..lineTo(58, -8)
        ..lineTo(50, -6)
        ..lineTo(48, 4)
        ..close(),
      fill,
    );
    // たてがみ・耳
    canvas.drawPath(
      Path()
        ..moveTo(41, -8)
        ..lineTo(49, -21)
        ..lineTo(51, -24)
        ..lineTo(52, -19)
        ..lineTo(44, -6)
        ..close(),
      Paint()..color = dark,
    );
    // ゼッケン
    final cloth = RRect.fromRectAndRadius(const Rect.fromLTWH(17, -11, 20, 18), const Radius.circular(3));
    canvas.drawRRect(cloth, Paint()..color = horseColor(no));
    canvas.drawRRect(
      cloth,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF111111),
    );
    final number = TextPainter(
      text: TextSpan(
        text: '$no',
        style: TextStyle(color: horseTextColor(no), fontSize: 14, fontWeight: FontWeight.w800, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    number.paint(canvas, Offset(27 - number.width / 2, -2 - number.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.animMs != animMs || old.myHorse != myHorse || !_same(old.progress, progress);

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
