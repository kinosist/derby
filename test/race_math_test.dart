import 'package:derby/src/race_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final even = List.generate(11, (i) => i * 2000); // 0, 2000, …, 20000

  test('horseProgress: 等間隔', () {
    expect(horseProgress(even, 0), 0.0);
    expect(horseProgress(even, 1000), closeTo(0.05, 1e-9));
    expect(horseProgress(even, 2000), closeTo(0.1, 1e-9));
    expect(horseProgress(even, 19000), closeTo(0.95, 1e-9));
    expect(horseProgress(even, 20000), 1.0);
    expect(horseProgress(even, 25000), 1.0);
    expect(horseProgress(even, -5), 0.0);
  });

  test('horseProgress: 不等間隔は区間内で線形補間', () {
    final t = [0, 1000, 3000, 5000, 7000, 9000, 11000, 13000, 15000, 17000, 19000];
    expect(horseProgress(t, 500), closeTo(0.05, 1e-9));
    expect(horseProgress(t, 2000), closeTo(0.15, 1e-9));
    expect(horseProgress(t, 3000), closeTo(0.2, 1e-9));
  });

  test('horseProgress: データが空・1点だけでも落ちない', () {
    expect(horseProgress(const [], 1000), 0.0);
    expect(horseProgress(const [0], 1000), 0.0);
  });

  test('liveOrder: 進んでいる順、同位置は馬番順', () {
    final fast = List.generate(11, (i) => i * 1600);
    final slow = List.generate(11, (i) => i * 1900);
    // 馬番 1: slow, 2: fast, 3: slow, 4: even
    expect(liveOrder([slow, fast, slow, even], 8000), [2, 1, 3, 4]);
    expect(liveOrder([slow, fast, slow, even], 0), [1, 2, 3, 4]);
  });

  test('trackScale: 距離が長いほどコースが長い(画面幅の 3〜5 倍)', () {
    expect(trackScale(1200), 3.0);
    expect(trackScale(1800), 4.0);
    expect(trackScale(2400), 5.0);
    expect(trackScale(800), 3.0);
    expect(trackScale(3600), 5.0);
  });

  test('cameraX: 先頭の馬を画面の右寄り(7割の位置)に置き、両端では止まる', () {
    // 画面幅 400、コース全長 1600
    expect(cameraX(100, 400, 1600), 0.0); // スタート直後は左端で止まる
    expect(cameraX(280, 400, 1600), 0.0);
    expect(cameraX(680, 400, 1600), 400.0); // 680 - 400*0.7
    expect(cameraX(1590, 400, 1600), 1200.0); // ゴール前は右端で止まる
    expect(cameraX(100, 400, 300), 0.0); // コースが画面より短くても負にならない
  });
}
