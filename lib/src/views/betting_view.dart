import 'dart:async';

import 'package:flutter/material.dart';

import '../format.dart';
import '../protocol.dart';
import '../widgets/horse_colors.dart';
import '../widgets/horse_face.dart';

const _minBet = 10;
const maxTickets = 10;

const _typeHints = {
  BetType.win: '1着になる馬を当てる',
  BetType.place: '3着以内に入る馬を当てる',
  BetType.quinella: '1着と2着の2頭を当てる(順番は問わない)',
  BetType.trifecta: '1着・2着・3着を順番どおりに当てる',
};

/// 出走表で馬を押したときの選択の変化。
/// 選んでいる馬をもう一度押すと外れる。頭数がいっぱいのときは、最後の 1 頭と入れ替える。
/// 3連単では、並び順が 1着・2着・3着になる。
List<int> toggleSelection(BetType type, List<int> current, int horse) {
  if (current.contains(horse)) return [for (final h in current) if (h != horse) h];
  if (current.length < type.horseCount) return [...current, horse];
  return [...current.take(type.horseCount - 1), horse];
}

String _comboKey(BetType type, List<int> horses) =>
    '${type.wire}:${(type == BetType.quinella ? ([...horses]..sort()) : horses).join('-')}';

/// 賭け受付中の画面: 馬券の種類と馬を選び、金額を決めて買う。1 レースに複数の馬券を買える。
class BettingView extends StatefulWidget {
  const BettingView({
    super.key,
    required this.view,
    required this.odds,
    required this.onBuy,
    required this.onCancel,
    required this.onBuyTip,
  });
  final RoomView view;

  /// 単勝以外の倍率表。まだ届いていない、または別のレースのものなら、単勝だけ買える。
  final OddsTable? odds;
  final void Function(BetType type, List<int> horses, int amount) onBuy;
  final void Function(String ticketId) onCancel;

  /// 予想屋に料金を払って予想を聞く
  final void Function(String tipsterId) onBuyTip;

  @override
  State<BettingView> createState() => _BettingViewState();
}

class _BettingViewState extends State<BettingView> {
  BetType _type = BetType.win;
  List<int> _selected = const [];
  int _amount = 100;

  Me? get _me => widget.view.me;
  int get _coins => _me?.coins ?? 0;
  List<Ticket> get _tickets => _me?.tickets ?? const [];

  /// このレースの倍率表(届いていて、レースが一致するときだけ)
  OddsTable? get _table {
    final t = widget.odds;
    return t != null && t.raceKey == widget.view.raceKey ? t : null;
  }

  /// 実際に使う種類。倍率表がなければ単勝だけ。
  BetType get _effectiveType => _table == null ? BetType.win : _type;

  bool get _complete => _selected.length == _effectiveType.horseCount;

  /// いま選んでいるのと同じ馬券をすでに買っていれば、その馬券(買うと金額の置き換えになる)
  Ticket? get _existing {
    if (!_complete) return null;
    final key = _comboKey(_effectiveType, _selected);
    for (final t in _tickets) {
      if (_comboKey(t.type, t.horses) == key) return t;
    }
    return null;
  }

  /// 賭けられる上限: 所持金 − ほかの馬券の合計(10 コイン単位に切り下げ)
  int get _maxBet {
    final others = (_me?.staked ?? 0) - (_existing?.amount ?? 0);
    final remaining = _coins - others;
    return remaining - remaining % _minBet;
  }

  double? get _odds {
    if (!_complete) return null;
    final type = _effectiveType;
    if (type == BetType.win) return winOdds(_selected, widget.view.horses);
    return _table?.oddsFor(type, _selected, widget.view.horses);
  }

  @override
  void initState() {
    super.initState();
    _amount = _clamp(100);
  }

  @override
  void didUpdateWidget(BettingView old) {
    super.didUpdateWidget(old);
    final raceChanged = widget.view.raceNo != old.view.raceNo || widget.view.raceKey != old.view.raceKey;
    // 買った(または金額を変えた)馬券がサーバーに反映されたら、選択を消して次の馬券に進む
    String signature(RoomView v) =>
        [for (final t in v.me?.tickets ?? const <Ticket>[]) '${_comboKey(t.type, t.horses)}=${t.amount}'].join(',');
    final bought = signature(widget.view) != signature(old.view) &&
        (widget.view.me?.tickets.length ?? 0) >= (old.view.me?.tickets.length ?? 0);
    if (raceChanged) {
      _type = BetType.win;
      _selected = const [];
      _amount = 100;
    } else if (bought) {
      _selected = const [];
    }
    _amount = _clamp(_amount);
  }

  int _clamp(int amount) {
    final max = _maxBet;
    return max >= _minBet ? amount.clamp(_minBet, max) : _minBet;
  }

  void _setAmount(int amount) => setState(() => _amount = _clamp(amount));

  void _setType(BetType type) {
    if (type != BetType.win && _table == null) return; // 倍率表がないと買えない
    if (type == _type) return;
    setState(() {
      _type = type;
      _selected = const [];
      _amount = _clamp(_amount);
    });
  }

  /// 聞いた予想の印を、出走表の馬ごとにまとめる(例: 「競◎ 伝○」。頭の 1 文字は予想屋の名前)
  String? _marksFor(int no) {
    const symbols = ['◎', '○', '▲'];
    final parts = <String>[];
    for (final tip in _me?.tips ?? const <Tip>[]) {
      final i = tip.marks.indexOf(no);
      if (i < 0 || i >= symbols.length) continue;
      final name = widget.view.tipsters.where((t) => t.id == tip.id).firstOrNull?.name ?? '';
      parts.add('${name.isEmpty ? '' : name.substring(0, 1)}${symbols[i]}');
    }
    return parts.isEmpty ? null : parts.join(' ');
  }

  void _tapHorse(int no) {
    setState(() {
      _selected = toggleSelection(_effectiveType, _selected, no);
      _amount = _clamp(_amount);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = _effectiveType;
    final table = _table;
    final canChoose = _coins >= _minBet;
    return Column(
      children: [
        _TypeSelector(type: type, enabledOthers: table != null, onChanged: _setType),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: Text(
                  [
                    _typeHints[type]!,
                    if (widget.view.course case final course?) '芝 ${course.distance}m ・ 馬場: ${course.going}',
                  ].join('  /  '),
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ),
              if (widget.view.tipsters.isNotEmpty)
                _TipsterPanel(
                  tipsters: widget.view.tipsters,
                  tips: _me?.tips ?? const [],
                  // 料金を払っても、買ってある馬券の合計を下回らない予想屋だけ聞ける
                  available: _coins - (_me?.staked ?? 0),
                  onBuy: widget.onBuyTip,
                ),
              for (final h in widget.view.horses)
                _HorseRow(
                  horse: h,
                  marks: _marksFor(h.no),
                  // 複勝を選んでいるときは、複勝の倍率を見せる
                  odds: type == BetType.place && table != null && h.no - 1 < table.place.length ? table.place[h.no - 1] : h.odds,
                  selected: _selected.contains(h.no),
                  // 3連単は、押した順に 1着・2着・3着
                  orderLabel: type == BetType.trifecta && _selected.contains(h.no) ? '${_selected.indexOf(h.no) + 1}着' : null,
                  onTap: canChoose ? () => _tapHorse(h.no) : null,
                ),
            ],
          ),
        ),
        Material(
          elevation: 8,
          color: scheme.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_tickets.isNotEmpty) _buildTickets(context),
                  if (canChoose) _buildForm(context) else _buildRescue(context),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 買った馬券の一覧。折り返して全部を見せ、1 点ずつ取り消せる。
  Widget _buildTickets(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final staked = _me?.staked ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '買った馬券 ${_tickets.length}点 ・ 計 ${formatCoins(staked)} ・ 残り ${formatCoins(_coins - staked)}',
          style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        // ふつうは全部がそのまま見える。極端に小さい画面で出走表が隠れてしまわないよう、
        // 画面の高さの 45% を超える分だけは一覧の中でスクロールする。
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final t in _tickets)
                  Container(
                    padding: const EdgeInsets.only(left: 10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${ticketLabel(t.type, t.horses)} ${formatCoins(t.amount)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.2),
                        ),
                        Tooltip(
                          message: '取り消す',
                          child: InkResponse(
                            radius: 16,
                            onTap: () => widget.onCancel(t.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                              child: Icon(Icons.close, size: 16, key: Key('cancel-${t.id}'), color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildRescue(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        '次のレースで 100 コインもらえます',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final type = _effectiveType;
    final existing = _existing;
    final odds = _odds;
    final max = _maxBet;
    final full = existing == null && _tickets.length >= maxTickets;
    final noCoins = max < _minBet;
    final missing = type.horseCount - _selected.length;

    final String message;
    var ready = false;
    if (full && _complete) {
      message = '1レースに買えるのは$maxTickets点までです';
    } else if (noCoins) {
      message = '残りのコインがありません(馬券を取り消すと買えます)';
    } else if (missing > 0) {
      message = _selected.isEmpty && type.horseCount == 1 ? '馬を選んでください' : 'あと $missing 頭 選んでください';
    } else if (odds == null) {
      message = '倍率を確認しています…';
    } else {
      ready = true;
      final back = (_amount * (odds * 10).round()) ~/ 10;
      message = '当たれば ${formatCoins(back)}(${formatOdds(odds)})';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('賭け金', style: theme.textTheme.titleSmall),
            const Spacer(),
            _RepeatIconButton(
              key: const Key('betMinus'),
              icon: Icons.remove,
              onStep: !noCoins && _amount > _minBet ? () => _setAmount(_amount - _minBet) : null,
            ),
            SizedBox(
              width: 88,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatCoins(_amount),
                  key: const Key('betAmount'),
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            _RepeatIconButton(
              key: const Key('betPlus'),
              icon: Icons.add,
              onStep: !noCoins && _amount < max ? () => _setAmount(_amount + _minBet) : null,
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              key: const Key('betPlus100'),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: noCoins ? null : () => _setAmount(_amount + 100),
              child: const Text('+100'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const Key('betAll'),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: noCoins ? null : () => _setAmount(max),
              child: const Text('全額'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleSmall?.copyWith(
            color: ready ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: ready
              ? () => widget.onBuy(type, type == BetType.quinella ? ([..._selected]..sort()) : [..._selected], _amount)
              : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          child: Text(existing != null ? '金額を変更する' : 'この馬券を買う'),
        ),
      ],
    );
  }
}

/// 馬券の種類を選ぶ(4 つを横に並べる。狭い画面でもはみ出さないよう等分する)
class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.type, required this.enabledOthers, required this.onChanged});
  final BetType type;

  /// 単勝以外を選べるか(倍率表が届いているか)
  final bool enabledOthers;
  final void Function(BetType) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          for (final t in BetType.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: t == type ? scheme.primary : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: t == BetType.win || enabledOthers ? () => onChanged(t) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          t.label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: t == type
                                ? scheme.onPrimary
                                : (t == BetType.win || enabledOthers ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.35)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HorseRow extends StatelessWidget {
  const _HorseRow({
    required this.horse,
    required this.odds,
    required this.selected,
    required this.orderLabel,
    required this.onTap,
    this.marks,
  });
  final HorseInfo horse;

  /// 聞いた予想の印(例: 「競◎ 伝○」)
  final String? marks;

  /// 表示する倍率(単勝または複勝)
  final double odds;
  final bool selected;

  /// 3連単で選んだときの「1着」「2着」「3着」
  final String? orderLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant, width: selected ? 2.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: horse.hasDetails ? 6 : 9),
            child: Row(
              children: [
                if (horse.hasDetails) ...[
                  HorseFace(no: horse.no, mood: horse.mood, size: 46),
                  const SizedBox(width: 8),
                ],
                HorseBadge(horse.no, size: horse.hasDetails ? 28 : 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 長い馬名は、切らずに縮めて全部見せる
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(horse.name, maxLines: 1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                      if (marks != null)
                        Text(
                          marks!,
                          key: Key('marks-${horse.no}'),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFB3261E), height: 1.2),
                        ),
                      if (horse.hasDetails)
                        Text(
                          _details(horse),
                          key: Key('details-${horse.no}'),
                          // 行数を制限しない: 狭い画面では折り返して、予想の手がかりを必ず全部見せる
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, height: 1.25),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (orderLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(999)),
                        child: Text(orderLabel!, style: TextStyle(color: scheme.onPrimary, fontSize: 13, fontWeight: FontWeight.w800)),
                      ),
                    Text(
                      formatOdds(odds),
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: scheme.primary, height: 1.2),
                    ),
                    if (horse.hasDetails) _Condition(horse.cond),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 例: 「気合十分 ・ 近走 1-3-2 ・ 先行 ・ 牡4 482kg(+2)」
  /// 狭い画面では折り返す。予想の手がかりになるもの(表情・近走)を先に置く。
  static String _details(HorseInfo h) {
    final diff = h.weightDiff > 0 ? '+${h.weightDiff}' : (h.weightDiff == 0 ? '±0' : '${h.weightDiff}');
    final mood = moodLabels[h.mood];
    return '${mood == null ? '' : '$mood ・ '}近走 ${h.recent.join('-')} ・ ${h.style} ・ ${h.sex}${h.age} ${h.weight}kg($diff)';
  }
}

/// 予想屋の欄。開くと 3 人が並び、料金を払うと ◎○▲ を教えてくれる。聞いた予想はここに出続ける。
class _TipsterPanel extends StatefulWidget {
  const _TipsterPanel({required this.tipsters, required this.tips, required this.available, required this.onBuy});
  final List<TipsterInfo> tipsters;
  final List<Tip> tips;

  /// 予想屋に払えるコイン(所持金 − 買ってある馬券の合計)
  final int available;
  final void Function(String tipsterId) onBuy;

  @override
  State<_TipsterPanel> createState() => _TipsterPanelState();
}

class _TipsterPanelState extends State<_TipsterPanel> {
  late bool _open = widget.tips.isNotEmpty; // 聞いた予想があれば、最初から開いておく

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: const Color(0xFFFFF6D6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE0A100)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.record_voice_over, size: 20, color: Color(0xFF6B4A00)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '予想屋に聞く(料金を払うと◎○▲を教えてくれる)',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF3D2B00)),
                      ),
                    ),
                    Icon(_open ? Icons.expand_less : Icons.expand_more, color: const Color(0xFF6B4A00)),
                  ],
                ),
              ),
            ),
            if (_open)
              for (final t in widget.tipsters) _buildTipster(context, t, scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildTipster(BuildContext context, TipsterInfo t, ColorScheme scheme) {
    final tip = widget.tips.where((x) => x.id == t.id).firstOrNull;
    const ink = Color(0xFF3D2B00);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(t.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: ink)),
              ),
              const SizedBox(width: 8),
              Text(
                '★' * t.stars.clamp(0, 3) + '☆' * (3 - t.stars.clamp(0, 3)),
                style: const TextStyle(fontSize: 13, color: Color(0xFFB26A00)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          if (tip != null) ...[
            Text(
              tipMarksText(tip.marks),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFB3261E), height: 1.2),
            ),
            if (tip.comment.isNotEmpty)
              Text('「${tip.comment}」', style: const TextStyle(fontSize: 12, color: ink, height: 1.25)),
          ] else
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: Key('tip-${t.id}'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: const Color(0xFF8A6200),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                onPressed: widget.available >= t.price ? () => widget.onBuy(t.id) : null,
                child: Text(widget.available >= t.price ? '${t.price}コインで聞く' : '${t.price}コイン(コインが足りません)'),
              ),
            ),
        ],
      ),
    );
  }
}

/// 調子の表示(矢印と名前)
class _Condition extends StatelessWidget {
  const _Condition(this.cond);
  final int cond;

  @override
  Widget build(BuildContext context) {
    final (arrow, label, color) = conditionDisplay(cond);
    final style = TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color, height: 1.2);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(arrow, size: 15, color: color), const SizedBox(width: 2), Text(label, style: style)],
    );
  }
}

/// 押すと 1 回、長押しで連続して進むボタン
class _RepeatIconButton extends StatefulWidget {
  const _RepeatIconButton({super.key, required this.icon, required this.onStep});
  final IconData icon;
  final VoidCallback? onStep;

  @override
  State<_RepeatIconButton> createState() => _RepeatIconButtonState();
}

class _RepeatIconButtonState extends State<_RepeatIconButton> {
  Timer? _timer;

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) {
        _stop();
        _timer = Timer.periodic(const Duration(milliseconds: 70), (_) {
          final step = widget.onStep;
          step == null ? _stop() : step();
        });
      },
      onLongPressEnd: (_) => _stop(),
      onLongPressCancel: _stop,
      child: IconButton.filledTonal(
        iconSize: 24,
        visualDensity: VisualDensity.compact,
        onPressed: widget.onStep,
        icon: Icon(widget.icon),
      ),
    );
  }
}
