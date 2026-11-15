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
        _MyResult(result: view.me?.lastResult),
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
        Expanded(child: Leaderboard(players: view.players, meId: view.me?.id)),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text('先生が次へ進めるのを待っています', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

class _MyResult extends StatelessWidget {
  const _MyResult({required this.result});
  final LastResult? result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final (String text, Color color) = switch (r) {
      null => ('見送り', Theme.of(context).colorScheme.onSurfaceVariant),
      LastResult(won: true) => ('的中! ${formatDelta(r.delta)}', const Color(0xFF0F7A35)),
      _ => ('はずれ ${formatDelta(r.delta)}', const Color(0xFFB3261E)),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(text, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: color)),
    );
  }
}
