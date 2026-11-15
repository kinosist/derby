import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../format.dart';
import '../protocol.dart';
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
    final distance = view.course?.distance ?? 1600;
    final lead = progress.fold(0.0, math.max);
    final remain = ((distance * (1 - lead)) / 10).round() * 10;
    final tickets = view.me?.tickets ?? const <Ticket>[];
    final myHorses = {for (final t in tickets) ...t.horses};
    final staked = tickets.fold(0, (a, t) => a + t.amount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Column(
        children: [
          Expanded(
            child: RaceTrack(progress: progress, myHorses: myHorses, animMs: elapsed, distance: distance),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(allIn ? 'ゴール ' : '順位 ', style: theme.textTheme.titleSmall),
              for (final no in order)
                Padding(padding: const EdgeInsets.only(right: 3), child: HorseBadge(no, size: 26)),

            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  switch (tickets.length) {
                    0 => '見送り',
                    1 => '${ticketLabel(tickets[0].type, tickets[0].horses)} に ${formatCoins(staked)}',
                    _ => '${tickets.length}点 計 ${formatCoins(staked)}(${tickets.map((t) => ticketLabel(t.type, t.horses)).join('、')})',
                  },
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: tickets.isEmpty ? null : FontWeight.w700),
                ),
              ),
              if (lead < 1.0) ...[
                const SizedBox(width: 8),
                Text('残り ${remain}m', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
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
