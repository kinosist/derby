import 'package:flutter/material.dart';

// 馬番ごとの色(管理ページと揃える): 1 白, 2 黒, 3 赤, 4 青, 5 黄, 6 緑, 7 橙, 8 桃
const _colors = [
  Color(0xFFFFFFFF),
  Color(0xFF1B1B1B),
  Color(0xFFD6282B),
  Color(0xFF1F5FD1),
  Color(0xFFF2CF1D),
  Color(0xFF1F9A4A),
  Color(0xFFF08A1C),
  Color(0xFFF29AC0),
];
const _lightText = [false, true, true, true, false, true, true, false];

Color horseColor(int no) => _colors[(no - 1) % _colors.length];
Color horseTextColor(int no) => _lightText[(no - 1) % _colors.length] ? Colors.white : const Color(0xFF111111);

/// 馬番のゼッケン
class HorseBadge extends StatelessWidget {
  const HorseBadge(this.no, {super.key, this.size = 32});
  final int no;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: horseColor(no),
        borderRadius: BorderRadius.circular(size * 0.2),
        border: Border.all(color: const Color(0xFF1B1B1B), width: 1.5),
      ),
      child: Text(
        '$no',
        style: TextStyle(color: horseTextColor(no), fontWeight: FontWeight.w800, fontSize: size * 0.55, height: 1),
      ),
    );
  }
}
