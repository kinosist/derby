import 'dart:async';

import 'package:derby/main.dart';
import 'package:derby/src/protocol.dart';
import 'package:derby/src/room_client.dart';
import 'package:derby/src/widgets/horse_colors.dart';
import 'package:derby/src/widgets/leaderboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 応答のないサーバー(接続の試行が終わらない)
class HangingTransport implements Transport {
  final _incoming = StreamController<String>();
  @override
  Stream<String> get messages => _incoming.stream;
  @override
  Future<void> get ready => Completer<void>().future;
  @override
  int? get closeCode => null;
  @override
  void send(String text) {}
  @override
  Future<void> close() async {
    if (!_incoming.isClosed) await _incoming.close();
  }
}

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('初めての参加でサーバーにつながらないとき、「再接続中…」が出る', (tester) async {
    phone(tester);
    SharedPreferences.setMockInitialValues({});
    final client = RoomClient(
      url: 'ws://test/ws',
      prefs: await SharedPreferences.getInstance(),
      connect: (_) => HangingTransport(),
    );
    await client.init();
    await tester.pumpWidget(DerbyApp(client: client));
    expect(find.text('再接続中…'), findsNothing); // まだ参加しようとしていない
    expect(client.wantsRoom, false);

    await tester.enterText(find.byType(TextField), 'たろう');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '参加'));
    await tester.pump();
    expect(client.wantsRoom, true);
    expect(find.text('再接続中…'), findsOneWidget);

    // 打ち切りと再試行を繰り返しても表示は出たまま
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('再接続中…'), findsOneWidget);

    client.leave();
    await tester.pump();
    expect(client.wantsRoom, false);
    expect(find.text('再接続中…'), findsNothing);
    client.dispose();
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('結果の順位表に、全員の賭けた馬と増減が出る', (tester) async {
    phone(tester);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Leaderboard(
          meId: 'a',
          players: [
            PlayerInfo(id: 'a', name: 'たろう', coins: 2230, rank: 1, online: true),
            PlayerInfo(id: 'pub-b', name: 'はなこ', coins: 900, rank: 2, online: true),
            PlayerInfo(id: 'pub-c', name: 'じろう', coins: 900, rank: 2, online: true),
          ],
          bets: [
            PublicBet(playerId: 'a', horse: 2, amount: 300, delta: 1230),
            PublicBet(playerId: 'pub-b', horse: 7, amount: 100, delta: -100),
          ],
        ),
      ),
    ));
    expect(find.text('+1,230'), findsOneWidget);
    expect(find.text('−100'), findsOneWidget);
    final badges = tester.widgetList<HorseBadge>(find.byType(HorseBadge)).map((b) => b.no).toList();
    expect(badges, [2, 7]); // 賭けなかった「じろう」には何も出ない
    expect(tester.takeException(), isNull);
  });

  testWidgets('賭けの一覧を渡さなければ、順位表は名前と所持金だけ', (tester) async {
    phone(tester);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Leaderboard(
          players: [PlayerInfo(id: 'a', name: 'たろう', coins: 1000, rank: 1, online: true)],
        ),
      ),
    ));
    expect(find.byType(HorseBadge), findsNothing);
    expect(find.text('1,000'), findsOneWidget);
  });
}
