import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txt_viewer/pagination.dart';
import 'package:txt_viewer/page_jump_dialog.dart';
import 'package:txt_viewer/main.dart';
import 'package:txt_viewer/model.dart';
import 'package:txt_viewer/platform.dart';

const size = Size(360, 650), style = TextStyle(fontSize: 20, height: 1.7);
final text = List.filled(80, '한글 소설 📖 English 문장입니다.\n다음 문단\n\n').join();
PageSession session({int offset = 0}) => PageSession(
  text: text,
  offset: offset,
  size: size,
  style: style,
  spacing: 12,
);
List<int> referenceEnds() {
  final result = <int>[];
  var start = 0;
  while (start < text.length) {
    start = nextPage(text, start, size, style, 12).end;
    result.add(start);
  }
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'background count matches canonical pages and does not change visible content',
    () async {
      final pages = session(offset: 1263);
      final before = pages.range;
      expect(pages.totalPages, isNull);
      expect(pages.cachedPageCount, 1);
      await pages.countAll(pause: Duration.zero);
      expect(pages.pageEnds, referenceEnds());
      expect(pages.totalPages, referenceEnds().length);
      expect(pages.range.start, before.start);
      expect(pages.range.end, before.end);
      final expected =
          referenceEnds().indexWhere((end) => end > before.start) + 1;
      expect(pages.currentPage, expected);
      expect(pages.indexProgress, 1);
      pages.dispose();
    },
  );
  test(
    'restored counts are immediate and navigation returns to the exact resumed anchor',
    () {
      final ends = referenceEnds();
      final pages = session(offset: 1263);
      final anchor = pages.range.start;
      expect(pages.restorePageEnds(ends), isTrue);
      expect(pages.totalPages, ends.length);
      final current = pages.currentPage!;
      expect(pages.move(-1), isTrue);
      expect(pages.currentPage, current - 1);
      expect(pages.move(1), isTrue);
      expect(pages.range.start, anchor);
      expect(pages.currentPage, current);
      expect(pages.move(1), isTrue);
      expect(pages.currentPage, current + 1);
      pages.dispose();
    },
  );
  test(
    'percentage targets map to page numbers including first and last pages',
    () {
      final ends = referenceEnds();
      final pages = session();
      pages.restorePageEnds(ends);
      expect(pages.pageNumberAt(0), 1);
      expect(pages.pageNumberAt(text.length), ends.length);
      expect(pages.pageNumberAt(ends[0]), 2);
      expect(
        pages.pageNumberAt(text.length ~/ 2),
        ends.indexWhere((e) => e > text.length ~/ 2) + 1,
      );
      pages.dispose();
    },
  );
  test('invalid or stale boundaries are rejected', () {
    final pages = session(offset: 1263);
    for (final ends in [
      <int>[],
      [text.length - 1],
      [500, 300, text.length],
      [-1, text.length],
      [0, text.length],
    ]) {
      expect(pages.restorePageEnds(ends), isFalse);
    }
    final split = text.indexOf('📖') + 1;
    expect(pages.restorePageEnds([split, text.length]), isFalse);
    expect(pages.totalPages, isNull);
    pages.dispose();
  });
  test('disposing stops the counter and releases its scheduled wait', () async {
    final pages = session();
    final counting = pages.countAll(pause: const Duration(seconds: 30));
    expect(pages.totalPages, isNull);
    final partial = pages.indexedPages;
    pages.dispose();
    await counting;
    expect(pages.indexedPages, partial);
    expect(pages.totalPages, isNull);
  });
  test(
    'numeric lookup and background indexing share a consistent prefix',
    () async {
      final pages = session(offset: 1263);
      final count = pages.countAll(pause: Duration.zero);
      final lookup = await pages.locatePage(8);
      await count;
      expect(lookup!.number, 8);
      expect(lookup.range.end, referenceEnds()[7]);
      expect(pages.pageEnds, referenceEnds());
      expect(pages.range.start, 1263);
      pages.dispose();
    },
  );
  testWidgets('move dialog shows current/total and previews the target page', (
    tester,
  ) async {
    final pages = session();
    final ends = referenceEnds();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('열기'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PageJumpDialog(session: pages),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('page-count-summary')))
          .data,
      contains('계산 중'),
    );
    pages.restorePageEnds(ends);
    await tester.pump();
    expect(find.text('현재 1쪽 / 전체 ${ends.length}쪽'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '50');
    await tester.pump();
    final expected = pages.pageNumberAt(text.length ~/ 2);
    expect(find.text('이동할 쪽: $expected / ${ends.length}쪽'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    pages.dispose();
  });
  testWidgets(
    'reopening the reader uses completed counts from its layout cache',
    (tester) async {
      final platform = CachedPlatform();
      final model = LibraryModel(platform);
      model.books.add(Book('cached', '쪽수 캐시.txt'));
      await tester.pumpWidget(ReaderApp(model: model));
      await tester.tap(find.text('쪽수 캐시.txt'));
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 30));
        if (find.byTooltip('읽기 설정').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty)
          break;
      }
      await tester.pumpAndSettle();
      expect(platform.writes, 1);
      final total = platform.cached.values.single.length;
      expect(total, greaterThan(1));
      await tester.tap(find.byTooltip('읽기 설정'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('서재로 돌아가기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('쪽수 캐시.txt'));
      await tester.pumpAndSettle();
      expect(platform.hits, 1);
      expect(platform.writes, 1);
      expect(find.textContaining('1 / $total쪽'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

class CachedPlatform extends ReaderPlatform {
  final cached = <String, List<int>>{};
  int writes = 0, hits = 0;
  @override
  Future<String> readBook(String id) async => text;
  @override
  Future<void> saveState(String value) async {}
  @override
  Future<void> setReading(bool value) async {}
  @override
  Future<Map<String, dynamic>?> loadPageIndex(String id, String layout) async {
    if (cached.containsKey(layout)) hits++;
    return {'token': 'test-token', 'ends': cached[layout]};
  }

  @override
  Future<void> savePageIndex(
    String id,
    String layout,
    String token,
    List<int> ends,
  ) async {
    writes++;
    cached[layout] = List.of(ends);
  }
}
