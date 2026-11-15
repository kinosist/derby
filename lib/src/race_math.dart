// レース映像データ(各地点の通過時刻)から、その時点の馬の位置を求める。

/// 進み具合(0.0〜1.0)。[times] は各地点の通過時刻(累積 ms)で、区間内は線形補間する。
double horseProgress(List<int> times, int elapsedMs) {
  final segments = times.length - 1;
  if (segments < 1 || elapsedMs <= 0) return 0.0;
  if (elapsedMs >= times[segments]) return 1.0;
  var i = 0;
  while (times[i + 1] <= elapsedMs) {
    i++;
  }
  final within = (elapsedMs - times[i]) / (times[i + 1] - times[i]);
  return (i + within) / segments;
}

/// その時点の順位(馬番の並び)。同じ位置なら馬番の小さい順。
List<int> liveOrder(List<List<int>> times, int elapsedMs) {
  final progress = [for (final t in times) horseProgress(t, elapsedMs)];
  final order = [for (var no = 1; no <= times.length; no++) no];
  order.sort((a, b) {
    final c = progress[b - 1].compareTo(progress[a - 1]);
    return c != 0 ? c : a.compareTo(b);
  });
  return order;
}

/// コースの長さ(画面幅の何倍か)。距離が長いほど長い(1200m で 3 倍、2400m で 5 倍)。
double trackScale(int distance) => 3 + (distance.clamp(1200, 2400) - 1200) / 600;

/// カメラの左端の位置。先頭の馬を画面の右寄り(7割の位置)に置き、コースの両端では止める。
double cameraX(double leaderX, double viewWidth, double worldWidth) {
  final max = worldWidth - viewWidth;
  if (max <= 0) return 0;
  return (leaderX - viewWidth * 0.7).clamp(0.0, max);
}
