// サーバーから届く状態スナップショットの型。

enum Phase { lobby, betting, racing, result, finalResult }

Phase _phaseFrom(Object? raw) => switch (raw) {
      'lobby' => Phase.lobby,
      'betting' => Phase.betting,
      'racing' => Phase.racing,
      'result' => Phase.result,
      'final' => Phase.finalResult,
      _ => throw FormatException('unknown phase: $raw'),
    };

List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) f) =>
    raw is List ? [for (final e in raw) f(e as Map<String, dynamic>)] : <T>[];

class HorseInfo {
  const HorseInfo({required this.no, required this.name, required this.odds});
  final int no;
  final String name;
  final double odds;

  factory HorseInfo.fromJson(Map<String, dynamic> j) =>
      HorseInfo(no: j['no'] as int, name: j['name'] as String, odds: (j['odds'] as num).toDouble());
}

class PlayerInfo {
  const PlayerInfo({required this.id, required this.name, required this.coins, required this.rank, required this.online});
  final String id;
  final String name;
  final int coins;
  final int rank;
  final bool online;

  factory PlayerInfo.fromJson(Map<String, dynamic> j) => PlayerInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        coins: j['coins'] as int,
        rank: j['rank'] as int,
        online: j['online'] as bool,
      );
}

class Bet {
  const Bet({required this.horse, required this.amount});
  final int horse;
  final int amount;

  factory Bet.fromJson(Map<String, dynamic> j) => Bet(horse: j['horse'] as int, amount: j['amount'] as int);
}

class LastResult {
  const LastResult({required this.horse, required this.amount, required this.won, required this.delta});
  final int horse;
  final int amount;
  final bool won;
  final int delta;

  factory LastResult.fromJson(Map<String, dynamic> j) => LastResult(
        horse: j['horse'] as int,
        amount: j['amount'] as int,
        won: j['won'] as bool,
        delta: j['delta'] as int,
      );
}

class Me {
  const Me({required this.id, required this.name, required this.coins, required this.rank, this.bet, this.lastResult});
  final String id;
  final String name;
  final int coins;
  final int rank;
  final Bet? bet;
  final LastResult? lastResult;

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        id: j['id'] as String,
        name: j['name'] as String,
        coins: j['coins'] as int,
        rank: j['rank'] as int,
        bet: j['bet'] == null ? null : Bet.fromJson(j['bet'] as Map<String, dynamic>),
        lastResult: j['lastResult'] == null ? null : LastResult.fromJson(j['lastResult'] as Map<String, dynamic>),
      );
}

class RaceInfo {
  const RaceInfo({required this.startedAt, required this.durationMs, required this.order, required this.times});
  final int startedAt;
  final int durationMs;

  /// 着順(馬番の並び)
  final List<int> order;

  /// times[馬番-1] は、コースを区切った各地点の通過時刻(累積 ms)
  final List<List<int>> times;

  factory RaceInfo.fromJson(Map<String, dynamic> j) => RaceInfo(
        startedAt: j['startedAt'] as int,
        durationMs: j['durationMs'] as int,
        order: [for (final e in j['order'] as List) e as int],
        times: [
          for (final row in j['times'] as List) [for (final e in row as List) (e as num).toInt()],
        ],
      );
}

class PublicBet {
  const PublicBet({required this.playerId, required this.horse, required this.amount, required this.delta});
  final String playerId;
  final int horse;
  final int amount;
  final int delta;

  factory PublicBet.fromJson(Map<String, dynamic> j) => PublicBet(
        playerId: j['playerId'] as String,
        horse: j['horse'] as int,
        amount: j['amount'] as int,
        delta: j['delta'] as int,
      );
}

class RoomView {
  const RoomView({
    required this.phase,
    required this.raceNo,
    required this.totalRaces,
    required this.serverNow,
    required this.betCount,
    required this.onlineCount,
    required this.horses,
    required this.players,
    required this.bets,
    this.me,
    this.race,
  });

  final Phase phase;
  final int raceNo;
  final int totalRaces;
  final int serverNow;
  final int betCount;
  final int onlineCount;
  final List<HorseInfo> horses;
  final List<PlayerInfo> players;
  final Me? me;
  final RaceInfo? race;
  final List<PublicBet> bets;

  factory RoomView.fromJson(Map<String, dynamic> j) => RoomView(
        phase: _phaseFrom(j['phase']),
        raceNo: j['raceNo'] as int,
        totalRaces: j['totalRaces'] as int,
        serverNow: j['serverNow'] as int,
        betCount: j['betCount'] as int,
        onlineCount: j['onlineCount'] as int,
        horses: _list(j['horses'], HorseInfo.fromJson),
        players: _list(j['players'], PlayerInfo.fromJson),
        bets: _list(j['bets'], PublicBet.fromJson),
        me: j['me'] == null ? null : Me.fromJson(j['me'] as Map<String, dynamic>),
        race: j['race'] == null ? null : RaceInfo.fromJson(j['race'] as Map<String, dynamic>),
      );
}
