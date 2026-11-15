import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../race_math.dart';
import 'horse_colors.dart';

/// コースと馬を描く。8 レーンを縦に並べ、馬は左から右へ走る。
/// コースは画面より長く、先頭の馬を追って横に流れる。上部に全馬の位置が分かる全体図を出す。
class RaceTrack extends StatelessWidget {
  const RaceTrack({super.key, required this.progress, this.myHorse, this.animMs = 0, this.distance = 1600});

  /// progress[馬番-1] は進み具合(0.0〜1.0)
  final List<double> progress;

  /// 自分が賭けた馬番(レーンを強調する)
  final int? myHorse;

  /// 脚の動きに使う経過時間
  final int animMs;

  /// レースの距離(m)。長いほどコースが長くなる。
  final int distance;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CustomPaint(
        painter: _TrackPainter(progress: progress, myHorse: myHorse, animMs: animMs, distance: distance),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({required this.progress, required this.myHorse, required this.animMs, required this.distance});
  final List<double> progress;
  final int? myHorse;
  final int animMs;
  final int distance;

  static const _mapH = 26.0; // 上部の全体図の高さ

  @override
  void paint(Canvas canvas, Size size) {
    final lanes = math.max(progress.length, 1);
    final trackH = size.height - _mapH;
    final laneH = trackH / lanes;
    final horseSize = math.min(laneH * 0.8, size.width * 0.16);
    final startX = horseSize + 6;
    final worldW = size.width * trackScale(distance);
    final goalX = worldW - 30;
    double xOf(double p) => startX + (goalX - startX) * p.clamp(0.0, 1.0);
    final lead = progress.fold(0.0, math.max).clamp(0.0, 1.0);
    final cam = cameraX(xOf(lead), size.width, worldW);

    // ---- コース(カメラに合わせて流れる) ----
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, _mapH, size.width, trackH));
    canvas.translate(-cam, _mapH);
    final fill = Paint();
    for (var i = 0; i < lanes; i++) {
      final mine = myHorse == i + 1;
      fill.color = mine
          ? const Color(0xFF3FA95C)
          : (i.isEven ? const Color(0xFF2F8F4A) : const Color(0xFF2A8444));
      canvas.drawRect(Rect.fromLTWH(cam, i * laneH, size.width, laneH), fill);
    }
    // 芝の刈り目(コースに固定した縦じま。流れて見える)
    const stripe = 90.0;
    fill.color = Colors.white.withValues(alpha: 0.05);
    for (var x = (cam / (stripe * 2)).floor() * stripe * 2; x < cam + size.width; x += stripe * 2) {
      canvas.drawRect(Rect.fromLTWH(x, 0, stripe, trackH), fill);
    }
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i < lanes; i++) {
      canvas.drawLine(Offset(cam, i * laneH), Offset(cam + size.width, i * laneH), line);
    }
    // 自分の馬のレーンの枠
    final my = myHorse;
    if (my != null && my >= 1 && my <= lanes) {
      canvas.drawRect(
        Rect.fromLTWH(cam + 1.5, (my - 1) * laneH + 1.5, size.width - 3, laneH - 3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFFFFD54A),
      );
      _text(canvas, 'あなたの馬', Offset(cam + 8, (my - 1) * laneH + 4), const Color(0xFFFFE9A0), 11);
    }
    // スタート線
    canvas.drawLine(
      Offset(startX, 0),
      Offset(startX, trackH),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..strokeWidth = 2,
    );
    // 200m ごとの標識(残り距離)
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1.5;
    for (var remain = 200; remain < distance; remain += 200) {
      final x = xOf(1 - remain / distance);
      if (x < cam - 60 || x > cam + size.width + 60) continue;
      for (var y = 0.0; y < trackH; y += 12) {
        canvas.drawLine(Offset(x, y), Offset(x, math.min(y + 6, trackH)), dash);
      }
      _text(canvas, '残り${remain}m', Offset(x + 4, trackH - 16), Colors.white.withValues(alpha: 0.85), 11);
    }
    // ゴール線(市松模様)
    final sq = math.max(5.0, laneH / 6);
    var row = 0;
    for (var y = 0.0; y < trackH; y += sq, row++) {
      for (var c = 0; c < 2; c++) {
        fill.color = (row + c).isEven ? Colors.white : const Color(0xFF111111);
        canvas.drawRect(Rect.fromLTWH(goalX + c * sq, y, sq, sq), fill);
      }
    }
    for (var i = 0; i < progress.length; i++) {
      final p = progress[i].clamp(0.0, 1.0);
      _drawHorse(canvas, xOf(p), i * laneH + laneH / 2, horseSize, i + 1, p > 0 && p < 1 ? animMs : 0);
    }
    canvas.restore();

    // ---- 全体図(画面に固定): スタートからゴールまでの全馬の位置 ----
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, _mapH), Paint()..color = const Color(0xFF14562A));
    const mapL = 14.0;
    final mapR = size.width - 18;
    canvas.drawLine(
      const Offset(mapL, _mapH / 2),
      Offset(mapR, _mapH / 2),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 2,
    );
    canvas.drawRect(Rect.fromLTWH(mapR, 5, 3, _mapH - 10), Paint()..color = Colors.white);
    // 遅い馬を先に描き、先頭の馬が上に来るようにする
    // 自分の馬の点は、ほかの馬に隠れないよう最後に描く
    final byProgress = [for (var i = 0; i < progress.length; i++) i]
      ..sort((a, b) {
        if ((myHorse == a + 1) != (myHorse == b + 1)) return myHorse == a + 1 ? 1 : -1;
        return progress[a].compareTo(progress[b]);
      });
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF111111);
    for (final i in byProgress) {
      final center = Offset(mapL + (mapR - mapL) * progress[i].clamp(0.0, 1.0), _mapH / 2);
      final mine = myHorse == i + 1;
      canvas.drawCircle(center, mine ? 7.5 : 5.5, Paint()..color = horseColor(i + 1));
      canvas.drawCircle(center, mine ? 7.5 : 5.5, border);
    }
  }

  void _text(Canvas canvas, String text, Offset at, Color color, double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.w800, locale: const Locale('ja', 'JP')),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
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
      old.animMs != animMs || old.myHorse != myHorse || old.distance != distance || !_same(old.progress, progress);

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
