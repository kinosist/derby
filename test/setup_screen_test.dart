import 'package:derby/main.dart';
import 'package:derby/src/screens/setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('接続先が指定されていないときは、設定方法を案内する', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SetupScreen()));
    expect(find.textContaining('接続先が設定されていません'), findsOneWidget);
    expect(find.textContaining('Additional run args'), findsOneWidget);
    expect(find.textContaining('--dart-define=SERVER_URL='), findsWidgets);
    expect(tester.takeException(), isNull); // 小さい画面でもはみ出さない
  });

  test('接続先の判定: 空なら未設定、ws:// か wss:// で始まれば有効', () {
    expect(isValidServerUrl(''), false);
    expect(isValidServerUrl('   '), false);
    expect(isValidServerUrl('https://example.com/ws'), false);
    expect(isValidServerUrl('example.com/ws'), false);
    expect(isValidServerUrl('wss://example.com/ws'), true);
    expect(isValidServerUrl('ws://10.0.2.2:8787/ws'), true);
  });

  testWidgets('アプリの入口: 接続先がなければ案内、あれば参加画面', (tester) async {
    await tester.pumpWidget(buildApp(''));
    expect(find.byType(SetupScreen), findsOneWidget);
  });
}
