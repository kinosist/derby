import 'dart:async';
import 'dart:convert';

import 'package:derby/src/protocol.dart';
import 'package:derby/src/room_client.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeTransport implements Transport {
  final _incoming = StreamController<String>();
  final sent = <Map<String, dynamic>>[];
  bool closedByClient = false;
  int? _closeCode;

  @override
  Stream<String> get messages => _incoming.stream;
  /// null なら即座に接続完了。設定すると、その Future が終わるまで接続中のままになる。
  Future<void>? readyFuture;
  @override
  Future<void> get ready => readyFuture ?? Future.value();
  @override
  int? get closeCode => _closeCode;
  @override
  void send(String text) => sent.add(jsonDecode(text) as Map<String, dynamic>);
  @override
  Future<void> close() async {
    closedByClient = true;
    if (!_incoming.isClosed) await _incoming.close();
  }

  void receive(Map<String, dynamic> message) => _incoming.add(jsonEncode(message));
  void serverCloses([int code = 1006]) {
    _closeCode = code;
    _incoming.close();
  }
}

Map<String, dynamic> stateMessage({String id = 'id-1', String name = 'たろう', int coins = 1000, int serverNow = 0}) => {
      't': 'state',
      'phase': 'lobby',
      'raceNo': 0,
      'totalRaces': 5,
      'serverNow': serverNow,
      'horses': [],
      'players': [
        {'id': id, 'name': name, 'coins': coins, 'online': true, 'rank': 1, 'hasBet': false},
      ],
      'betCount': 0,
      'onlineCount': 1,
      'me': {'id': id, 'name': name, 'coins': coins, 'rank': 1, 'bet': null, 'lastResult': null},
      'race': null,
      'bets': [],
      'isAdmin': false,
    };

void main() {
  late List<FakeTransport> transports;
  late SharedPreferences prefs;

  /// これから作られる接続が、応答なしで固まるようにする
  var hang = false;
  setUp(() => hang = false);

  Future<RoomClient> makeClient(Map<String, Object> saved, {int Function()? nowMs}) async {
    SharedPreferences.setMockInitialValues(saved);
    prefs = await SharedPreferences.getInstance();
    transports = [];
    return RoomClient(
      url: 'ws://test/ws',
      prefs: prefs,
      nowMs: nowMs,
      connect: (uri) {
        final t = FakeTransport();
        if (hang) t.readyFuture = Completer<void>().future;
        transports.add(t);
        return t;
      },
    );
  }

  /// fakeAsync の中で、たまっている非同期処理を進める
  void settle(FakeAsync async) => async.flushMicrotasks();

  test('初回は id を作って保存し、名前がなければ接続しない', () async {
    final client = await makeClient({});
    await client.init();
    expect(prefs.getString('derby.id'), matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(client.savedName, isNull);
    expect(transports, isEmpty);
    expect(client.status, ConnStatus.disconnected);
  });

  test('join で接続して参加を送り、state を受けたら名前を保存する', () {
    fakeAsync((async) {
      late RoomClient client;
      makeClient({'derby.id': 'id-1'}).then((c) => client = c);
      settle(async);
      client.init();
      settle(async);
      client.join('  たろう ');
      settle(async);
      expect(transports.length, 1);
      expect(transports[0].sent, [
        {'t': 'join', 'id': 'id-1', 'name': 'たろう'},
      ]);
      expect(client.status, ConnStatus.connected);
      expect(client.view, isNull);

      transports[0].receive(stateMessage());
      settle(async);
      expect(client.view!.me!.name, 'たろう');
      expect(client.view!.phase, Phase.lobby);
      expect(client.savedName, 'たろう');
      expect(prefs.getString('derby.name'), 'たろう');
    });
  });

  test('保存済みの名前があれば init で自動的に参加する', () {
    fakeAsync((async) {
      late RoomClient client;
      makeClient({'derby.id': 'id-1', 'derby.name': 'たろう'}).then((c) => client = c);
      settle(async);
      client.init();
      settle(async);
      expect(transports.single.sent.single, {'t': 'join', 'id': 'id-1', 'name': 'たろう'});
    });
  });

  test('サーバーが別の id を振ったら、その id を保存する', () {
    fakeAsync((async) {
      late RoomClient client;
      makeClient({'derby.id': 'id-1', 'derby.name': 'たろう'}).then((c) => client = c);
      settle(async);
      client.init();
      settle(async);
      transports[0].receive(stateMessage(id: 'server-id'));
      settle(async);
      expect(prefs.getString('derby.id'), 'server-id');
    });
  });

  test('切断されたら 1 秒後に再接続して参加し直す', () {
    fakeAsync((async) {
      late RoomClient client;
      makeClient({'derby.id': 'id-1', 'derby.name': 'たろう'}).then((c) => client = c);
      settle(async);
      client.init();
      settle(async);
      transports[0].receive(stateMessage());
      settle(async);

      transports[0].serverCloses();
      settle(async);
      expect(client.status, isNot(ConnStatus.connected));
      expect(client.view, isNotNull); // 画面は残す
      async.elapse(const Duration(milliseconds: 900));
      expect(transports.length, 1);
      async.elapse(const Duration(milliseconds: 200));
      expect(transports.length, 2);
      expect(transports[1].sent.single, {'t': 'join', 'id': 'id-1', 'name': 'たろう'});
      expect(client.status, ConnStatus.connected);
    });
  });

  test('再接続の間隔は 1 秒 → 2 秒 → 4 秒 → 最大 5 秒', () {
    fakeAsync((async) {
      late RoomClient client;
      makeClient({'derby.id': 'id-1', 'derby.name': 'たろう'}).then((c) => client = c);
      settle(async);
      client.init();
      settle(async);
      final waits = <int>[];
      for (var i = 0; i < 5; i++) {
        final count = transports.length;
        transports.last.serverCloses();
        settle(async);
        var waited = 0;
        while (transports.length == count) {
          async.elapse(const Duration(milliseconds: 100));
          waited += 100;
        }
        waits.add(waited);
      }
      expect(waits, [1000, 2000, 4000, 5000, 5000]);
    });
  });

  test('接続の試行が応答なしで固まっても、8 秒で打ち切って再試行する', () {
    fakeAsync((async) {
      late RoomClient client;
      makeClient({'derby.id': 'id-1', 'derby.name': 'たろう'}).then((c) => client = c);
      settle(async);
      hang = true;
      client.init();
      settle(async);
      expect(transports.length, 1);
      expect(client.status, ConnStatus.connecting);
      async.elapse(const Duration(seconds: 7));
      expect(transports.length, 1);
      // 8 秒で打ち切り、1 秒後に次の試行。今度はつながる。
      hang = false;
      async.elapse(const Duration(seconds: 3));
      expect(transports[0].closedByClient, true);
      expect(transports.length, 2);
      expect(client.status, ConnStatus.connected);
      expect(transports[1].sent.single, {'t': 'join', 'id': 'id-1', 'name': 'たろう'});
    });
  });

  test('接続に失敗(例外)しても再試行を続ける', () {
    fakeAsync((async) {
      late RoomClient client;
      makeClient({'derby.id': 'id-1', 'derby.name': 'たろう'}).then((c) => client = c);
      settle(async);
      client.init();
      settle(async);
      transports[0].receive(stateMessage());
      settle(async);
      transports[0].serverCloses();
      settle(async);
      // 再試行が 3 回続けて失敗する
      for (var i = 0; i < 3; i++) {
        final count = transports.length;
        async.elapse(const Duration(seconds: 6));
        expect(transports.length, greaterThan(count), reason: '再試行 ${i + 1} 回目');
        transports.last.readyFuture = null;
        transports.last.serverCloses();
        settle(async);
      }
      async.elapse(const Duration(seconds: 6));
      expect(client.status, ConnStatus.connected);
    });
  });

  test('name_taken は保存名を消して参加画面に戻し、再接続しない', () {
    fakeAsync((async) {
      late RoomClient client;
      makeClient({'derby.id': 'id-1', 'derby.name': 'たろう'}).then((c) => client = c);
      settle(async);
      client.init();
      settle(async);
      transports[0].receive({'t': 'error', 'code': 'name_taken', 'message': 'その名前は使われています'});
      settle(async);
      expect(client.lastError, 'その名前は使われています');
      expect(client.savedName, isNull);
      expect(prefs.getString('derby.name'), isNull);
      expect(client.view, isNull);
      async.elapse(const Duration(seconds: 10));
      expect(transports.length, 1);
    });
  });

  test('kicked は参加画面に戻し、再接続しない', () {
    fakeAsync((async) {
      late RoomClient client;
      makeClient({'derby.id': 'id-1', 'derby.name': 'たろう'}).then((c) => client = c);
      settle(async);
      client.init();
      settle(async);
      transports[0].receive(stateMessage());
      settle(async);
      transports[0].receive({'t': 'error', 'code': 'kicked', 'message': '先生が退出させました'});
      transports[0].serverCloses(4001);
      settle(async);
      expect(client.view, isNull);
      expect(client.savedName, isNull);
      expect(client.lastError, '先生が退出させました');
      async.elapse(const Duration(seconds: 10));
      expect(transports.length, 1);
    });
  });

  test('別の接続に置き換えられた(4000)ら、再接続を繰り返さない', () {
    fakeAsync((async) {
      late RoomClient client;
      makeClient({'derby.id': 'id-1', 'derby.name': 'たろう'}).then((c) => client = c);
      settle(async);
      client.init();
      settle(async);
      transports[0].receive(stateMessage());
      settle(async);
      transports[0].serverCloses(4000);
      settle(async);
      async.elapse(const Duration(seconds: 10));
      expect(transports.length, 1);
      expect(client.view, isNull);
      expect(client.lastError, isNotNull);
    });
  });

  test('賭けと取り消しを送る。bad_bet は lastError に出て、次の操作で消える', () {
    fakeAsync((async) {
      late RoomClient client;
      makeClient({'derby.id': 'id-1', 'derby.name': 'たろう'}).then((c) => client = c);
      settle(async);
      client.init();
      settle(async);
      transports[0].receive(stateMessage());
      settle(async);
      client.placeTicket(BetType.win, [2], 300);
      expect(transports[0].sent.last, {'t': 'bet', 'horse': 2, 'amount': 300});
      transports[0].receive({'t': 'error', 'code': 'bad_bet', 'message': 'その賭けはできません'});
      settle(async);
      expect(client.lastError, 'その賭けはできません');
      expect(client.view, isNotNull);
      client.cancelTicket('legacy');
      expect(transports[0].sent.last, {'t': 'cancelBet'});
      expect(client.lastError, isNull);
    });
  });

  test('新しいサーバー(raceKey あり)には、種類と馬を指定して買い、id を指定して取り消す', () {
    fakeAsync((async) {
      late RoomClient client;
      makeClient({'derby.id': 'id-1', 'derby.name': 'たろう'}).then((c) => client = c);
      settle(async);
      client.init();
      settle(async);
      transports[0].receive({...stateMessage(), 'phase': 'betting', 'raceNo': 1, 'raceKey': '1-abc'});
      settle(async);
      expect(client.oddsTable, isNull);
      transports[0].receive({'t': 'odds', 'raceKey': '1-abc', 'place': [1.2, 1.5], 'quinella': {'1-2': 4.5}, 'trifecta': {'1-2-3': 30.5}});
      settle(async);
      expect(client.oddsTable!.raceKey, '1-abc');
      expect(client.oddsTable!.place, [1.2, 1.5]);

      client.placeTicket(BetType.quinella, [5, 3], 200);
      expect(transports[0].sent.last, {'t': 'bet', 'type': 'quinella', 'horses': [5, 3], 'amount': 200});
      client.placeTicket(BetType.win, [2], 100);
      expect(transports[0].sent.last, {'t': 'bet', 'type': 'win', 'horses': [2], 'amount': 100});
      client.cancelTicket('t7');
      expect(transports[0].sent.last, {'t': 'cancelBet', 'id': 't7'});
    });
  });

  test('サーバーとの時計のずれを保つ', () {
    fakeAsync((async) {
      late RoomClient client;
      makeClient({'derby.id': 'id-1', 'derby.name': 'たろう'}, nowMs: () => 10000).then((c) => client = c);
      settle(async);
      client.init();
      settle(async);
      transports[0].receive(stateMessage(serverNow: 12500));
      settle(async);
      expect(client.clockOffsetMs, 2500);
      expect(client.serverNowMs(), 12500);
    });
  });

  test('leave は保存名を消して切断する', () {
    fakeAsync((async) {
      late RoomClient client;
      makeClient({'derby.id': 'id-1', 'derby.name': 'たろう'}).then((c) => client = c);
      settle(async);
      client.init();
      settle(async);
      transports[0].receive(stateMessage());
      settle(async);
      client.leave();
      settle(async);
      expect(transports[0].closedByClient, true);
      expect(client.view, isNull);
      expect(prefs.getString('derby.name'), isNull);
      async.elapse(const Duration(seconds: 10));
      expect(transports.length, 1);
    });
  });

  test('壊れたメッセージは無視する', () {
    fakeAsync((async) {
      late RoomClient client;
      makeClient({'derby.id': 'id-1', 'derby.name': 'たろう'}).then((c) => client = c);
      settle(async);
      client.init();
      settle(async);
      transports[0]._incoming.add('not json');
      transports[0]._incoming.add('[1]');
      transports[0].receive({'t': 'state', 'phase': 'unknown-phase'});
      settle(async);
      expect(client.view, isNull);
      transports[0].receive(stateMessage());
      settle(async);
      expect(client.view, isNotNull);
    });
  });

  test('debugSetView で view と時計を差し込める', () async {
    final client = await makeClient({}, nowMs: () => 1000);
    client.debugSetView(RoomView.fromJson(stateMessage()), clockOffsetMs: 500);
    expect(client.view!.me!.name, 'たろう');
    expect(client.serverNowMs(), 1500);
  });
}
