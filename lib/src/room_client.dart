// サーバーとの接続。自動再接続と、本人情報(id・名前)の保存を受け持つ。

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'protocol.dart';

enum ConnStatus { disconnected, connecting, connected }

/// 通信路。テストで差し替えられるよう、WebSocket をこの形に包む。
abstract class Transport {
  Stream<String> get messages;
  Future<void> get ready;
  int? get closeCode;
  void send(String text);
  Future<void> close();
}

class WebSocketTransport implements Transport {
  // pingInterval: 応答のなくなった接続(Wi-Fi が黙って切れた場合など)を検出して閉じ、再接続に回す。
  WebSocketTransport(Uri uri)
      : _channel = IOWebSocketChannel.connect(
          uri,
          pingInterval: const Duration(seconds: 5),
          connectTimeout: _connectTimeout,
        );
  final WebSocketChannel _channel;

  @override
  Stream<String> get messages => _channel.stream.where((e) => e is String).cast<String>();
  @override
  Future<void> get ready => _channel.ready;
  @override
  int? get closeCode => _channel.closeCode;
  @override
  void send(String text) => _channel.sink.add(text);
  @override
  Future<void> close() => _channel.sink.close();
}

const _idKey = 'derby.id';
const _nameKey = 'derby.name';
const _closeReplaced = 4000;
const _connectTimeout = Duration(seconds: 8);

class RoomClient extends ChangeNotifier {
  RoomClient({
    required this.url,
    Transport Function(Uri)? connect,
    SharedPreferences? prefs,
    int Function()? nowMs,
  })  : _connect = connect ?? WebSocketTransport.new,
        _prefs = prefs,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String url;
  final Transport Function(Uri) _connect;
  final int Function() _nowMs;
  SharedPreferences? _prefs;

  ConnStatus _status = ConnStatus.disconnected;
  RoomView? _view;
  String? _id;
  String? _savedName;
  String? _lastError;
  OddsTable? _oddsTable;
  int _clockOffsetMs = 0;

  /// 参加したい名前。null なら部屋に入るつもりがない(接続も再接続もしない)。
  String? _wantedName;
  Transport? _transport;
  StreamSubscription<String>? _subscription;
  Timer? _retryTimer;
  int _retryMs = 1000;
  bool _disposed = false;

  ConnStatus get status => _status;
  RoomView? get view => _view;
  String? get savedName => _savedName;

  /// 部屋に入ろうとしている(参加を押した、または参加済み)。つながっていなければ再接続を続けている。
  bool get wantsRoom => _wantedName != null;

  /// 単勝以外の倍率表(賭け受付が始まるときに届く)。view.raceKey と一致するものだけ使うこと。
  OddsTable? get oddsTable => _oddsTable;

  /// 直近のエラーの文言。次の操作で消える。
  String? get lastError => _lastError;

  /// サーバー時刻 − 端末の時刻
  int get clockOffsetMs => _clockOffsetMs;
  int serverNowMs() => _nowMs() + _clockOffsetMs;

  /// 保存済みの id・名前を読む。名前があれば自動で接続して参加する。
  Future<void> init() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    _id = prefs.getString(_idKey);
    if (_id == null) {
      _id = _newId();
      await prefs.setString(_idKey, _id!);
    }
    _savedName = prefs.getString(_nameKey);
    if (_savedName != null) {
      _wantedName = _savedName;
      _open();
    }
    _notify();
  }

  void join(String name) {
    _lastError = null;
    _wantedName = name.trim();
    if (_status == ConnStatus.connected) {
      _sendJoin();
    } else if (_status == ConnStatus.disconnected) {
      _retryTimer?.cancel();
      _open();
    }
    _notify();
  }

  /// 馬券を 1 点買う。同じ種類・同じ馬の馬券があれば、金額を置き換える。
  void placeTicket(BetType type, List<int> horses, int amount) {
    _lastError = null;
    if (_view?.raceKey == null && type == BetType.win && horses.length == 1) {
      // 古いサーバー(単勝 1 点だけ)向けの形式
      _send({'t': 'bet', 'horse': horses[0], 'amount': amount});
    } else {
      _send({'t': 'bet', 'type': type.wire, 'horses': horses, 'amount': amount});
    }
    _notify();
  }

  /// 予想屋に料金を払って、予想を聞く。
  void buyTip(String tipsterId) {
    _lastError = null;
    _send({'t': 'buyTip', 'id': tipsterId});
    _notify();
  }

  /// 馬券を 1 点取り消す。
  void cancelTicket(String ticketId) {
    _lastError = null;
    // 古いサーバー(raceKey を送らない)は単勝 1 点だけなので、id を指定せずに取り消す。
    _send(_view?.raceKey == null ? {'t': 'cancelBet'} : {'t': 'cancelBet', 'id': ticketId});
    _notify();
  }

  /// 保存した名前を消して切断する(参加画面に戻る)。
  void leave() => _leaveRoom(null);

  @visibleForTesting
  void debugSetView(RoomView v, {int clockOffsetMs = 0}) {
    _view = v;
    _clockOffsetMs = clockOffsetMs;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _closeTransport();
    super.dispose();
  }

  // ---- 内部 ----

  static String _newId() {
    final random = Random.secure();
    return [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _send(Map<String, dynamic> message) {
    if (_status == ConnStatus.connected) _transport?.send(jsonEncode(message));
  }

  void _sendJoin() => _send({'t': 'join', 'id': _id ?? '', 'name': _wantedName});

  Future<void> _open() async {
    if (_status != ConnStatus.disconnected || _wantedName == null) return;
    _status = ConnStatus.connecting;
    final Transport transport;
    try {
      transport = _connect(Uri.parse(url));
    } catch (_) {
      _onClosed(null);
      return;
    }
    _transport = transport;
    _subscription = transport.messages.listen(
      (text) => _onMessage(transport, text),
      onDone: () => _onClosed(transport),
      onError: (Object _) => _onClosed(transport),
      cancelOnError: true,
    );
    try {
      // 応答のないネットワークでは接続の試行が固まることがある。打ち切って再試行に回す。
      await transport.ready.timeout(_connectTimeout);
    } catch (_) {
      _onClosed(transport);
      return;
    }
    if (_disposed || _transport != transport) return;
    _status = ConnStatus.connected;
    if (_wantedName != null) _sendJoin();
    _notify();
  }

  void _closeTransport() {
    _subscription?.cancel();
    _subscription = null;
    final transport = _transport;
    _transport = null;
    // 閉じ終わるのは待たない。失敗しても、もう使わない接続なので無視してよい。
    if (transport != null) unawaited(transport.close().catchError((Object _) {}));
  }

  void _onClosed(Transport? transport) {
    if (_disposed || (transport != null && transport != _transport)) return;
    final code = transport?.closeCode;
    _closeTransport();
    _status = ConnStatus.disconnected;
    if (code == _closeReplaced) {
      // 同じ名前・同じ id の別の接続に置き換えられた。張り直すと奪い合いになるのでやめる。
      _leaveRoom('ほかの画面で同じ名前が使われたため、接続を終了しました');
      return;
    }
    if (_wantedName != null) {
      _retryTimer?.cancel();
      _retryTimer = Timer(Duration(milliseconds: _retryMs), _open);
      _retryMs = min(_retryMs * 2, 5000);
    }
    _notify();
  }

  void _onMessage(Transport transport, String text) {
    if (transport != _transport) return;
    final Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return;
      message = decoded;
    } catch (_) {
      return;
    }
    switch (message['t']) {
      case 'state':
        final RoomView view;
        try {
          view = RoomView.fromJson(message);
        } catch (_) {
          return; // 読めないスナップショットは捨て、前の表示を保つ
        }
        _view = view;
        _clockOffsetMs = view.serverNow - _nowMs();
        _retryMs = 1000;
        final me = view.me;
        if (me != null) _remember(me.id, me.name);
        _notify();
      case 'odds':
        try {
          _oddsTable = OddsTable.fromJson(message);
        } catch (_) {
          return;
        }
        _notify();
      case 'error':
        final code = message['code'];
        final errorText = message['message'] is String ? message['message'] as String : 'エラーが起きました';
        if (code == 'kicked' || code == 'name_taken' || code == 'bad_name' || code == 'room_full') {
          _leaveRoom(errorText);
        } else {
          _lastError = errorText;
          _notify();
        }
    }
  }

  void _remember(String id, String name) {
    final prefs = _prefs;
    if (id != _id) {
      _id = id;
      prefs?.setString(_idKey, id);
    }
    if (name != _savedName) {
      _savedName = name;
      prefs?.setString(_nameKey, name);
    }
  }

  void _leaveRoom(String? error) {
    _wantedName = null;
    _savedName = null;
    _prefs?.remove(_nameKey);
    _retryTimer?.cancel();
    _closeTransport();
    _status = ConnStatus.disconnected;
    _view = null;
    _oddsTable = null;
    _lastError = error;
    _notify();
  }
}
