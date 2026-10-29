import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txt_viewer/pagination.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const style = TextStyle(fontSize: 20, height: 1.7);
  const size = Size(300, 500);
  test('pages preserve mixed Korean, English, emoji and paragraph breaks', () {
    final text = List.filled(
      100,
      '이야기의 시작 📖 A quiet night.\n다음 문단입니다.\n\n',
    ).join();
    final pages = <String>[];
    var start = 0;
    while (start < text.length) {
      final page = nextPage(text, start, size, style, 12);
      expect(page.end, greaterThan(start));
      final content = text.substring(page.start, page.end);
      expect(content.runes, isNot(contains(0xFFFD)));
      expect(page.layout!.height, lessThanOrEqualTo(size.height));
      for (final slice in page.layout!.slices) {
        expect(
          slice.targetTop + slice.height,
          lessThanOrEqualTo(size.height + .01),
        );
      }
      pages.add(content);
      start = page.end;
    }
    expect(pages.length, greaterThan(1));
    expect(pages.join(), text);
  });
  test('larger typography and paragraph spacing reduce page capacity', () {
    final text = List.filled(200, '글자와 줄 간격을 조절합니다.\n').join();
    final normal = nextPage(text, 0, size, style, 0);
    final large = nextPage(
      text,
      0,
      size,
      style.copyWith(fontSize: 32, height: 2.2),
      32,
    );
    expect(large.end, lessThan(normal.end));
  });
  test('end of book is retained without an extra blank page', () {
    const text = '마지막 페이지';
    final page = nextPage(text, 0, size, style, 12);
    expect(page.start, 0);
    expect(page.end, text.length);
  });
}
