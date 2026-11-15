import 'package:flutter/material.dart';

import '../format.dart';
import '../protocol.dart';

/// 順位表。自分の行を強調し、切断中の人は薄く表示する。
class Leaderboard extends StatelessWidget {
  const Leaderboard({super.key, required this.players, this.meId});
  final List<PlayerInfo> players;
  final String? meId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: players.length,
      itemBuilder: (context, i) {
        final p = players[i];
        final isMe = p.id == meId;
        final color = p.online ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.4);
        final style = TextStyle(color: color, fontSize: 16, fontWeight: isMe ? FontWeight.w800 : FontWeight.w500);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isMe ? scheme.primaryContainer : null,
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              SizedBox(width: 44, child: Text('${p.rank}位', style: style, textAlign: TextAlign.right)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  p.online ? p.name : '${p.name}(切断中)',
                  style: style,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(formatCoins(p.coins), style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        );
      },
    );
  }
}
