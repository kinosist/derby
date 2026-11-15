import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../format.dart';
import '../race_math.dart';
import '../room_client.dart';
import '../widgets/horse_colors.dart';
import '../widgets/race_track.dart';

/// レース中の画面。サーバーの時刻を基準に、全員が同じ展開を見る。
class RaceView extends StatefulWidget {
  const RaceView({super.key, required this.client});
  final RoomClient client;

  @override
  State<RaceView> createState() => _RaceViewState();
}

class _RaceViewState extends State<RaceView> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    // 毎フレーム描き直す。位置は経過時間から求めるので、途中から開いても正しい位置になる。
    _ticker = createTicker((_) => setState(() {}))..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final view = widget.client.view;
    final race = view?.race;
    if (view == null || race == null) return const SizedBox.shrink();

    final elapsed = math.max(0, widget.client.serverNowMs() - race.startedAt);
    final progress = [
      for (var i = 0; i < view.horses.length; i++) i < race.times.length ? horseProgress(race.times[i], elapsed) : 0.0,
    ];
    final allIn = race.times.isNotEmpty && progress.every((p) => p >= 1.0);
    final order = allIn && race.order.isNotEmpty ? race.order : liveOrder(race.times, elapsed);
    final bet = view.me?.bet;
    final betHorse = bet == null ? null : view.horses.where((h) => h.no == bet.horse).firstOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        children: [
          Expanded(child: RaceTrack(progress: progress, myHorse: bet?.horse, animMs: elapsed)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(allIn ? 'ゴール ' : '順位 ', style: theme.textTheme.titleSmall),
              for (final no in order)
                Padding(padding: const EdgeInsets.only(right: 4), child: HorseBadge(no, size: 28)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (bet != null) ...[
                HorseBadge(bet.horse, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${betHorse?.name ?? ''} に ${formatCoins(bet.amount)}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ] else
                Expanded(child: Text('見送り', style: theme.textTheme.titleMedium)),
            ],
          ),
          SizedBox(
            height: 28,
            child: allIn
                ? Text('結果を待っています…', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 16))
                : null,
          ),
        ],
      ),
    );
  }
}
