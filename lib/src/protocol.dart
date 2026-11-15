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
  const HorseInfo({
    required this.no,
    required this.name,
    required this.odds,
    this.sex = '',
    this.age = 0,
    this.weight = 0,
    this.weightDiff = 0,
    this.style = '',
    this.recent = const [],
    this.pop = 0,
    this.cond = 3,
    this.mood = 'calm',
    this.hasDetails = false,
  });
  final int no;
  final String name;
  final double odds;

  /// 性別(牡・牝・セ)と年齢
  final String sex;
  final int age;

  /// 馬体重(kg)と前走からの増減
  final int weight;
  final int weightDiff;

  /// 脚質(逃げ・先行・差し・追込)
  final String style;

  /// 近3走の着順(新しい順)
  final List<int> recent;

  /// 人気順
  final int pop;

  /// 調子 1(絶不調)〜 5(絶好調)
  final int cond;

  /// 表情: fired / happy / calm / restless / sleepy
  final String mood;

  /// 詳細が届いているか(古いサーバーは名前と倍率しか送らない)
  final bool hasDetails;

  factory HorseInfo.fromJson(Map<String, dynamic> j) => HorseInfo(
        no: j['no'] as int,
        name: j['name'] as String,
        odds: (j['odds'] as num).toDouble(),
        sex: j['sex'] is String ? j['sex'] as String : '',
        age: j['age'] is int ? j['age'] as int : 0,
        weight: j['weight'] is int ? j['weight'] as int : 0,
        weightDiff: j['weightDiff'] is int ? j['weightDiff'] as int : 0,
        style: j['style'] is String ? j['style'] as String : '',
        recent: j['recent'] is List ? [for (final e in j['recent'] as List) if (e is int) e] : const [],
        pop: j['pop'] is int ? j['pop'] as int : 0,
        cond: j['cond'] is int ? (j['cond'] as int).clamp(1, 5) : 3,
        mood: j['mood'] is String ? j['mood'] as String : 'calm',
        hasDetails: j['cond'] is int && j['mood'] is String,
      );
}

/// レースの距離(m)と馬場状態
class CourseInfo {
  const CourseInfo({required this.distance, required this.going});
  final int distance;
  final String going;

  factory CourseInfo.fromJson(Map<String, dynamic> j) => CourseInfo(
        distance: j['distance'] is int ? j['distance'] as int : 1600,
        going: j['going'] is String ? j['going'] as String : '良',
      );
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
    this.course,
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
  final CourseInfo? course;
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
        course: j['course'] is Map<String, dynamic> ? CourseInfo.fromJson(j['course'] as Map<String, dynamic>) : null,
      );
}
