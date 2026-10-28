import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txt_viewer/page_jump_dialog.dart';
import 'package:txt_viewer/pagination.dart';

const size = Size(360, 650), style = TextStyle(fontSize: 20, height: 1.7);
PageSession book() => PageSession(
  text: List.filled(1000, '소설의 한글 문장입니다. English.\n\n').join(),
  size: size,
  style: style,
  spacing: 12,
);
Future<void> openDialog(
  WidgetTester tester,
  PageSession session,
  void Function(PageJumpSelection?) receive,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => receive(
              await showDialog<PageJumpSelection>(
                context: context,
                builder: (_) => PageJumpDialog(session: session),
              ),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('열기'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'page-number lookup is exact and does not move before confirmation',
    () async {
      final pages = book();
      var start = 0;
      final expected = <PageRange>[];
      for (var i = 0; i < 8; i++) {
        final p = nextPage(pages.text, start, size, style, 12);
        expected.add(p);
        start = p.end;
      }
      final located = await pages.locatePage(8);
      expect(located!.number, 8);
      expect(located.range.start, expected.last.start);
      expect(pages.range.start, 0);
      expect(pages.cachedPageCount, 1);
      pages.seekOffset(located.range.start);
      expect(pages.range.end, expected.last.end);
      expect(pages.move(-1), isTrue);
      expect(pages.range.start, expected[6].start);
      expect(pages.move(1), isTrue);
      expect(pages.range.start, expected[7].start);
    },
  );
  test('out-of-range page clamps to the actual final page', () async {
    final pages = PageSession(
      text: '짧은 책',
      size: size,
      style: style,
      spacing: 12,
    );
    final located = await pages.locatePage(500);
    expect(located!.number, 1);
    expect(located.range.end, pages.text.length);
  });
  test(
    'page lookup cancellation after yielding keeps the current reading position',
    () async {
      final pages = book();
      pages.seekOffset(5000);
      var cancel = false;
      final pending = pages.locatePage(100000, cancelled: () => cancel);
      cancel = true;
      expect(await pending, isNull);
      expect(pages.range.start, 5000);
      expect(pages.cachedPageCount, 1);
    },
  );
  test('percentage endpoints and emoji boundaries remain valid', () {
    final pages = PageSession(
      text: '시작 📖 문장입니다.',
      size: size,
      style: style,
      spacing: 12,
    );
    pages.seekOffset(pages.text.indexOf('📖') + 1);
    expect(pages.range.start, pages.text.indexOf('📖'));
    pages.seekOffset(pages.text.length);
    expect(pages.range.end, pages.text.length);
    pages.seekOffset(0);
    expect(pages.range.start, 0);
  });
  testWidgets(
    'percentage jump returns a precise offset without precomputing the book',
    (tester) async {
      final pages = book();
      PageJumpSelection? selected;
      await openDialog(tester, pages, (value) => selected = value);
      await tester.enterText(find.byType(TextField).first, '75');
      await tester.pump();
      await tester.tap(find.text('위치로 이동'));
      await tester.pumpAndSettle();
      expect(selected!.offset, (pages.text.length * .75).floor());
      expect(pages.range.start, 0);
      expect(pages.cachedPageCount, 1);
    },
  );
  testWidgets(
    'invalid percentages are rejected and cancellation does not move',
    (tester) async {
      final pages = book();
      PageJumpSelection? selected;
      await openDialog(tester, pages, (value) => selected = value);
      for (final value in ['101', '-1', 'NaN']) {
        await tester.enterText(find.byType(TextField).first, value);
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '위치로 이동'))
              .onPressed,
          isNull,
        );
      }
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(pages.range.start, 0);
    },
  );
  testWidgets('numeric jump validates input and resolves the requested page', (
    tester,
  ) async {
    final pages = book();
    PageJumpSelection? selected;
    await openDialog(tester, pages, (value) => selected = value);
    await tester.enterText(find.byType(TextField).last, '0');
    await tester.ensureVisible(find.text('쪽으로 이동'));
    await tester.tap(find.text('쪽으로 이동'));
    await tester.pump();
    expect(find.textContaining('1~1,000,000'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '5');
    await tester.ensureVisible(find.text('쪽으로 이동'));
    await tester.tap(find.text('쪽으로 이동'));
    await tester.pumpAndSettle();
    expect(selected!.actualPage, 5);
    expect(selected!.requestedPage, 5);
    final expected = await pages.locatePage(5);
    expect(selected!.offset, expected!.range.start);
  });
}
