import 'package:flutter/material.dart';

import '../format.dart';
import '../protocol.dart';
import 'horse_colors.dart';

/// 順位表。自分の行を強調し、切断中の人は薄く表示する。
class Leaderboard extends StatelessWidget {
  const Leaderboard({super.key, required this.players, this.meId, this.bets = const []});
  final List<PlayerInfo> players;
  final String? meId;

  /// 結果画面で公開する全員の賭け。渡すと、各行に賭けた馬と増減を出す。
  final List<PublicBet> bets;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final betOf = {for (final b in bets) b.playerId: b};
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: players.length,
      itemBuilder: (context, i) {
        final p = players[i];
        final isMe = p.id == meId;
        final bet = betOf[p.id];
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
              if (bet != null) ...[
                const SizedBox(width: 6),
                HorseBadge(bet.horse, size: 22),
                SizedBox(
                  width: 72,
                  child: Text(
                    formatDelta(bet.delta),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: bet.delta > 0 ? const Color(0xFF0F7A35) : const Color(0xFFB3261E),
                    ),
                  ),
                ),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 64),
                child: Text(
                  formatCoins(p.coins),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
