import 'package:derby/src/screens/join_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<String>> pump(WidgetTester tester, {String? error}) async {
    final joined = <String>[];
    await tester.pumpWidget(MaterialApp(home: JoinScreen(onJoin: joined.add, error: error)));
    return joined;
  }

  FilledButton button(WidgetTester tester) => tester.widget<FilledButton>(find.widgetWithText(FilledButton, '参加'));

  testWidgets('空や空白だけでは参加できない', (tester) async {
    final joined = await pump(tester);
    expect(button(tester).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(button(tester).onPressed, isNull);
    await tester.enterText(find.byType(TextField), ' 　 ');
    await tester.pump();
    expect(button(tester).onPressed, isNull);
    expect(joined, isEmpty);
  });

  testWidgets('前後の空白を除いた名前で参加する', (tester) async {
    final joined = await pump(tester);
    await tester.enterText(find.byType(TextField), '  たろう  ');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '参加'));
    expect(joined, ['たろう']);
  });

  testWidgets('13 文字は参加できず、案内が出る', (tester) async {
    final joined = await pump(tester);
    await tester.enterText(find.byType(TextField), 'あ' * 13);
    await tester.pump();
    expect(button(tester).onPressed, isNull);
    expect(find.text('12文字までです'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'あ' * 12);
    await tester.pump();
    expect(button(tester).onPressed, isNotNull);
    expect(find.text('12文字までです'), findsNothing);
    expect(joined, isEmpty);
  });

  testWidgets('絵文字 12 個は 12 文字として参加できる', (tester) async {
    final joined = await pump(tester);
    await tester.enterText(find.byType(TextField), '🐎' * 12);
    await tester.pump();
    expect(button(tester).onPressed, isNotNull);
    await tester.tap(find.widgetWithText(FilledButton, '参加'));
    expect(joined, ['🐎' * 12]);
    await tester.enterText(find.byType(TextField), '🐎' * 13);
    await tester.pump();
    expect(button(tester).onPressed, isNull);
  });

  testWidgets('エラーを表示する', (tester) async {
    await pump(tester, error: 'その名前は使われています');
    expect(find.text('その名前は使われています'), findsOneWidget);
  });
}
