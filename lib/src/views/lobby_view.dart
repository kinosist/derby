import 'package:flutter/material.dart';

import '../protocol.dart';

/// 試合開始を待つ画面。
class LobbyView extends StatelessWidget {
  const LobbyView({super.key, required this.view});
  final RoomView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meId = view.me?.id;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 12),
        Text('先生が試合を始めるのを待っています',
            textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('参加者 ${view.players.length} 人', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final p in view.players)
              Chip(
                label: Text(p.name),
                backgroundColor: p.id == meId ? theme.colorScheme.primaryContainer : null,
                side: p.id == meId ? BorderSide(color: theme.colorScheme.primary, width: 2) : null,
              ),
          ],
        ),
      ],
    );
  }
}
