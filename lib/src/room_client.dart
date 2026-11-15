// サーバーとの接続。自動再接続と、本人情報(id・名前)の保存を受け持つ。

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  WebSocketTransport(Uri uri) : _channel = WebSocketChannel.connect(uri);
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

  void placeBet(int horse, int amount) {
    _lastError = null;
    _send({'t': 'bet', 'horse': horse, 'amount': amount});
    _notify();
  }

  void cancelBet() {
    _lastError = null;
    _send({'t': 'cancelBet'});
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
      await transport.ready;
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
    _lastError = error;
    _notify();
  }
}
