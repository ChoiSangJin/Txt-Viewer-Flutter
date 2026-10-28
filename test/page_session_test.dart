import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txt_viewer/pagination.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const style = TextStyle(fontSize: 20, height: 1.7);
  const size = Size(360, 650);
  PageSession session(String text, {int offset = 0}) => PageSession(
    text: text,
    size: size,
    style: style,
    spacing: 12,
    offset: offset,
  );
  void fits(String text, PageRange range) {
    final painter = TextPainter(
      text: readingSpan(text.substring(range.start, range.end), style, 12),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: size.width);
    expect(painter.height, lessThanOrEqualTo(size.height));
    painter.dispose();
    expect(
      text.substring(range.start, range.end).runes,
      isNot(contains(0xFFFD)),
    );
  }

  test('long-book startup and near-end resume each measure just one page', () {
    final text = List.filled(
      1800,
      '한글 소설의 문장입니다. Reading a novel offline.\n다음 문단을 읽습니다.\n\n',
    ).join();
    final timer = Stopwatch()..start();
    final first = session(text);
    timer.stop();
    final resumedTimer = Stopwatch()..start();
    final resumed = session(text, offset: text.length - 1200);
    resumedTimer.stop();
    expect(first.cachedPageCount, 1);
    expect(first.range.start, 0);
    expect(resumed.cachedPageCount, 1);
    expect(resumed.range.start, text.length - 1200);
    expect(first.range.end, lessThan(12000));
    expect(resumed.canPrevious, isTrue);
    print(
      'ON_DEMAND chars=${text.length} startupPages=${first.cachedPageCount} firstPageUs=${timer.elapsedMicroseconds} nearEndUs=${resumedTimer.elapsedMicroseconds}',
    );
  });

  test(
    'forward navigation preserves all content and cached reverse navigation',
    () {
      final text = List.filled(
        100,
        '한글 English 📖 한 문단입니다.\n\n다음 줄을 읽습니다.\n',
      ).join();
      final pages = session(text);
      final ranges = <PageRange>[];
      do {
        fits(text, pages.range);
        ranges.add(pages.range);
      } while (pages.move(1));
      expect(ranges.map((r) => text.substring(r.start, r.end)).join(), text);
      expect(pages.canNext, isFalse);
      expect(pages.progress, 1);
      for (var i = ranges.length - 2; i >= 0; i--) {
        expect(pages.move(-1), isTrue);
        expect(pages.range.start, ranges[i].start);
        expect(pages.range.end, ranges[i].end);
      }
      expect(pages.canPrevious, isFalse);
      expect(pages.move(-1), isFalse);
      expect(pages.cachedPageCount, ranges.length);
    },
  );

  test(
    'backward pagination from the end preserves text and fits the viewport',
    () {
      final text = List.filled(150, '한글과 English 📖\n문단 여백을 유지합니다.\n\n').join();
      var end = text.length;
      final chunks = <String>[];
      while (end > 0) {
        final range = previousPage(text, end, size, style, 12);
        expect(range.start, lessThan(end));
        expect(range.end, end);
        fits(text, range);
        chunks.insert(0, text.substring(range.start, range.end));
        end = range.start;
      }
      expect(chunks.join(), text);
    },
  );

  test(
    'resuming in the middle supports immediate previous and exact return',
    () {
      final text = List.filled(1000, '오래된 소설의 다음 문단입니다.\n').join();
      final pages = session(text, offset: 15000);
      final original = pages.range;
      expect(pages.cachedPageCount, 1);
      expect(pages.move(-1), isTrue);
      expect(pages.range.end, original.start);
      fits(text, pages.range);
      expect(pages.cachedPageCount, 2);
      expect(pages.move(1), isTrue);
      expect(pages.range.start, original.start);
      expect(pages.range.end, original.end);
    },
  );

  test(
    'prefix and suffix around a resumed anchor have no gaps or duplicates',
    () {
      final text = List.filled(
        80,
        '한글 📖 English mixed paragraph.\n다음 줄\n\n',
      ).join();
      final prefix = session(text, offset: 1263);
      final anchor = prefix.range.start;
      final before = <String>[];
      while (prefix.move(-1)) {
        before.insert(0, text.substring(prefix.range.start, prefix.range.end));
      }
      final suffix = session(text, offset: anchor);
      final after = <String>[];
      do {
        after.add(text.substring(suffix.range.start, suffix.range.end));
      } while (suffix.move(1));
      expect(before.join() + after.join(), text);
    },
  );

  test('reflow preserves the character anchor without indexing the prefix', () {
    final text = List.filled(1000, '소설 문단입니다.\n').join();
    final original = session(text, offset: 4500);
    final reflow = PageSession(
      text: text,
      offset: original.range.start,
      size: size,
      style: style.copyWith(fontSize: 32, height: 2.2),
      spacing: 24,
    );
    expect(reflow.range.start, original.range.start);
    expect(reflow.cachedPageCount, 1);
    expect(reflow.range.end, lessThan(original.range.end));
  });

  test('resume inside an emoji aligns to the complete surrogate pair', () {
    const text = '첫 줄 📖 다음 문단입니다.';
    final emoji = text.indexOf('📖');
    final pages = session(text, offset: emoji + 1);
    expect(pages.range.start, emoji);
    fits(text, pages.range);
  });

  test('long unbroken text stays bounded when opening near the end', () {
    final text = List.filled(250000, '가').join();
    final pages = session(text, offset: 240000);
    expect(pages.range.start, 240000);
    expect(pages.range.end, greaterThan(240000));
    expect(pages.range.end - pages.range.start, lessThanOrEqualTo(12000));
    fits(text, pages.range);
  });

  test('empty text and out-of-range restored offsets are safe', () {
    final empty = session('');
    expect(empty.canNext, isFalse);
    expect(empty.canPrevious, isFalse);
    expect(empty.progress, 0);
    expect(empty.range.end, 0);
    const text = '짧아진 소설';
    final end = session(text, offset: 9000);
    expect(end.range.start, 0);
    expect(end.range.end, text.length);
    expect(end.canNext, isFalse);
    expect(end.canPrevious, isFalse);
    expect(session(text, offset: -20).range.start, 0);
  });
}
