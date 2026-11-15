import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/room_client.dart';
import 'src/screens/game_screen.dart';
import 'src/screens/join_screen.dart';

/// 接続先。ビルド時に --dart-define=SERVER_URL=wss://…/ws で指定する。
/// 既定値は、エミュレータから開発 PC のローカルサーバーを指すアドレス。
const serverUrl = String.fromEnvironment('SERVER_URL', defaultValue: 'ws://10.0.2.2:8787/ws');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(DerbyApp(client: RoomClient(url: serverUrl)..init()));
}

class DerbyApp extends StatelessWidget {
  const DerbyApp({super.key, required this.client});
  final RoomClient client;

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A3A)),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'derby',
      debugShowCheckedModeBanner: false,
      // 漢字が日本語の字形で表示されるよう、文字の言語を日本語にする
      theme: base.copyWith(
        textTheme: _japanese(base.textTheme),
        primaryTextTheme: _japanese(base.primaryTextTheme),
      ),
      home: ListenableBuilder(
        listenable: client,
        builder: (context, _) {
          final joined = client.view?.me != null;
          // 初めての参加でつながらないときも出す(接続先の間違いや、ネットワークの制限に気づけるように)
          final reconnecting = client.status != ConnStatus.connected && client.wantsRoom;
          return Stack(
            children: [
              joined
                  ? GameScreen(client: client)
                  : JoinScreen(
                      onJoin: client.join,
                      error: client.lastError,
                      busy: client.status == ConnStatus.connecting,
                    ),
              if (reconnecting) const _ReconnectingBanner(),
            ],
          );
        },
      ),
    );
  }
}

TextTheme _japanese(TextTheme t) {
  const ja = Locale('ja', 'JP');
  TextStyle? f(TextStyle? s) => s?.copyWith(locale: ja);
  return t.copyWith(
    displayLarge: f(t.displayLarge),
    displayMedium: f(t.displayMedium),
    displaySmall: f(t.displaySmall),
    headlineLarge: f(t.headlineLarge),
    headlineMedium: f(t.headlineMedium),
    headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge),
    titleMedium: f(t.titleMedium),
    titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge),
    bodyMedium: f(t.bodyMedium),
    bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge),
    labelMedium: f(t.labelMedium),
    labelSmall: f(t.labelSmall),
  );
}

class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Material(
        color: scheme.error,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('再接続中…',
                textAlign: TextAlign.center, style: TextStyle(color: scheme.onError, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}
