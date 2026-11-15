import 'package:flutter/material.dart';

const nameMaxLength = 12;

/// 名前を入れて参加する画面。
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.onJoin, this.error, this.busy = false});
  final void Function(String name) onJoin;
  final String? error;

  /// 接続中(ボタンを押せなくする)
  final bool busy;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _controller.text.trim();
    // 絵文字なども 1 文字として数える(サーバーと同じ数え方)
    final length = name.runes.length;
    final tooLong = length > nameMaxLength;
    final valid = length >= 1 && !tooLong;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'derby',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w900, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 4),
                Text('みんなで競馬予想', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                const SizedBox(height: 40),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  style: const TextStyle(fontSize: 22),
                  decoration: InputDecoration(
                    labelText: 'あなたの名前',
                    border: const OutlineInputBorder(),
                    errorText: tooLong ? '12文字までです' : null,
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (valid && !widget.busy) widget.onJoin(name);
                  },
                ),
                const SizedBox(height: 12),
                if (widget.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(widget.error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 16)),
                  ),
                FilledButton(
                  onPressed: valid && !widget.busy ? () => widget.onJoin(name) : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('参加'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
