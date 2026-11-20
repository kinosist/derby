import 'package:flutter/material.dart';

/// 接続先(サーバーのアドレス)が指定されずに起動されたときに出す案内。
/// 接続先はコードには書かず、実行・ビルドのときに --dart-define=SERVER_URL=… で指定する。
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key, this.given = ''});

  /// 指定されていた値(形式が正しくないときに見せる)
  final String given;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const code = TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4);
    Widget box(String text) => Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(text, style: code),
        );
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('接続先が設定されていません',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: theme.colorScheme.error)),
              const SizedBox(height: 12),
              if (given.trim().isNotEmpty) ...[
                const Text('指定された値は、ws:// または wss:// で始まるアドレスではありません。'),
                box(given),
              ],
              const Text('このアプリは、起動するときにサーバーのアドレスを指定します。先生から教わったアドレスを使ってください。'),
              const SizedBox(height: 16),
              Text('Android Studio の場合', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Run → Edit Configurations… を開き、「Additional run args」に次を入れて、実行し直します。'),
              box('--dart-define=SERVER_URL=wss://<サーバーのアドレス>/ws'),
              const SizedBox(height: 10),
              Text('ターミナルの場合', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              box('flutter run --dart-define=SERVER_URL=wss://<サーバーのアドレス>/ws'),
              const SizedBox(height: 10),
              const Text('設定を変えたあとは、アプリを一度停止して実行し直してください(ホットリロードでは反映されません)。'),
            ],
          ),
        ),
      ),
    );
  }
}
