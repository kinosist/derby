import 'package:flutter/material.dart';

import '../format.dart';
import '../protocol.dart';
import '../widgets/horse_colors.dart';
import '../widgets/leaderboard.dart';

/// レース結果の画面: 着順、自分の結果、順位表。
class ResultView extends StatelessWidget {
  const ResultView({super.key, required this.view});
  final RoomView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = view.race?.order ?? const <int>[];
    String nameOf(int no) => view.horses.where((h) => h.no == no).firstOrNull?.name ?? '';
    final winner = order.isEmpty ? null : view.horses.where((h) => h.no == order.first).firstOrNull;

    return Column(
      children: [
        _MyResult(results: view.me?.results),
        if (view.me?.results case final r? when r.tickets.length > 1 || r.tickets.any((t) => t.type != BetType.win))
          _MyTickets(tickets: r.tickets),
        if (winner != null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6D6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0A100), width: 2),
            ),
            child: Row(
              children: [
                const Text('1着', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF6B4A00))),
                const SizedBox(width: 10),
                HorseBadge(winner.no, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(winner.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF201800))),
                ),
                Text(formatOdds(winner.odds),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF201800))),
              ],
            ),
          ),
        if (order.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                for (var i = 1; i < order.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${i + 1}着 ', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                      Tooltip(message: nameOf(order[i]), child: HorseBadge(order[i], size: 24)),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(child: Leaderboard(players: view.players, meId: view.me?.id, bets: view.bets)),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text('先生が次へ進めるのを待っています', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

class _MyResult extends StatelessWidget {
  const _MyResult({required this.results});
  final Results? results;

  @override
  Widget build(BuildContext context) {
    final r = results;
    final (String text, Color color) = switch (r) {
      null => ('見送り', Theme.of(context).colorScheme.onSurfaceVariant),
      // 1 点でも当たっていれば「的中」。増減は全馬券の合計。
      _ when r.tickets.any((t) => t.won) => ('的中! ${formatDelta(r.delta)}', const Color(0xFF0F7A35)),
      _ => ('はずれ ${formatDelta(r.delta)}', const Color(0xFFB3261E)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: color)),
      ),
    );
  }
}

/// 自分の馬券ごとの結果(横に並べる。当たった馬券を先に)
class _MyTickets extends StatelessWidget {
  const _MyTickets({required this.tickets});
  final List<TicketResult> tickets;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sorted = [...tickets.where((t) => t.won), ...tickets.where((t) => !t.won)];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: sorted.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final t = sorted[i];
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: t.won ? const Color(0xFFDDF3E2) : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: t.won ? const Color(0xFF0F7A35) : scheme.outlineVariant),
            ),
            child: Text(
              t.won ? '${ticketLabel(t.type, t.horses)} +${formatCoins(t.payout)}' : '${ticketLabel(t.type, t.horses)} はずれ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: t.won ? FontWeight.w800 : FontWeight.w500,
                color: t.won ? const Color(0xFF0B5A27) : scheme.onSurfaceVariant,
              ),
            ),
          );
        },
      ),
    );
  }
}
