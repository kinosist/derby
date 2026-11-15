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

/// 馬券の種類
enum BetType {
  win('win', '単勝', 1),
  place('place', '複勝', 1),
  quinella('quinella', '馬連', 2),
  trifecta('trifecta', '3連単', 3);

  const BetType(this.wire, this.label, this.horseCount);

  /// 通信で使う名前
  final String wire;
  final String label;

  /// 選ぶ頭数
  final int horseCount;

  static BetType? fromWire(Object? raw) {
    for (final t in values) {
      if (t.wire == raw) return t;
    }
    return null;
  }
}

/// 馬券の表示名(例: 「単勝 3」「馬連 3-5」「3連単 4→1→2」)
String ticketLabel(BetType type, List<int> horses) =>
    '${type.label} ${horses.join(type == BetType.trifecta ? '→' : '-')}';

List<int> _ints(Object? raw) => raw is List ? [for (final e in raw) if (e is int) e] : const [];

/// 予想屋(賭け受付中に、料金を払うと予想を教えてくれる)
class TipsterInfo {
  const TipsterInfo({required this.id, required this.name, required this.price, required this.stars});
  final String id;
  final String name;
  final int price;

  /// 精度(1〜3)
  final int stars;

  factory TipsterInfo.fromJson(Map<String, dynamic> j) => TipsterInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        price: j['price'] as int,
        stars: j['stars'] is int ? j['stars'] as int : 1,
      );
}

/// 予想の印(例: 「◎2 ○5 ▲1」)。marks は ◎本命・○対抗・▲単穴 の馬番。
String tipMarksText(List<int> marks) {
  const symbols = ['◎', '○', '▲'];
  return [for (var i = 0; i < marks.length && i < symbols.length; i++) '${symbols[i]}${marks[i]}'].join(' ');
}

/// 買った予想
class Tip {
  const Tip({required this.id, required this.marks, required this.comment});

  /// 予想屋の id
  final String id;
  final List<int> marks;
  final String comment;

  factory Tip.fromJson(Map<String, dynamic> j) => Tip(
        id: j['id'] as String,
        marks: _ints(j['marks']),
        comment: j['comment'] is String ? j['comment'] as String : '',
      );
}

/// 結果画面で公開される、予想屋の予想と当たり外れ(◎ が 1 着なら的中)
class TipResult {
  const TipResult({required this.id, required this.name, required this.marks, required this.hit});
  final String id;
  final String name;
  final List<int> marks;
  final bool hit;

  factory TipResult.fromJson(Map<String, dynamic> j) => TipResult(
        id: j['id'] as String,
        name: j['name'] as String,
        marks: _ints(j['marks']),
        hit: j['hit'] == true,
      );
}

/// 買った馬券 1 点。odds は買った時点の倍率。
class Ticket {
  const Ticket({required this.id, required this.type, required this.horses, required this.amount, required this.odds});
  final String id;
  final BetType type;
  final List<int> horses;
  final int amount;
  final double odds;

  /// 知らない種類の馬券(新しいサーバーが増やした場合)は null
  static Ticket? fromJson(Map<String, dynamic> j) {
    final type = BetType.fromWire(j['type']);
    if (type == null) return null;
    return Ticket(
      id: j['id'] is String ? j['id'] as String : '',
      type: type,
      horses: _ints(j['horses']),
      amount: j['amount'] as int,
      odds: (j['odds'] as num).toDouble(),
    );
  }
}

/// 馬券 1 点の結果
class TicketResult {
  const TicketResult({
    required this.type,
    required this.horses,
    required this.amount,
    required this.odds,
    required this.won,
    required this.payout,
  });
  final BetType type;
  final List<int> horses;
  final int amount;
  final double odds;
  final bool won;
  final int payout;

  static TicketResult? fromJson(Map<String, dynamic> j) {
    final type = BetType.fromWire(j['type']);
    if (type == null) return null;
    return TicketResult(
      type: type,
      horses: _ints(j['horses']),
      amount: j['amount'] as int,
      odds: (j['odds'] as num).toDouble(),
      won: j['won'] as bool,
      payout: j['payout'] as int,
    );
  }
}

/// 1 レースの自分の結果: 賭けた合計、差し引きの増減、馬券ごとの当たり外れ
class Results {
  const Results({required this.staked, required this.delta, required this.tickets});
  final int staked;
  final int delta;
  final List<TicketResult> tickets;

  factory Results.fromJson(Map<String, dynamic> j) => Results(
        staked: j['staked'] as int,
        delta: j['delta'] as int,
        tickets: [
          for (final e in j['tickets'] as List)
            ?TicketResult.fromJson(e as Map<String, dynamic>),
        ],
      );
}

class Me {
  const Me({
    required this.id,
    required this.name,
    required this.coins,
    required this.rank,
    this.tickets = const [],
    this.results,
    this.tips = const [],
  });
  final String id;
  final String name;
  final int coins;
  final int rank;

  /// このレースで買った予想
  final List<Tip> tips;

  /// このレースで買った馬券
  final List<Ticket> tickets;

  /// 直前のレースの結果(賭けていなければ null)
  final Results? results;

  /// 買った馬券の合計
  int get staked => tickets.fold(0, (a, t) => a + t.amount);

  factory Me.fromJson(Map<String, dynamic> j) {
    // 古いサーバーは単勝 1 点(bet)とその結果(lastResult)だけを送る。馬券の形に直して読む。
    final List<Ticket> tickets;
    if (j['tickets'] is List) {
      tickets = [
        for (final e in j['tickets'] as List)
          ?Ticket.fromJson(e as Map<String, dynamic>),
      ];
    } else if (j['bet'] case final Map<String, dynamic> bet) {
      tickets = [Ticket(id: 'legacy', type: BetType.win, horses: [bet['horse'] as int], amount: bet['amount'] as int, odds: 0)];
    } else {
      tickets = const [];
    }
    final Results? results;
    if (j['results'] case final Map<String, dynamic> r) {
      results = Results.fromJson(r);
    } else if (j['lastResult'] case final Map<String, dynamic> last when j['results'] == null && j['tickets'] == null) {
      final amount = last['amount'] as int;
      final delta = last['delta'] as int;
      final won = last['won'] as bool;
      results = Results(staked: amount, delta: delta, tickets: [
        TicketResult(
          type: BetType.win, horses: [last['horse'] as int], amount: amount, odds: 0, won: won, payout: won ? amount + delta : 0,
        ),
      ]);
    } else {
      results = null;
    }
    return Me(
      id: j['id'] as String,
      name: j['name'] as String,
      coins: j['coins'] as int,
      rank: j['rank'] as int,
      tickets: tickets,
      results: results,
      tips: _list(j['tips'], Tip.fromJson),
    );
  }
}

/// 単勝の倍率(出走表から引く)
double? winOdds(List<int> horses, List<HorseInfo> field) {
  if (horses.length != 1) return null;
  for (final h in field) {
    if (h.no == horses[0]) return h.odds;
  }
  return null;
}

/// 単勝以外の倍率表。賭け受付が始まるときにサーバーから 1 回届く。
class OddsTable {
  const OddsTable({required this.raceKey, required this.place, required this.quinella, required this.trifecta});

  /// どのレースの倍率表か(状態の raceKey と一致するものだけ使う)
  final String raceKey;

  /// place[馬番-1]
  final List<double> place;

  /// キーは「小さい馬番-大きい馬番」
  final Map<String, double> quinella;

  /// キーは「1着-2着-3着」
  final Map<String, double> trifecta;

  static Map<String, double> _map(Object? raw) => raw is Map
      ? {
          for (final e in raw.entries)
            if (e.value is num) e.key as String: (e.value as num).toDouble(),
        }
      : const {};

  factory OddsTable.fromJson(Map<String, dynamic> j) => OddsTable(
        raceKey: j['raceKey'] as String,
        place: j['place'] is List ? [for (final e in j['place'] as List) if (e is num) e.toDouble()] : const [],
        quinella: _map(j['quinella']),
        trifecta: _map(j['trifecta']),
      );

  /// 馬券の倍率。選んだ頭数が足りない、表にない、などの場合は null。
  double? oddsFor(BetType type, List<int> horses, List<HorseInfo> field) {
    if (horses.length != type.horseCount) return null;
    switch (type) {
      case BetType.win:
        return winOdds(horses, field);
      case BetType.place:
        final i = horses[0] - 1;
        return i >= 0 && i < place.length ? place[i] : null;
      case BetType.quinella:
        final sorted = [...horses]..sort();
        return quinella[sorted.join('-')];
      case BetType.trifecta:
        return trifecta[horses.join('-')];
    }
  }
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

/// 結果画面で公開される、ほかの人も含めた賭け。
/// horse は古いサーバー向けの要約(単勝 1 点だった頃の馬番)。tickets があればそちらを使う。
class PublicBet {
  const PublicBet({
    required this.playerId,
    required this.horse,
    required this.amount,
    required this.delta,
    this.tickets = const [],
  });
  final String playerId;
  final int horse;

  /// 賭けた合計
  final int amount;
  final int delta;
  final List<TicketResult> tickets;

  factory PublicBet.fromJson(Map<String, dynamic> j) => PublicBet(
        playerId: j['playerId'] as String,
        horse: j['horse'] as int,
        amount: j['amount'] as int,
        delta: j['delta'] as int,
        tickets: j['tickets'] is List
            ? [
                for (final e in j['tickets'] as List)
                  ?TicketResult.fromJson(e as Map<String, dynamic>),
              ]
            : const [],
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
    this.raceKey,
    this.tipsters = const [],
    this.tipResults = const [],
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

  /// レースごとに変わる識別子(倍率表と対応させる)。古いサーバーは送らない。
  final String? raceKey;

  /// 予想屋の一覧(賭け受付中のみ。古いサーバーは送らない)
  final List<TipsterInfo> tipsters;

  /// 結果画面で公開される、予想屋の予想と当たり外れ
  final List<TipResult> tipResults;
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
        raceKey: j['raceKey'] is String ? j['raceKey'] as String : null,
        tipsters: _list(j['tipsters'], TipsterInfo.fromJson),
        tipResults: _list(j['tipResults'], TipResult.fromJson),
      );
}
