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
    // 古いサーバーの bet は、単勝 1 点の馬券として読む
    expect(v.me!.tickets.single.type, BetType.win);
    expect(v.me!.tickets.single.horses, [2]);
    expect(v.me!.tickets.single.amount, 300);
    expect(v.me!.results, isNull);
    expect(v.raceKey, isNull);
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
    expect(v.me!.tickets, isEmpty);
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
    // 古いサーバーの lastResult は、単勝 1 点の結果として読む
    expect(v.me!.results!.delta, 1230);
    expect(v.me!.results!.staked, 300);
    expect(v.me!.results!.tickets.single.won, true);
    expect(v.me!.results!.tickets.single.horses, [2]);
    expect(v.me!.results!.tickets.single.payout, 1530);
    expect(v.bets[1].tickets, isEmpty);
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

  test('馬券と結果(新しい形式)を読む', () {
    final v = parse('''
{"phase":"result","raceNo":2,"totalRaces":5,"serverNow":0,"raceKey":"2-abc","horses":[],"players":[],"betCount":0,"onlineCount":0,"race":null,
 "me":{"id":"a","name":"たろう","coins":900,"rank":1,
   "bet":{"horse":3,"amount":100},"lastResult":{"horse":3,"amount":400,"won":true,"delta":250},
   "tickets":[{"id":"t1","type":"win","horses":[3],"amount":100,"odds":2.5},
              {"id":"t2","type":"quinella","horses":[3,5],"amount":100,"odds":18},
              {"id":"t3","type":"trifecta","horses":[4,1,2],"amount":100,"odds":141.2},
              {"id":"t4","type":"place","horses":[2],"amount":100,"odds":1.4},
              {"id":"t5","type":"superfecta","horses":[1,2,3,4],"amount":100,"odds":9}],
   "results":{"staked":400,"delta":250,"tickets":[
              {"id":"t1","type":"win","horses":[3],"amount":100,"odds":2.5,"won":true,"payout":250},
              {"id":"t2","type":"quinella","horses":[3,5],"amount":100,"odds":18,"won":false,"payout":0}]}},
 "bets":[{"playerId":"p","horse":3,"amount":400,"delta":250,
          "tickets":[{"type":"place","horses":[2],"amount":100,"odds":1.4,"won":true,"payout":140}]}]}''');
    expect(v.raceKey, '2-abc');
    final t = v.me!.tickets;
    expect(t.map((x) => x.type), [BetType.win, BetType.quinella, BetType.trifecta, BetType.place]); // 知らない種類は捨てる
    expect(t[1].horses, [3, 5]);
    expect(t[1].odds, 18.0);
    expect(t[2].id, 't3');
    expect(t[2].horses, [4, 1, 2]);
    expect(t[2].odds, 141.2);
    final r = v.me!.results!;
    expect(r.staked, 400);
    expect(r.delta, 250);
    expect(r.tickets.map((x) => x.won), [true, false]);
    expect(r.tickets[0].payout, 250);
    expect(v.bets.single.tickets.single.type, BetType.place);
    expect(v.bets.single.tickets.single.won, true);
    expect(v.bets.single.tickets.single.payout, 140);
  });

  test('馬券の表示名', () {
    expect(ticketLabel(BetType.win, [3]), '単勝 3');
    expect(ticketLabel(BetType.place, [3]), '複勝 3');
    expect(ticketLabel(BetType.quinella, [3, 5]), '馬連 3-5');
    expect(ticketLabel(BetType.trifecta, [4, 1, 2]), '3連単 4→1→2');
  });

  test('倍率表を読み、馬券の倍率を引ける', () {
    final table = OddsTable.fromJson(jsonDecode('''
{"t":"odds","raceKey":"2-abc","place":[1.2,1.4,3],"quinella":{"1-2":4.5,"2-3":18},"trifecta":{"1-2-3":30.5,"3-2-1":999.9}}''') as Map<String, dynamic>);
    expect(table.raceKey, '2-abc');
    final field = [const HorseInfo(no: 1, name: 'a', odds: 2.4), const HorseInfo(no: 2, name: 'b', odds: 5.1)];
    expect(table.oddsFor(BetType.win, [2], field), 5.1);
    expect(table.oddsFor(BetType.place, [3], field), 3.0);
    expect(table.oddsFor(BetType.quinella, [3, 2], field), 18.0); // 順不同
    expect(table.oddsFor(BetType.trifecta, [3, 2, 1], field), 999.9);
    expect(table.oddsFor(BetType.trifecta, [1, 3, 2], field), isNull); // 表にない
    expect(table.oddsFor(BetType.place, [9], field), isNull);
    expect(table.oddsFor(BetType.quinella, [1], field), isNull); // 頭数が足りない
    expect(winOdds([2], field), 5.1);
    expect(winOdds([7], field), isNull);
  });

  test('予想屋の一覧・買った予想・結果を読む。古いサーバー(項目なし)でも読める', () {
    final v = parse('''
{"phase":"result","raceNo":1,"totalRaces":5,"serverNow":0,"horses":[],"players":[],"betCount":0,"onlineCount":0,"race":null,"bets":[],
 "tipsters":[{"id":"paper","name":"競馬新聞","price":30,"stars":1},{"id":"master","name":"伝説の予想屋","price":150,"stars":3}],
 "tipResults":[{"id":"paper","name":"競馬新聞","marks":[2,5,1],"hit":true},{"id":"master","name":"伝説の予想屋","marks":[5,2,8],"hit":false}],
 "me":{"id":"a","name":"たろう","coins":900,"rank":1,"tickets":[],"results":null,
       "tips":[{"id":"paper","marks":[2,5,1],"comment":"今日はこの馬で決まり!"}]}}''');
    expect(v.tipsters.map((t) => [t.id, t.name, t.price, t.stars]), [['paper', '競馬新聞', 30, 1], ['master', '伝説の予想屋', 150, 3]]);
    expect(v.me!.tips.single.id, 'paper');
    expect(v.me!.tips.single.marks, [2, 5, 1]);
    expect(v.me!.tips.single.comment, '今日はこの馬で決まり!');
    expect(v.tipResults.map((t) => [t.name, t.marks, t.hit]), [['競馬新聞', [2, 5, 1], true], ['伝説の予想屋', [5, 2, 8], false]]);

    final old = parse('{"phase":"betting","raceNo":1,"totalRaces":5,"serverNow":0,"horses":[],"players":[],"betCount":0,"onlineCount":0,"race":null,"bets":[],"me":{"id":"a","name":"たろう","coins":900,"rank":1}}');
    expect(old.tipsters, isEmpty);
    expect(old.tipResults, isEmpty);
    expect(old.me!.tips, isEmpty);
  });

  test('phase の対応', () {
    for (final e in {'lobby': Phase.lobby, 'betting': Phase.betting, 'racing': Phase.racing, 'result': Phase.result}.entries) {
      final v = parse('{"phase":"${e.key}","raceNo":0,"totalRaces":5,"serverNow":0,"horses":[],"players":[],"betCount":0,"onlineCount":0,"me":null,"race":null,"bets":[]}');
      expect(v.phase, e.value);
    }
  });
}
