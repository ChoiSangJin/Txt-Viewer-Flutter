import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txt_viewer/numeric_reading_setting.dart';

Widget setting({
  required String label,
  required double value,
  required double min,
  required double max,
  required ValueChanged<double> update,
}) => MaterialApp(
  home: Scaffold(
    body: StatefulBuilder(
      builder: (context, refresh) => NumericReadingSetting(
        label: label,
        value: value,
        min: min,
        max: max,
        onChanged: (next) {
          value = next;
          update(next);
          refresh(() {});
        },
      ),
    ),
  ),
);

void main() {
  testWidgets('typing waits for Apply and slider stays synchronized', (
    tester,
  ) async {
    final values = <double>[];
    await tester.pumpWidget(
      setting(label: '글자 크기', value: 20, min: 14, max: 36, update: values.add),
    );
    await tester.enterText(find.byType(TextField), '24.5');
    expect(values, isEmpty);
    await tester.tap(find.byTooltip('글자 크기 적용'));
    await tester.pump();
    expect(values, [24.5]);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 24.5);
    tester.widget<Slider>(find.byType(Slider)).onChanged!(28.2);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '28.2',
    );
  });

  testWidgets('invalid input never changes the saved setting', (tester) async {
    final values = <double>[];
    await tester.pumpWidget(
      setting(label: '글자 크기', value: 20, min: 14, max: 36, update: values.add),
    );
    for (final invalid in ['', '13.9', '36.1', 'NaN', 'Infinity', 'abc']) {
      await tester.enterText(find.byType(TextField), invalid);
      await tester.tap(find.byTooltip('글자 크기 적용'));
      await tester.pump();
      expect(find.text('14~36 사이의 숫자를 입력해 주세요.'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 20);
    }
    expect(values, isEmpty);
    await tester.enterText(find.byType(TextField), '36');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(values, [36]);
    expect(find.text('14~36 사이의 숫자를 입력해 주세요.'), findsNothing);
  });

  testWidgets('decimal keyboard Done accepts comma and normalizes precision', (
    tester,
  ) async {
    final values = <double>[];
    await tester.pumpWidget(
      setting(
        label: '줄 간격',
        value: 1.7,
        min: 1.2,
        max: 2.4,
        update: values.add,
      ),
    );
    await tester.enterText(find.byType(TextField), '1,855');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(values, [1.86]);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '1.86',
    );
  });
}
