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

const moods = ['fired', 'happy', 'calm', 'restless', 'sleepy'];
final horses = [
  for (var no = 1; no <= 8; no++)
    HorseInfo(no: no, name: 'ワクワクジャーニー$no', odds: 20.0 + no, sex: '牡', age: 4, weight: 518, weightDiff: -10,
        style: '追込', recent: const [10, 12, 11], pop: no, cond: 1 + no % 5, mood: moods[no % 5], hasDetails: true),
];

// 馬番 1 が最も速く、8 が最も遅い。区間ごとに少し緩急を付ける。
final times = [
  for (var h = 0; h < 8; h++) [for (var i = 0; i <= 10; i++) i * (1600 + h * 30) + (i.isOdd ? 120 : 0) * (i < 10 ? 1 : 0)],
];

RoomView view(Phase phase, {int startedAt = now - 8000, Ticket? bet, Results? results, int coins = 1400}) => RoomView(
      phase: phase,
      raceNo: 2,
      totalRaces: 5,
      serverNow: now,
      betCount: 1,
      onlineCount: 2,
      horses: phase == Phase.lobby || phase == Phase.finalResult ? const [] : horses,
      course: phase == Phase.lobby || phase == Phase.finalResult ? null : const CourseInfo(distance: 2400, going: '不良'),
      players: [
        PlayerInfo(id: 'a', name: 'たろうたろうたろうたろう', coins: coins, rank: 1, online: true),
        const PlayerInfo(id: 'b', name: 'はなこ', coins: 900, rank: 2, online: false),
      ],
      bets: const [],
      me: Me(id: 'a', name: 'たろうたろうたろうたろう', coins: coins, rank: 1, tickets: [?bet], results: results),
      race: phase == Phase.racing || phase == Phase.result
          ? RaceInfo(startedAt: startedAt, durationMs: 20000, order: const [1, 2, 3, 4, 5, 6, 7, 8], times: times)
          : null,
    );

/// 3連単を含む 10 点を持っている場面
RoomView manyTickets(Phase phase) {
  final base = view(phase);
  final tickets = [
    for (var h = 1; h <= 8; h++) Ticket(id: 't$h', type: BetType.trifecta, horses: [h, h % 8 + 1, (h + 1) % 8 + 1], amount: 100, odds: 999.9),
    const Ticket(id: 'q', type: BetType.quinella, horses: [1, 2], amount: 100, odds: 12.5),
    const Ticket(id: 'p', type: BetType.place, horses: [1], amount: 100, odds: 1.4),
  ];
  return RoomView(
    phase: phase, raceNo: 2, totalRaces: 5, serverNow: now, betCount: 1, onlineCount: 2,
    horses: base.horses, course: base.course, players: base.players, race: base.race,
    bets: phase == Phase.result
        ? [
            PublicBet(playerId: 'a', horse: 1, amount: 1000, delta: 98890, tickets: [
              for (final t in tickets)
                TicketResult(type: t.type, horses: t.horses, amount: t.amount, odds: t.odds, won: t.id == 't1', payout: t.id == 't1' ? 99990 : 0),
            ]),
          ]
        : const [],
    me: Me(
      id: 'a', name: 'たろうたろうたろうたろう', coins: 99890, rank: 1,
      tickets: tickets,
      results: phase == Phase.result
          ? Results(staked: 1000, delta: 98990, tickets: [
              for (final t in tickets)
                TicketResult(type: t.type, horses: t.horses, amount: t.amount, odds: t.odds, won: t.id == 't1', payout: t.id == 't1' ? 99990 : 0),
            ])
          : null,
    ),
  );
}

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
    await pumpRace(tester, view(Phase.racing, bet: const Ticket(id: 't', type: BetType.win, horses: [3], amount: 300, odds: 2.0)));
    final track = tester.widget<RaceTrack>(find.byType(RaceTrack));
    expect(track.progress.length, 8);
    for (var i = 0; i < 8; i++) {
      expect(track.progress[i], closeTo(horseProgress(times[i], 8000), 0.02), reason: '馬番 ${i + 1}');
    }
    expect(track.progress[0], greaterThan(track.progress[7]));
    expect(track.myHorses, {3});
    expect(track.distance, 2400);
    expect(find.textContaining('残り'), findsOneWidget);
    expect(find.text('結果を待っています…'), findsNothing);
    expect(find.textContaining('300'), findsWidgets);
  });

  testWidgets('全馬ゴール後は 1.0 で止まり、結果待ちの表示になる', (tester) async {
    await pumpRace(tester, view(Phase.racing, startedAt: now - 30000));
    final track = tester.widget<RaceTrack>(find.byType(RaceTrack));
    expect(track.progress, everyElement(1.0));
    expect(track.myHorses, isEmpty);
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
    ('賭け済み', view(Phase.betting, bet: const Ticket(id: 't', type: BetType.win, horses: [8], amount: 1400, odds: 2.0))),
    ('レース中', view(Phase.racing, bet: const Ticket(id: 't', type: BetType.win, horses: [3], amount: 300, odds: 2.0))),
    ('結果・的中', view(Phase.result, bet: const Ticket(id: 't', type: BetType.win, horses: [1], amount: 300, odds: 2.0), results: const Results(staked: 300, delta: 1230, tickets: [TicketResult(type: BetType.win, horses: [1], amount: 300, odds: 5.1, won: true, payout: 1530)]), coins: 1234567)),
    ('結果・はずれ', view(Phase.result, results: const Results(staked: 300, delta: -300, tickets: [TicketResult(type: BetType.win, horses: [2], amount: 300, odds: 5.1, won: false, payout: 0)]))),
    ('結果・見送り', view(Phase.result)),
    ('最終結果', view(Phase.finalResult, coins: 1234567)),
    ('レース中・馬券 10 点', manyTickets(Phase.racing)),
    ('結果・馬券 10 点', manyTickets(Phase.result)),
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

  testWidgets('レース中: 複数の馬券を持っていると、点数と合計が出て、関係する馬がすべて強調される', (tester) async {
    await pumpRace(tester, manyTickets(Phase.racing));
    final track = tester.widget<RaceTrack>(find.byType(RaceTrack));
    expect(track.myHorses, {1, 2, 3, 4, 5, 6, 7, 8});
    expect(find.textContaining('10点'), findsOneWidget);
    expect(find.textContaining('計 1,000'), findsOneWidget);
  });

  testWidgets('結果: 馬券ごとの当たり外れと払い戻しが出る', (tester) async {
    phone(tester);
    client.debugSetView(manyTickets(Phase.result));
    await tester.pumpWidget(DerbyApp(client: client));
    await tester.pump();
    expect(find.text('的中! +98,990'), findsOneWidget);
    expect(find.textContaining('3連単 1→2→3'), findsWidgets);
    expect(find.textContaining('+99,990'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('結果: 一部だけ当たって差し引きが損のときは「一部的中」と出る', (tester) async {
    phone(tester);
    client.debugSetView(view(Phase.result, results: const Results(staked: 400, delta: -200, tickets: [
      TicketResult(type: BetType.place, horses: [3], amount: 100, odds: 2.0, won: true, payout: 200),
      TicketResult(type: BetType.win, horses: [3], amount: 300, odds: 6.4, won: false, payout: 0),
    ])));
    await tester.pumpWidget(DerbyApp(client: client));
    await tester.pump();
    expect(find.text('一部的中 −200'), findsOneWidget);
    expect(find.textContaining('的中!'), findsNothing);
    // 差し引きがちょうど 0 なら「的中! +0」
    client.debugSetView(view(Phase.result, results: const Results(staked: 200, delta: 0, tickets: [
      TicketResult(type: BetType.place, horses: [3], amount: 100, odds: 2.0, won: true, payout: 200),
      TicketResult(type: BetType.win, horses: [3], amount: 100, odds: 6.4, won: false, payout: 0),
    ])));
    await tester.pump();
    expect(find.text('的中! +0'), findsOneWidget);
  });

  testWidgets('結果画面の文言', (tester) async {
    phone(tester);
    client.debugSetView(view(Phase.result, bet: const Ticket(id: 't', type: BetType.win, horses: [1], amount: 300, odds: 2.0), results: const Results(staked: 300, delta: 1230, tickets: [TicketResult(type: BetType.win, horses: [1], amount: 300, odds: 5.1, won: true, payout: 1530)])));
    await tester.pumpWidget(DerbyApp(client: client));
    await tester.pump();
    expect(find.text('的中! +1,230'), findsOneWidget);
    client.debugSetView(view(Phase.result, results: const Results(staked: 300, delta: -300, tickets: [TicketResult(type: BetType.win, horses: [2], amount: 300, odds: 5.1, won: false, payout: 0)])));
    await tester.pump();
    expect(find.text('はずれ −300'), findsOneWidget);
    client.debugSetView(view(Phase.result));
    await tester.pump();
    expect(find.text('見送り'), findsOneWidget);
  });
}
