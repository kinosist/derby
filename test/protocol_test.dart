import 'dart:convert';

import 'package:derby/src/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

RoomView parse(String json) => RoomView.fromJson(jsonDecode(json) as Map<String, dynamic>);

const horsesJson = '''
[{"no":1,"name":"ハヤテオー","odds":2.4},{"no":2,"name":"ミドリノカゼ","odds":5.1},
 {"no":3,"name":"アサヤケゴー","odds":12},{"no":4,"name":"ツキアカリ","odds":8.3},
 {"no":5,"name":"ノンビリヤ","odds":20.5},{"no":6,"name":"ガンバルゾー","odds":6},
 {"no":7,"name":"アカトンボ","odds":9.9},{"no":8,"name":"サクラフブキ","odds":30}]''';

const playersJson = '''
[{"id":"a","name":"たろう","coins":1400,"online":true,"rank":1,"hasBet":false},
 {"id":"b","name":"はなこ","coins":900,"online":false,"rank":2,"hasBet":false}]''';

void main() {
  test('賭け受付中のスナップショット', () {
    final v = parse('''
{"t":"state","phase":"betting","raceNo":3,"totalRaces":5,"serverNow":1700000000123,
 "horses":$horsesJson,"players":$playersJson,"betCount":1,"onlineCount":1,
 "me":{"id":"a","name":"たろう","coins":1400,"rank":1,"bet":{"horse":2,"amount":300},"lastResult":null},
 "race":null,"bets":[],"isAdmin":false}''');
    expect(v.phase, Phase.betting);
    expect(v.raceNo, 3);
    expect(v.totalRaces, 5);
    expect(v.serverNow, 1700000000123);
    expect(v.betCount, 1);
    expect(v.onlineCount, 1);
    expect(v.horses.length, 8);
    expect(v.horses[1].no, 2);
    expect(v.horses[1].name, 'ミドリノカゼ');
    expect(v.horses[1].odds, 5.1);
    expect(v.horses[2].odds, 12.0); // 整数で届いても double
    expect(v.players.length, 2);
    expect(v.players[1].name, 'はなこ');
    expect(v.players[1].coins, 900);
    expect(v.players[1].online, false);
    expect(v.players[1].rank, 2);
    expect(v.me!.id, 'a');
    expect(v.me!.coins, 1400);
    expect(v.me!.rank, 1);
    expect(v.me!.bet!.horse, 2);
    expect(v.me!.bet!.amount, 300);
    expect(v.me!.lastResult, isNull);
    expect(v.race, isNull);
    expect(v.bets, isEmpty);
  });

  test('レース中は race が入る', () {
    final times = List.generate(8, (h) => List.generate(11, (i) => i * (1600 + h * 20)));
    final v = parse('''
{"t":"state","phase":"racing","raceNo":1,"totalRaces":5,"serverNow":5000,
 "horses":$horsesJson,"players":$playersJson,"betCount":0,"onlineCount":1,
 "me":{"id":"a","name":"たろう","coins":1100,"rank":1,"bet":null,"lastResult":null},
 "race":{"startedAt":4000,"durationMs":20000,"order":[1,2,3,4,5,6,7,8],"times":${jsonEncode(times)}},
 "bets":[],"isAdmin":false}''');
    expect(v.phase, Phase.racing);
    expect(v.race!.startedAt, 4000);
    expect(v.race!.durationMs, 20000);
    expect(v.race!.order, [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(v.race!.times.length, 8);
    expect(v.race!.times[7][10], 17400);
    expect(v.me!.bet, isNull);
  });

  test('結果では bets と lastResult が入る', () {
    final v = parse('''
{"t":"state","phase":"result","raceNo":1,"totalRaces":5,"serverNow":1,
 "horses":$horsesJson,"players":$playersJson,"betCount":1,"onlineCount":1,
 "me":{"id":"a","name":"たろう","coins":2630,"rank":1,"bet":{"horse":2,"amount":300},
       "lastResult":{"horse":2,"amount":300,"won":true,"delta":1230}},
 "race":{"startedAt":0,"durationMs":20000,"order":[2,1,3,4,5,6,7,8],"times":[]},
 "bets":[{"playerId":"a","horse":2,"amount":300,"delta":1230},{"playerId":"b","horse":1,"amount":100,"delta":-100}],
 "isAdmin":false}''');
    expect(v.phase, Phase.result);
    expect(v.me!.lastResult!.won, true);
    expect(v.me!.lastResult!.delta, 1230);
    expect(v.me!.lastResult!.horse, 2);
    expect(v.me!.lastResult!.amount, 300);
    expect(v.bets.length, 2);
    expect(v.bets[1].playerId, 'b');
    expect(v.bets[1].horse, 1);
    expect(v.bets[1].amount, 100);
    expect(v.bets[1].delta, -100);
  });

  test('me が null、phase が final、未知のキーがあっても読める', () {
    final v = parse('''
{"t":"state","phase":"final","raceNo":5,"totalRaces":5,"serverNow":1,
 "horses":[],"players":$playersJson,"betCount":0,"onlineCount":1,
 "me":null,"bets":[],"isAdmin":false,"somethingNew":{"x":1}}''');
    expect(v.phase, Phase.finalResult);
    expect(v.me, isNull);
    expect(v.race, isNull); // race キー自体がない
    expect(v.horses, isEmpty);
  });

  test('出走馬の詳細と、距離・馬場を読む', () {
    final v = parse('''
{"phase":"betting","raceNo":1,"totalRaces":5,"serverNow":0,"players":[],"betCount":0,"onlineCount":0,"me":null,"race":null,"bets":[],
 "course":{"distance":2400,"going":"稍重"},
 "horses":[{"no":1,"name":"ハヤテオー","odds":2.4,"sex":"牡","age":4,"weight":482,"weightDiff":-6,
            "style":"追込","recent":[1,3,12],"pop":1,"cond":5,"mood":"fired"}]}''');
    expect(v.course!.distance, 2400);
    expect(v.course!.going, '稍重');
    final h = v.horses.single;
    expect(h.sex, '牡');
    expect(h.age, 4);
    expect(h.weight, 482);
    expect(h.weightDiff, -6);
    expect(h.style, '追込');
    expect(h.recent, [1, 3, 12]);
    expect(h.pop, 1);
    expect(h.cond, 5);
    expect(h.mood, 'fired');
    expect(h.hasDetails, true);
  });

  test('古いサーバー(詳細なし)の出走馬も読める', () {
    final v = parse('''
{"phase":"betting","raceNo":1,"totalRaces":5,"serverNow":0,"players":[],"betCount":0,"onlineCount":0,"me":null,"race":null,"bets":[],
 "horses":[{"no":1,"name":"ハヤテオー","odds":2.4}]}''');
    expect(v.course, isNull);
    final h = v.horses.single;
    expect(h.hasDetails, false);
    expect(h.cond, 3);
    expect(h.mood, 'calm');
    expect(h.recent, isEmpty);
    expect(h.style, '');
  });

  test('phase の対応', () {
    for (final e in {'lobby': Phase.lobby, 'betting': Phase.betting, 'racing': Phase.racing, 'result': Phase.result}.entries) {
      final v = parse('{"phase":"${e.key}","raceNo":0,"totalRaces":5,"serverNow":0,"horses":[],"players":[],"betCount":0,"onlineCount":0,"me":null,"race":null,"bets":[]}');
      expect(v.phase, e.value);
    }
  });
}
