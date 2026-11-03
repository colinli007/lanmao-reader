import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanmao_reader/ui/theme.dart';
import 'package:lanmao_reader/ui/tokens.dart';
import 'package:lanmao_reader/ui/widgets.dart';

Widget _wrap(Widget child) => MaterialApp(theme: appTheme(Brightness.light), home: Scaffold(body: Center(child: child)));

void main() {
  group('ValueStepper', () {
    Future<List<double>> pump(WidgetTester tester, double value) async {
      final changes = <double>[];
      await tester.pumpWidget(
        _wrap(ValueStepper(label: '字号', value: value, valueText: '${value.round()}', min: 12, max: 40, step: 1, onChanged: changes.add)),
      );
      return changes;
    }

    bool enabled(WidgetTester tester, String tooltip) =>
        tester.widget<IconButton>(find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton))).onPressed != null;

    testWidgets('加减一个步长', (tester) async {
      final changes = await pump(tester, 18);
      await tester.tap(find.byTooltip('增大字号'));
      await tester.tap(find.byTooltip('减小字号'));
      expect(changes, [19, 17]);
      expect(find.text('18'), findsOneWidget);
    });

    testWidgets('到上限时「+」不可用', (tester) async {
      await pump(tester, 40);
      expect(enabled(tester, '增大字号'), isFalse);
      expect(enabled(tester, '减小字号'), isTrue);
    });

    testWidgets('到下限时「−」不可用', (tester) async {
      await pump(tester, 12);
      expect(enabled(tester, '减小字号'), isFalse);
    });
  });

  group('PresetPicker', () {
    Future<List<double>> pump(WidgetTester tester, double? selected) async {
      final picks = <double>[];
      await tester.pumpWidget(
        _wrap(
          PresetPicker<double>(
            options: [
              for (final (value, label) in [(1.5, '紧凑'), (1.8, '适中'), (2.2, '宽松')])
                (value: value, label: label, child: Text(label), color: null),
            ],
            selected: selected,
            onSelected: picks.add,
          ),
        ),
      );
      return picks;
    }

    bool isSelected(WidgetTester tester, String label) => 
        tester.getSemantics(find.bySemanticsLabel(label)).hasFlag(SemanticsFlag.isSelected);

    testWidgets('标出选中项，点别的项返回它的值', (tester) async {
      final picks = await pump(tester, 1.8);
      expect(isSelected(tester, '适中'), isTrue);
      expect(isSelected(tester, '宽松'), isFalse);
      await tester.tap(find.text('宽松'));
      expect(picks, [2.2]);
    });

    testWidgets('没有选中项时都不标出', (tester) async {
      await pump(tester, null);
      for (final label in ['紧凑', '适中', '宽松']) {
        expect(isSelected(tester, label), isFalse);
      }
    });
  });

  group('showActionSheet', () {
    Future<Future<String?>> open(WidgetTester tester) async {
      late Future<String?> result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => result = showActionSheet<String>(
                context,
                message: '网络错误',
                items: [(value: 'detail', label: '详情', danger: false), (value: 'remove', label: '移出书架', danger: true)],
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('选一项返回它的值', (tester) async {
      final result = await open(tester);
      expect(find.text('网络错误'), findsOneWidget);
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();
      expect(await result, 'detail');
    });

    testWidgets('点「取消」返回 null', (tester) async {
      final result = await open(tester);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await result, isNull);
    });
  });

  group('showConfirmDialog', () {
    Future<Future<bool>> open(WidgetTester tester, {bool danger = false, bool enabled = true}) async {
      late Future<bool> result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => result = showConfirmDialog(
                context,
                title: '删除 2 个书源？',
                message: '书架上来自这些书源的书会保留。',
                confirmLabel: '删除',
                danger: danger,
                confirmEnabled: enabled,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      return result;
    }

    FilledButton confirm(WidgetTester tester) => tester.widget<FilledButton>(find.widgetWithText(FilledButton, '删除'));

    testWidgets('确认返回 true，取消返回 false', (tester) async {
      var result = await open(tester);
      expect(find.text('书架上来自这些书源的书会保留。'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);

      result = await open(tester);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    testWidgets('危险操作的确认按钮用危险色', (tester) async {
      await open(tester, danger: true);
      final background = confirm(tester).style!.backgroundColor!.resolve({});
      expect(background, AppColors.light.danger);
    });

    testWidgets('confirmEnabled 为假时确认按钮不可用', (tester) async {
      await open(tester, enabled: false);
      expect(confirm(tester).onPressed, isNull);
    });
  });
}
