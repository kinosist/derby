import 'package:flutter/material.dart';

import '../format.dart';
import '../protocol.dart';
import '../widgets/leaderboard.dart';

/// 最終結果の画面。
class FinalView extends StatelessWidget {
  const FinalView({super.key, required this.view});
  final RoomView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = view.me;
    return Column(
      children: [
        const SizedBox(height: 16),
        Text('最終結果', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        if (me != null) ...[
          const SizedBox(height: 8),
          Text(
            '${me.rank}位',
            style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: theme.colorScheme.primary, height: 1.1),
          ),
          Text('${view.players.length}人中 ・ ${formatCoins(me.coins)} コイン', style: theme.textTheme.titleMedium),
        ],
        const SizedBox(height: 12),
        const Divider(height: 1),
        Expanded(child: Leaderboard(players: view.players, meId: me?.id)),
      ],
    );
  }
}
