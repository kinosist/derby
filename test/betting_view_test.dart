import 'package:derby/src/protocol.dart';
import 'package:derby/src/views/betting_view.dart';
import 'package:derby/src/widgets/horse_face.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const names = ['ハヤテオー', 'ミドリノカゼ', 'アサヤケゴー', 'ツキアカリ', 'ノンビリヤ', 'ガンバルゾー', 'アカトンボ', 'サクラフブキ'];
const winOdds = [2.4, 5.1, 12.0, 8.3, 20.5, 6.0, 9.9, 30.0];

final horses = [
  for (var i = 0; i < 8; i++) HorseInfo(no: i + 1, name: names[i], odds: winOdds[i]),
];

/// 倍率表。複勝は単勝の半分、馬連は 10 + 馬番の和、3連単は 100 + 1着×10 + 2着 + 3着/10(見分けやすい値)。
final odds = OddsTable(
  raceKey: 'r1',
  place: [for (final o in winOdds) (o / 2 * 10).round() / 10],
  quinella: {
    for (var a = 1; a <= 8; a++)
      for (var b = a + 1; b <= 8; b++) '$a-$b': 10.0 + a + b,
  },
  trifecta: {
    for (var a = 1; a <= 8; a++)
      for (var b = 1; b <= 8; b++)
        for (var c = 1; c <= 8; c++)
          if (a != b && b != c && a != c) '$a-$b-$c': 100.0 + a * 10 + b + c / 10,
  },
);

const tipsters = [
  TipsterInfo(id: 'paper', name: '競馬新聞', price: 30, stars: 1),
  TipsterInfo(id: 'veteran', name: 'ベテラン予想屋', price: 80, stars: 2),
  TipsterInfo(id: 'master', name: '伝説の予想屋', price: 150, stars: 3),
];

RoomView bettingView({
  int coins = 1400,
  List<Ticket> tickets = const [],
  String? raceKey = 'r1',
  List<HorseInfo>? field,
  List<TipsterInfo> sellers = const [],
  List<Tip> tips = const [],
}) =>
    RoomView(
      phase: Phase.betting,
      raceNo: 3,
      totalRaces: 5,
      serverNow: 0,
      betCount: 0,
      onlineCount: 1,
      raceKey: raceKey,
      horses: field ?? horses,
      tipsters: sellers,
      players: [PlayerInfo(id: 'a', name: 'たろう', coins: coins, rank: 1, online: true)],
      bets: const [],
      me: Me(id: 'a', name: 'たろう', coins: coins, rank: 1, tickets: tickets, tips: tips),
    );

void main() {
  late List<String> bought;
  late List<String> cancelled;
  late List<String> tipsBought;

  Future<void> pump(WidgetTester tester, RoomView view, {OddsTable? table, Size size = const Size(1080, 2340), double ratio = 3.0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BettingView(
          view: view,
          odds: table,
          onBuy: (type, horses, amount) => bought.add('${type.name} ${horses.join('-')} $amount'),
          onCancel: cancelled.add,
          onBuyTip: tipsBought.add,
        ),
      ),
    ));
  }

  setUp(() {
    bought = [];
    cancelled = [];
    tipsBought = [];
  });

  String amount(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('betAmount'))).data!;
  FilledButton buy(WidgetTester tester) => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'この馬券を買う'));
  Future<void> tapHorse(WidgetTester tester, int no) async {
    await tester.ensureVisible(find.text(names[no - 1]));
    await tester.tap(find.text(names[no - 1]));
    await tester.pump();
  }

  Future<void> chooseType(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
  }

  group('toggleSelection', () {
    test('単勝・複勝は 1 頭。別の馬を押すと入れ替わり、同じ馬を押すと外れる', () {
      expect(toggleSelection(BetType.win, [], 3), [3]);
      expect(toggleSelection(BetType.win, [3], 5), [5]);
      expect(toggleSelection(BetType.place, [3], 3), isEmpty);
    });
    test('馬連は 2 頭まで', () {
      expect(toggleSelection(BetType.quinella, [3], 5), [3, 5]);
      expect(toggleSelection(BetType.quinella, [3, 5], 3), [5]);
      expect(toggleSelection(BetType.quinella, [3, 5], 7), [3, 7]); // 3 頭目は最後の 1 頭と入れ替え
    });
    test('3連単は押した順に 1着・2着・3着', () {
      expect(toggleSelection(BetType.trifecta, [4], 1), [4, 1]);
      expect(toggleSelection(BetType.trifecta, [4, 1], 2), [4, 1, 2]);
      expect(toggleSelection(BetType.trifecta, [4, 1, 2], 1), [4, 2]); // 外すと後ろが繰り上がる
      expect(toggleSelection(BetType.trifecta, [4, 1, 2], 8), [4, 1, 8]);
    });
  });

  testWidgets('単勝: 馬と金額を選ぶと払い戻しが出て、買える', (tester) async {
    await pump(tester, bettingView(), table: odds);
    expect(find.text('5.1倍'), findsOneWidget);
    expect(amount(tester), '100');
    expect(buy(tester).onPressed, isNull); // 馬を選ぶまで押せない

    await tapHorse(tester, 2);
    await tester.tap(find.byKey(const Key('betPlus100')));
    await tester.tap(find.byKey(const Key('betPlus100')));
    await tester.pump();
    expect(amount(tester), '300');
    expect(find.textContaining('当たれば 1,530'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'この馬券を買う'));
    expect(bought, ['win 2 300']);
  });

  testWidgets('複勝: 出走表の倍率が複勝のものに変わり、複勝で買える', (tester) async {
    await pump(tester, bettingView(), table: odds);
    await chooseType(tester, '複勝');
    expect(find.text('2.6倍'), findsOneWidget); // 馬番 2: 5.1 → 2.6(5.1/2 を丸めた値)
    expect(find.text('5.1倍'), findsNothing);
    await tapHorse(tester, 2);
    expect(find.textContaining('当たれば 260'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'この馬券を買う'));
    expect(bought, ['place 2 100']);
  });

  testWidgets('馬連: 2 頭選ぶと買える。順番は問わない', (tester) async {
    await pump(tester, bettingView(), table: odds);
    await chooseType(tester, '馬連');
    await tapHorse(tester, 5);
    expect(buy(tester).onPressed, isNull); // 1 頭では買えない
    expect(find.textContaining('あと 1 頭'), findsOneWidget);
    await tapHorse(tester, 3);
    expect(find.textContaining('当たれば 1,800'), findsOneWidget); // 3-5: 18.0 倍 × 100
    await tester.tap(find.widgetWithText(FilledButton, 'この馬券を買う'));
    expect(bought, ['quinella 3-5 100']); // 馬番の小さい順で送る
  });

  testWidgets('3連単: 押した順に 1着・2着・3着になり、その順で買える', (tester) async {
    await pump(tester, bettingView(), table: odds);
    await chooseType(tester, '3連単');
    await tapHorse(tester, 4);
    await tapHorse(tester, 1);
    expect(buy(tester).onPressed, isNull);
    expect(find.textContaining('あと 1 頭'), findsOneWidget);
    await tapHorse(tester, 2);
    expect(find.text('1着'), findsOneWidget);
    expect(find.text('2着'), findsOneWidget);
    expect(find.text('3着'), findsOneWidget);
    expect(find.textContaining('当たれば 14,120'), findsOneWidget); // 4-1-2: 141.2 倍 × 100
    await tester.tap(find.widgetWithText(FilledButton, 'この馬券を買う'));
    expect(bought, ['trifecta 4-1-2 100']);
  });

  testWidgets('種類を変えると選択が消える', (tester) async {
    await pump(tester, bettingView(), table: odds);
    await tapHorse(tester, 2);
    expect(buy(tester).onPressed, isNotNull);
    await chooseType(tester, '馬連');
    expect(buy(tester).onPressed, isNull);
  });

  testWidgets('買った馬券が一覧に出て、1 点ずつ取り消せる。残りの金額までしか買えない', (tester) async {
    const tickets = [
      Ticket(id: 't1', type: BetType.win, horses: [2], amount: 300, odds: 5.1),
      Ticket(id: 't2', type: BetType.trifecta, horses: [4, 1, 2], amount: 1000, odds: 141.2),
    ];
    await pump(tester, bettingView(tickets: tickets), table: odds);
    expect(find.textContaining('2点'), findsOneWidget);
    expect(find.textContaining('計 1,300'), findsOneWidget);
    expect(find.textContaining('残り 100'), findsOneWidget);
    expect(find.textContaining('単勝 2'), findsOneWidget);
    expect(find.textContaining('3連単 4→1→2'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('cancel-t2'))); // 一覧は横にスクロールする
    await tester.pump();
    await tester.tap(find.byKey(const Key('cancel-t2')));
    expect(cancelled, ['t2']);

    // 残り 100 コインまでしか賭けられない
    await tester.tap(find.byKey(const Key('betAll')));
    await tester.pump();
    expect(amount(tester), '100');
    await tester.tap(find.byKey(const Key('betPlus100')));
    await tester.pump();
    expect(amount(tester), '100');
  });

  testWidgets('馬券を 10 点買っても、一覧の全部が画面内に見えて、どれも取り消せる', (tester) async {
    final tickets = [
      for (var h = 1; h <= 4; h++) Ticket(id: 'tri$h', type: BetType.trifecta, horses: [h, h + 1, h + 2], amount: 100, odds: 141.2),
      for (var h = 1; h <= 3; h++) Ticket(id: 'q$h', type: BetType.quinella, horses: [h, h + 4], amount: 100, odds: 18),
      for (var h = 1; h <= 3; h++) Ticket(id: 'p$h', type: BetType.place, horses: [h], amount: 10, odds: 1.4),
    ];
    for (final size in [const Size(360, 780), const Size(320, 640)]) {
      await pump(tester, bettingView(tickets: tickets), table: odds, size: size, ratio: 1.0);
      expect(tester.takeException(), isNull);
      final screen = Offset.zero & size;
      for (final t in tickets) {
        final label = find.textContaining(ticketLabel(t.type, t.horses));
        expect(label, findsOneWidget, reason: '${t.id} が一覧に出ていない');
        final rect = tester.getRect(label);
        expect(screen.contains(rect.topLeft) && screen.contains(rect.bottomRight - const Offset(1, 1)), true,
            reason: '${t.id} が画面の外にある: $rect (画面 $size)');
        final close = tester.getRect(find.byKey(Key('cancel-${t.id}')));
        expect(screen.contains(close.center), true, reason: '${t.id} の取り消しボタンが画面の外にある');
      }
      // 出走表も、少なくとも 1 頭分は見える
      expect(tester.getRect(find.text(names[0])).bottom, lessThan(size.height));
      // 買うボタンも画面内にある
      expect(screen.contains(tester.getRect(find.widgetWithText(FilledButton, 'この馬券を買う')).bottomRight - const Offset(1, 1)), true);
    }
    // 一覧のどの馬券も、そのまま(スクロールせずに)取り消せる
    await tester.tap(find.byKey(const Key('cancel-p3')));
    expect(cancelled, ['p3']);
  });

  testWidgets('同じ馬券を選ぶと「金額を変更」になり、その分は残りに含めて計算する', (tester) async {
    const tickets = [Ticket(id: 't1', type: BetType.win, horses: [2], amount: 1000, odds: 5.1)];
    await pump(tester, bettingView(tickets: tickets), table: odds);
    await tapHorse(tester, 2);
    expect(find.widgetWithText(FilledButton, '金額を変更する'), findsOneWidget);
    await tester.tap(find.byKey(const Key('betAll')));
    await tester.pump();
    expect(amount(tester), '1,400'); // 既存の 1,000 を置き換えるので全額まで
    await tester.tap(find.widgetWithText(FilledButton, '金額を変更する'));
    expect(bought, ['win 2 1400']);
  });

  testWidgets('10 点買うと、新しい馬券は買えない', (tester) async {
    final tickets = [
      for (var h = 1; h <= 8; h++) Ticket(id: 'w$h', type: BetType.win, horses: [h], amount: 10, odds: 2),
      const Ticket(id: 'p1', type: BetType.place, horses: [1], amount: 10, odds: 2),
      const Ticket(id: 'p2', type: BetType.place, horses: [2], amount: 10, odds: 2),
    ];
    await pump(tester, bettingView(tickets: tickets), table: odds);
    await chooseType(tester, '複勝');
    await tapHorse(tester, 3);
    expect(buy(tester).onPressed, isNull);
    expect(find.textContaining('10点まで'), findsOneWidget);
  });

  testWidgets('金額は 10 〜 残りの範囲に収まる。全額は 10 コイン単位に切り下げる', (tester) async {
    await pump(tester, bettingView(coins: 1538), table: odds);
    await tester.tap(find.byKey(const Key('betAll')));
    await tester.pump();
    expect(amount(tester), '1,530');
    await tester.tap(find.byKey(const Key('betPlus')));
    await tester.pump();
    expect(amount(tester), '1,530');
    await tester.tap(find.byKey(const Key('betMinus')));
    await tester.pump();
    expect(amount(tester), '1,520');

    await pump(tester, bettingView(coins: 30), table: odds);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('betMinus')));
      await tester.pump();
    }
    expect(amount(tester), '10');
  });

  testWidgets('所持金が 10 未満なら買えず、案内が出る', (tester) async {
    await pump(tester, bettingView(coins: 5), table: odds);
    expect(find.text('次のレースで 100 コインもらえます'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'この馬券を買う'), findsNothing);
  });

  testWidgets('倍率表がまだ届いていない(または別のレースのもの)なら、単勝だけ選べる', (tester) async {
    await pump(tester, bettingView(), table: null);
    await chooseType(tester, '複勝');
    await tapHorse(tester, 2);
    await tester.tap(find.widgetWithText(FilledButton, 'この馬券を買う'));
    expect(bought, ['win 2 100']); // 複勝には切り替わらない

    bought.clear();
    await pump(tester, bettingView(raceKey: 'r2'), table: odds); // 倍率表は r1 のもの
    await chooseType(tester, '馬連');
    await tapHorse(tester, 2);
    await tester.tap(find.widgetWithText(FilledButton, 'この馬券を買う'));
    expect(bought, ['win 2 100']);
  });

  group('予想屋', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.textContaining('予想屋に聞く'));
      await tester.pump();
    }

    testWidgets('一覧を開くと 3 人の名前・精度・料金が出て、料金を払って聞ける', (tester) async {
      await pump(tester, bettingView(sellers: tipsters), table: odds);
      expect(find.text('競馬新聞'), findsNothing); // 最初は閉じている
      await open(tester);
      expect(find.text('競馬新聞'), findsOneWidget);
      expect(find.text('ベテラン予想屋'), findsOneWidget);
      expect(find.text('伝説の予想屋'), findsOneWidget);
      expect(find.text('★☆☆'), findsOneWidget);
      expect(find.text('★★★'), findsOneWidget);
      expect(find.textContaining('30コインで聞く'), findsOneWidget);
      expect(find.textContaining('150コインで聞く'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tip-veteran')));
      expect(tipsBought, ['veteran']);
    });

    testWidgets('聞いた予想は ◎○▲ とひとことで出て、出走表の馬にも印が付く。同じ予想屋はもう聞けない', (tester) async {
      const tips = [Tip(id: 'paper', marks: [2, 5, 1], comment: '今日はこの馬で決まり!')];
      await pump(tester, bettingView(sellers: tipsters, tips: tips), table: odds);
      // 聞いた予想があるときは、最初から開いている
      expect(find.text('競馬新聞'), findsOneWidget);
      expect(find.textContaining('◎2 ○5 ▲1'), findsOneWidget);
      expect(find.textContaining('今日はこの馬で決まり!'), findsOneWidget);
      expect(find.byKey(const Key('tip-paper')), findsNothing);
      expect(find.byKey(const Key('tip-master')), findsOneWidget);
      // 出走表の 2 番に ◎、5 番に ○、1 番に ▲
      expect(find.byKey(const Key('marks-2')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('marks-2'))).data, contains('◎'));
      expect(tester.widget<Text>(find.byKey(const Key('marks-5'))).data, contains('○'));
      expect(tester.widget<Text>(find.byKey(const Key('marks-1'))).data, contains('▲'));
      expect(find.byKey(const Key('marks-3')), findsNothing);
    });

    testWidgets('料金を払えない(馬券を買った残りが足りない)予想屋は聞けない', (tester) async {
      const tickets = [Ticket(id: 't1', type: BetType.win, horses: [2], amount: 900, odds: 5.1)];
      await pump(tester, bettingView(coins: 1000, tickets: tickets, sellers: tipsters), table: odds);
      await open(tester);
      // 残り 100: 30 と 80 は聞ける、150 は聞けない
      expect(tester.widget<FilledButton>(find.byKey(const Key('tip-paper'))).onPressed, isNotNull);
      expect(tester.widget<FilledButton>(find.byKey(const Key('tip-veteran'))).onPressed, isNotNull);
      expect(tester.widget<FilledButton>(find.byKey(const Key('tip-master'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('tip-master')));
      expect(tipsBought, isEmpty);
    });

    testWidgets('払ったあとに 10 コイン残らない予想屋は聞けない', (tester) async {
      await pump(tester, bettingView(coins: 39, sellers: tipsters), table: odds);
      await open(tester);
      expect(tester.widget<FilledButton>(find.byKey(const Key('tip-paper'))).onPressed, isNull); // 39 - 30 = 9
      await pump(tester, bettingView(coins: 40, sellers: tipsters), table: odds);
      expect(tester.widget<FilledButton>(find.byKey(const Key('tip-paper'))).onPressed, isNotNull); // 40 - 30 = 10
    });

    testWidgets('聞くボタンは 1 回押すと押せなくなる(二重に送らない)', (tester) async {
      await pump(tester, bettingView(sellers: tipsters), table: odds);
      await open(tester);
      await tester.tap(find.byKey(const Key('tip-paper')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tip-paper')));
      await tester.pump();
      expect(tipsBought, ['paper']);
      expect(tester.widget<FilledButton>(find.byKey(const Key('tip-paper'))).onPressed, isNull);
      // ほかの予想屋は押せる
      expect(tester.widget<FilledButton>(find.byKey(const Key('tip-veteran'))).onPressed, isNotNull);
      // サーバーから何も返らなかったときは、少し待つとまた押せる
      await tester.pump(const Duration(seconds: 4));
      expect(tester.widget<FilledButton>(find.byKey(const Key('tip-paper'))).onPressed, isNotNull);
    });

    testWidgets('予想屋のいないサーバー(古い版)では、予想屋の欄を出さない', (tester) async {
      await pump(tester, bettingView(), table: odds);
      expect(find.textContaining('予想屋'), findsNothing);
    });

    testWidgets('幅 320 の画面で 3 人とも聞いた状態でも、はみ出さない', (tester) async {
      const tips = [
        Tip(id: 'paper', marks: [2, 5, 1], comment: '◎○▲の 3 頭でまず間違いない。'),
        Tip(id: 'veteran', marks: [5, 2, 8], comment: 'パドックの気配は◎がいちばん。'),
        Tip(id: 'master', marks: [2, 8, 5], comment: '人気より中身。◎を信じなさい。'),
      ];
      await pump(tester, bettingView(sellers: tipsters, tips: tips), table: odds, size: const Size(320, 640), ratio: 1.0);
      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(find.byKey(const Key('marks-2'))).data, contains('◎'));
    });
  });

  testWidgets('出走表に、調子・表情・脚質・近走・距離と馬場が出る', (tester) async {
    const detailed = [
      HorseInfo(no: 1, name: 'ハヤテオー', odds: 2.4, sex: '牡', age: 4, weight: 482, weightDiff: 2, style: '先行',
          recent: [1, 3, 2], pop: 1, cond: 5, mood: 'fired', hasDetails: true),
      HorseInfo(no: 2, name: 'ミドリノカゼ', odds: 5.1, sex: '牝', age: 3, weight: 446, weightDiff: -6, style: '追込',
          recent: [5, 2, 8], pop: 2, cond: 2, mood: 'sleepy', hasDetails: true),
    ];
    const view = RoomView(
      phase: Phase.betting, raceNo: 1, totalRaces: 5, serverNow: 0, betCount: 0, onlineCount: 1,
      horses: detailed, players: [], bets: [],
      course: CourseInfo(distance: 1600, going: '稍重'),
      me: Me(id: 'a', name: 'たろう', coins: 1000, rank: 1),
    );
    await pump(tester, view);
    expect(find.textContaining('芝 1600m'), findsOneWidget);
    expect(find.textContaining('稍重'), findsOneWidget);
    expect(find.text('絶好調'), findsOneWidget);
    expect(find.text('不調'), findsOneWidget);
    expect(find.textContaining('牡4'), findsOneWidget);
    expect(find.textContaining('482kg(+2)'), findsOneWidget);
    expect(find.textContaining('先行'), findsOneWidget);
    expect(find.textContaining('1-3-2'), findsOneWidget);
    final faces = tester.widgetList<HorseFace>(find.byType(HorseFace)).map((f) => f.mood).toList();
    expect(faces, ['fired', 'sleepy']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('幅 320 の画面でも、はみ出さず、近走などの詳細が切れずに読める', (tester) async {
    const worst = HorseInfo(no: 8, name: 'ワクワクジャーニー', odds: 25.9, sex: '牡', age: 4, weight: 518, weightDiff: -10,
        style: '追込', recent: [10, 12, 11], pop: 8, cond: 1, mood: 'restless', hasDetails: true);
    final tickets = [
      for (var h = 1; h <= 8; h++) Ticket(id: 'w$h', type: BetType.trifecta, horses: [h, h % 8 + 1, (h + 1) % 8 + 1], amount: 10, odds: 999.9),
    ];
    final view = bettingView(tickets: tickets, field: [worst, ...horses.skip(1)]);
    await pump(tester, view, table: odds, size: const Size(320, 640), ratio: 1.0);
    expect(tester.takeException(), isNull);
    final details = tester.renderObject<RenderParagraph>(find.byKey(const Key('details-8')));
    expect(details.didExceedMaxLines, false);
    expect(find.textContaining('近走 10-12-11'), findsOneWidget);
    for (final label in ['単勝', '複勝', '馬連', '3連単']) {
      await chooseType(tester, label);
      expect(tester.takeException(), isNull, reason: label);
    }
  });
}
