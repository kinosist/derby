import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/room_client.dart';
import 'src/screens/game_screen.dart';
import 'src/screens/join_screen.dart';
import 'src/screens/setup_screen.dart';

/// 接続先(サーバーのアドレス)。コードには書かず、実行・ビルドのときに指定する。
///   flutter run --dart-define=SERVER_URL=wss://<サーバーのアドレス>/ws
/// Android Studio では、Run → Edit Configurations… の「Additional run args」に同じ指定を入れる。
/// 開発 PC のローカルサーバーにつなぐときは ws://10.0.2.2:8787/ws(10.0.2.2 はエミュレータから見た開発 PC)。
const serverUrl = String.fromEnvironment('SERVER_URL');

/// 接続先として使える形か(ws:// か wss:// で始まるアドレス)
bool isValidServerUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  return uri != null && (uri.scheme == 'ws' || uri.scheme == 'wss') && uri.host.isNotEmpty;
}

/// アプリの入口。接続先が指定されていなければ、設定方法の案内を出す。
Widget buildApp(String url) {
  if (!isValidServerUrl(url)) {
    return MaterialApp(
      title: 'derby',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F7A3A)), useMaterial3: true),
      home: SetupScreen(given: url),
    );
  }
  return DerbyApp(client: RoomClient(url: url.trim())..init());
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(buildApp(serverUrl));
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
