/// 3 桁区切り(例: 1400 → "1,400")
String formatCoins(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// 増減の表示(例: +1,230 / −300)
String formatDelta(int n) => n >= 0 ? '+${formatCoins(n)}' : '−${formatCoins(-n)}';

String formatOdds(double odds) => '${odds.toStringAsFixed(1)}倍';
