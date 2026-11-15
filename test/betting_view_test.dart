import 'package:derby/src/protocol.dart';
import 'package:derby/src/views/betting_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const horses = [
  HorseInfo(no: 1, name: 'ハヤテオー', odds: 2.4),
  HorseInfo(no: 2, name: 'ミドリノカゼ', odds: 5.1),
  HorseInfo(no: 3, name: 'アサヤケゴー', odds: 12.0),
  HorseInfo(no: 4, name: 'ツキアカリ', odds: 8.3),
  HorseInfo(no: 5, name: 'ノンビリヤ', odds: 20.5),
  HorseInfo(no: 6, name: 'ガンバルゾー', odds: 6.0),
  HorseInfo(no: 7, name: 'アカトンボ', odds: 9.9),
  HorseInfo(no: 8, name: 'サクラフブキ', odds: 30.0),
];

RoomView bettingView({int coins = 1400, Bet? bet}) => RoomView(
      phase: Phase.betting,
      raceNo: 3,
      totalRaces: 5,
      serverNow: 0,
      betCount: 0,
      onlineCount: 1,
      horses: horses,
      players: [PlayerInfo(id: 'a', name: 'たろう', coins: coins, rank: 1, online: true)],
      bets: const [],
      me: Me(id: 'a', name: 'たろう', coins: coins, rank: 1, bet: bet),
    );

void main() {
  late List<(int, int)> bets;
  late int cancels;

  Future<void> pump(WidgetTester tester, RoomView view) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    bets = [];
    cancels = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BettingView(view: view, onBet: (h, a) => bets.add((h, a)), onCancel: () => cancels++),
      ),
    ));
  }

  String amount(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('betAmount'))).data!;
  FilledButton submit(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'この内容で賭ける'));

  testWidgets('馬と金額を選ぶと、当たったときの払い戻しが出て、賭けられる', (tester) async {
    await pump(tester, bettingView());
    expect(find.text('5.1倍'), findsOneWidget);
    expect(find.text('12.0倍'), findsOneWidget);
    expect(amount(tester), '100');
    expect(submit(tester).onPressed, isNull); // 馬を選ぶまで押せない

    await tester.tap(find.text('ミドリノカゼ'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('betPlus100')));
    await tester.tap(find.byKey(const Key('betPlus100')));
    await tester.pump();
    expect(amount(tester), '300');
    expect(find.text('当たれば 1,530'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'この内容で賭ける'));
    expect(bets, [(2, 300)]);
  });

  testWidgets('金額は 10 〜 所持金の範囲に収まる', (tester) async {
    await pump(tester, bettingView());
    await tester.tap(find.byKey(const Key('betAll')));
    await tester.pump();
    expect(amount(tester), '1,400');
    await tester.tap(find.byKey(const Key('betPlus')));
    await tester.tap(find.byKey(const Key('betPlus100')));
    await tester.pump();
    expect(amount(tester), '1,400');
    await tester.tap(find.byKey(const Key('betMinus')));
    await tester.pump();
    expect(amount(tester), '1,390');

    await pump(tester, bettingView(coins: 30));
    expect(amount(tester), '30');
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('betMinus')));
      await tester.pump();
    }
    expect(amount(tester), '10');
  });

  testWidgets('全額は 10 コイン単位に切り下げる', (tester) async {
    await pump(tester, bettingView(coins: 1538));
    await tester.tap(find.byKey(const Key('betAll')));
    await tester.pump();
    expect(amount(tester), '1,530');
  });

  testWidgets('賭け済みなら内容と「変更」「取り消し」が出る', (tester) async {
    await pump(tester, bettingView(bet: const Bet(horse: 2, amount: 300)));
    expect(find.textContaining('300'), findsWidgets);
    expect(find.text('この内容で賭ける'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '取り消し'));
    expect(cancels, 1);

    await tester.tap(find.widgetWithText(OutlinedButton, '変更'));
    await tester.pump();
    expect(amount(tester), '300'); // 今の賭けから編集を始める
    await tester.tap(find.text('ハヤテオー'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'この内容で賭ける'));
    expect(bets, [(1, 300)]);
  });

  testWidgets('所持金が 10 未満なら賭けられず、案内が出る', (tester) async {
    await pump(tester, bettingView(coins: 5));
    await tester.tap(find.text('ミドリノカゼ'));
    await tester.pump();
    expect(submit(tester).onPressed, isNull);
    expect(find.text('次のレースで 100 コインもらえます'), findsOneWidget);
  });
}
