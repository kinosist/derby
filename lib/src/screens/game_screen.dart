import 'package:flutter/material.dart';

import '../format.dart';
import '../protocol.dart';
import '../room_client.dart';
import '../views/betting_view.dart';
import '../views/final_view.dart';
import '../views/lobby_view.dart';
import '../views/race_view.dart';
import '../views/result_view.dart';

const _phaseLabels = {
  Phase.lobby: '参加受付中',
  Phase.betting: '賭け受付中',
  Phase.racing: 'レース中',
  Phase.result: '結果',
  Phase.finalResult: '最終結果',
};

/// 参加後の画面。サーバーのフェーズに合わせて中身を切り替える。
class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.client});
  final RoomClient client;

  @override
  Widget build(BuildContext context) {
    final view = client.view!;
    final error = client.lastError;
    return Scaffold(
      body: Column(
        children: [
          _Header(view: view, onLeave: () => _confirmLeave(context)),
          if (error != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
            ),
          Expanded(
            child: switch (view.phase) {
              Phase.lobby => LobbyView(view: view),
              Phase.betting => BettingView(
                  view: view,
                  odds: client.oddsTable,
                  onBuy: client.placeTicket,
                  onCancel: client.cancelTicket,
                  onBuyTip: client.buyTip,
                ),
              Phase.racing => RaceView(client: client),
              Phase.result => ResultView(view: view),
              Phase.finalResult => FinalView(view: view),
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLeave(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出しますか?'),
        content: const Text('名前の入力画面に戻ります。同じ名前で入り直せば、所持金はそのままです。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出する')),
        ],
      ),
    );
    if (ok == true) client.leave();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.view, required this.onLeave});
  final RoomView view;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final me = view.me!;
    final onColor = scheme.onPrimary;
    return Material(
      color: scheme.primary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      view.raceNo > 0 ? '第 ${view.raceNo} レース / 全 ${view.totalRaces} レース' : 'derby',
                      style: TextStyle(color: onColor, fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFE0A100), borderRadius: BorderRadius.circular(999)),
                    child: Text(
                      _phaseLabels[view.phase]!,
                      style: const TextStyle(color: Color(0xFF201800), fontWeight: FontWeight.w700),
                    ),
                  ),
                  // 退出できるのは試合が始まる前だけ(名前の打ち間違いを直すため)。
                  // 試合中に別の名前で入り直すと、新しい 1,000 コインで予想屋だけ聞く、といったことができてしまう。
                  if (view.phase == Phase.lobby)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: onColor),
                      onSelected: (_) => onLeave(),
                      itemBuilder: (context) => const [PopupMenuItem(value: 'leave', child: Text('退出する'))],
                    )
                  else
                    const SizedBox(width: 12, height: 48),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                // 長い名前や大きな金額でもはみ出さないよう、収まらないときは全体を縮める
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('${me.name}: ', style: TextStyle(color: onColor, fontSize: 16)),
                      Text('${formatCoins(me.coins)}コイン',
                          style: TextStyle(color: onColor, fontSize: 24, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 8),
                      Text('(${me.rank}位 / ${view.players.length}人)', style: TextStyle(color: onColor, fontSize: 16)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
