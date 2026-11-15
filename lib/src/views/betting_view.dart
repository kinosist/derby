import 'dart:async';

import 'package:flutter/material.dart';

import '../format.dart';
import '../protocol.dart';
import '../widgets/horse_colors.dart';

const _minBet = 10;

/// 賭け受付中の画面: 出走馬を選び、金額を決めて賭ける。
class BettingView extends StatefulWidget {
  const BettingView({super.key, required this.view, required this.onBet, required this.onCancel});
  final RoomView view;
  final void Function(int horse, int amount) onBet;
  final VoidCallback onCancel;

  @override
  State<BettingView> createState() => _BettingViewState();
}

class _BettingViewState extends State<BettingView> {
  int? _horse;
  late int _amount;

  /// 賭け済みの内容を変更している最中
  bool _editing = false;

  int get _coins => widget.view.me?.coins ?? 0;
  int get _maxBet => _coins - _coins % _minBet;
  bool get _canBet => _maxBet >= _minBet;
  Bet? get _placed => widget.view.me?.bet;

  @override
  void initState() {
    super.initState();
    _amount = _clamp(100);
  }

  @override
  void didUpdateWidget(BettingView old) {
    super.didUpdateWidget(old);
    _amount = _clamp(_amount);
    if (widget.view.raceNo != old.view.raceNo) {
      _horse = null;
      _editing = false;
      _amount = _clamp(100);
    }
    final placed = _placed;
    final before = old.view.me?.bet;
    // 賭けがサーバーに反映されたら、編集を終える
    if (placed != null && (before == null || before.horse != placed.horse || before.amount != placed.amount)) {
      _editing = false;
    }
  }

  int _clamp(int amount) => _canBet ? amount.clamp(_minBet, _maxBet) : _minBet;

  void _setAmount(int amount) => setState(() => _amount = _clamp(amount));

  @override
  Widget build(BuildContext context) {
    final placed = _placed;
    final showForm = placed == null || _editing;
    final selected = showForm ? _horse : placed.horse;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            children: [
              for (final h in widget.view.horses)
                _HorseRow(
                  horse: h,
                  selected: selected == h.no,
                  onTap: showForm && _canBet ? () => setState(() => _horse = h.no) : null,
                ),
            ],
          ),
        ),
        Material(
          elevation: 8,
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: showForm ? _buildForm(context) : _buildPlaced(context, placed),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    if (!_canBet) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('次のレースで 100 コインもらえます', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          const FilledButton(onPressed: null, child: Text('この内容で賭ける')),
        ],
      );
    }
    final horse = _horse == null ? null : widget.view.horses.where((h) => h.no == _horse).firstOrNull;
    final back = horse == null ? null : (_amount * (horse.odds * 10).round()) ~/ 10;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('賭け金', style: theme.textTheme.titleMedium),
            const Spacer(),
            _RepeatIconButton(
              key: const Key('betMinus'),
              icon: Icons.remove,
              onStep: _amount > _minBet ? () => _setAmount(_amount - _minBet) : null,
            ),
            SizedBox(
              width: 96,
              child: Text(
                formatCoins(_amount),
                key: const Key('betAmount'),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            _RepeatIconButton(
              key: const Key('betPlus'),
              icon: Icons.add,
              onStep: _amount < _maxBet ? () => _setAmount(_amount + _minBet) : null,
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(key: const Key('betPlus100'), onPressed: () => _setAmount(_amount + 100), child: const Text('+100')),
            const SizedBox(width: 8),
            OutlinedButton(key: const Key('betAll'), onPressed: () => _setAmount(_maxBet), child: const Text('全額')),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          back == null ? '馬を選んでください' : '当たれば ${formatCoins(back)}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: back == null ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (_editing) ...[
              TextButton(onPressed: () => setState(() => _editing = false), child: const Text('やめる')),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FilledButton(
                onPressed: horse == null ? null : () => widget.onBet(horse.no, _amount),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                child: const Text('この内容で賭ける'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlaced(BuildContext context, Bet placed) {
    final theme = Theme.of(context);
    final horse = widget.view.horses.where((h) => h.no == placed.horse).firstOrNull;
    final back = horse == null ? 0 : (placed.amount * (horse.odds * 10).round()) ~/ 10;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('賭けました', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            HorseBadge(placed.horse, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Text(horse?.name ?? '', style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
            ),
            Text('${formatCoins(placed.amount)} コイン',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 4),
        Text('当たれば ${formatCoins(back)}',
            textAlign: TextAlign.right, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: widget.onCancel, child: const Text('取り消し')),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => setState(() {
                _editing = true;
                _horse = placed.horse;
                _amount = _clamp(placed.amount);
              }),
              child: const Text('変更'),
            ),
          ],
        ),
        Text('先生が締め切るまで変更できます',
            textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _HorseRow extends StatelessWidget {
  const _HorseRow({required this.horse, required this.selected, required this.onTap});
  final HorseInfo horse;
  final bool selected;
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                HorseBadge(horse.no),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    horse.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  formatOdds(horse.odds),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: scheme.primary),
                ),
              ],
            ),
          ),
        ),
      ),
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
        iconSize: 28,
        onPressed: widget.onStep,
        icon: Icon(widget.icon),
      ),
    );
  }
}
