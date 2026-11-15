import 'package:derby/main.dart';
import 'package:derby/src/protocol.dart';
import 'package:derby/src/race_math.dart';
import 'package:derby/src/room_client.dart';
import 'package:derby/src/views/race_view.dart';
import 'package:derby/src/widgets/race_track.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const now = 1000000;

final horses = [
  for (var no = 1; no <= 8; no++) HorseInfo(no: no, name: 'ウマ$no', odds: 2.0 + no),
];

// 馬番 1 が最も速く、8 が最も遅い。区間ごとに少し緩急を付ける。
final times = [
  for (var h = 0; h < 8; h++) [for (var i = 0; i <= 10; i++) i * (1600 + h * 30) + (i.isOdd ? 120 : 0) * (i < 10 ? 1 : 0)],
];

RoomView view(Phase phase, {int startedAt = now - 8000, Bet? bet, LastResult? lastResult, int coins = 1400}) => RoomView(
      phase: phase,
      raceNo: 2,
      totalRaces: 5,
      serverNow: now,
      betCount: 1,
      onlineCount: 2,
      horses: phase == Phase.lobby || phase == Phase.finalResult ? const [] : horses,
      players: [
        PlayerInfo(id: 'a', name: 'たろうたろうたろうたろう', coins: coins, rank: 1, online: true),
        const PlayerInfo(id: 'b', name: 'はなこ', coins: 900, rank: 2, online: false),
      ],
      bets: const [],
      me: Me(id: 'a', name: 'たろうたろうたろうたろう', coins: coins, rank: 1, bet: bet, lastResult: lastResult),
      race: phase == Phase.racing || phase == Phase.result
          ? RaceInfo(startedAt: startedAt, durationMs: 20000, order: const [1, 2, 3, 4, 5, 6, 7, 8], times: times)
          : null,
    );

void main() {
  late RoomClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    client = RoomClient(url: 'ws://test/ws', prefs: await SharedPreferences.getInstance(), nowMs: () => now);
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpRace(WidgetTester tester, RoomView v) async {
    phone(tester);
    client.debugSetView(v);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RaceView(client: client))));
    await tester.pump(const Duration(milliseconds: 16));
  }

  testWidgets('途中から開いても、経過時間に合った位置を描く', (tester) async {
    await pumpRace(tester, view(Phase.racing, bet: const Bet(horse: 3, amount: 300)));
    final track = tester.widget<RaceTrack>(find.byType(RaceTrack));
    expect(track.progress.length, 8);
    for (var i = 0; i < 8; i++) {
      expect(track.progress[i], closeTo(horseProgress(times[i], 8000), 0.02), reason: '馬番 ${i + 1}');
    }
    expect(track.progress[0], greaterThan(track.progress[7]));
    expect(track.myHorse, 3);
    expect(find.text('結果を待っています…'), findsNothing);
    expect(find.textContaining('300'), findsWidgets);
  });

  testWidgets('全馬ゴール後は 1.0 で止まり、結果待ちの表示になる', (tester) async {
    await pumpRace(tester, view(Phase.racing, startedAt: now - 30000));
    final track = tester.widget<RaceTrack>(find.byType(RaceTrack));
    expect(track.progress, everyElement(1.0));
    expect(track.myHorse, isNull);
    expect(find.text('結果を待っています…'), findsOneWidget);
    expect(find.text('見送り'), findsOneWidget);
  });

  testWidgets('開始前(時計のずれで経過が負)でも 0 から始まる', (tester) async {
    await pumpRace(tester, view(Phase.racing, startedAt: now + 500));
    final track = tester.widget<RaceTrack>(find.byType(RaceTrack));
    expect(track.progress, everyElement(0.0));
  });

  testWidgets('映像データが空でも落ちない', (tester) async {
    phone(tester);
    client.debugSetView(RoomView(
      phase: Phase.racing, raceNo: 1, totalRaces: 5, serverNow: now, betCount: 0, onlineCount: 1,
      horses: horses, players: const [], bets: const [],
      me: const Me(id: 'a', name: 'a', coins: 1000, rank: 1),
      race: const RaceInfo(startedAt: now, durationMs: 20000, order: [], times: []),
    ));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: RaceView(client: client))));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  });

  // 画面全体を各フェーズで描いて、はみ出しや例外がないことを確かめる
  for (final (label, v) in [
    ('受付', view(Phase.lobby)),
    ('賭け受付', view(Phase.betting)),
    ('賭け済み', view(Phase.betting, bet: const Bet(horse: 8, amount: 1400))),
    ('レース中', view(Phase.racing, bet: const Bet(horse: 3, amount: 300))),
    ('結果・的中', view(Phase.result, bet: const Bet(horse: 1, amount: 300), lastResult: const LastResult(horse: 1, amount: 300, won: true, delta: 1230), coins: 1234567)),
    ('結果・はずれ', view(Phase.result, lastResult: const LastResult(horse: 2, amount: 300, won: false, delta: -300))),
    ('結果・見送り', view(Phase.result)),
    ('最終結果', view(Phase.finalResult, coins: 1234567)),
  ]) {
    testWidgets('画面全体: $label がはみ出さずに描ける', (tester) async {
      phone(tester);
      client.debugSetView(v);
      await tester.pumpWidget(DerbyApp(client: client));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('コイン'), findsWidgets);
    });
  }

  testWidgets('画面全体: 小さい画面(320x480)でも賭け画面がはみ出さない', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    client.debugSetView(view(Phase.betting));
    await tester.pumpWidget(DerbyApp(client: client));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('結果画面の文言', (tester) async {
    phone(tester);
    client.debugSetView(view(Phase.result, bet: const Bet(horse: 1, amount: 300), lastResult: const LastResult(horse: 1, amount: 300, won: true, delta: 1230)));
    await tester.pumpWidget(DerbyApp(client: client));
    await tester.pump();
    expect(find.text('的中! +1,230'), findsOneWidget);
    client.debugSetView(view(Phase.result, lastResult: const LastResult(horse: 2, amount: 300, won: false, delta: -300)));
    await tester.pump();
    expect(find.text('はずれ −300'), findsOneWidget);
    client.debugSetView(view(Phase.result));
    await tester.pump();
    expect(find.text('見送り'), findsOneWidget);
  });
}
