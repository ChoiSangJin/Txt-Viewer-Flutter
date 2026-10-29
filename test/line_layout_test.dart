import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txt_viewer/pagination.dart';
import 'pagination_reference.dart' as legacy;

const viewport = Size(360, 650);
const style = TextStyle(
  fontFamily: 'RIDIBatang',
  fontSize: 20,
  height: 1.7,
  letterSpacing: .2,
);
PageSession session(
  String text, {
  int offset = 0,
  Size size = viewport,
  TextStyle font = style,
  double spacing = 12,
}) => PageSession(
  text: text,
  offset: offset,
  size: size,
  style: font,
  spacing: spacing,
);
Future<Uint8List> raster(
  PageSession pages, {
  Color color = Colors.black,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);
  pages.lineLayout.paint(canvas, pages.range.layout!, color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    pages.size.width.ceil(),
    pages.size.height.ceil(),
  );
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

Future<Uint8List> referenceRaster(
  String text,
  TextStyle font,
  Size size,
) async {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: font.copyWith(color: Colors.black),
    ),
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  )..layout(maxWidth: size.width);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);
  canvas.clipRect(Offset.zero & size);
  painter.paint(canvas, Offset.zero);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  ))!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  painter.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'RIDIBatang': 'ridi.otf',
      'KoPubBatang': 'kopub.ttf',
      'Pretendard': 'pretendard.ttf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(rootBundle.load('assets/fonts/${entry.value}'));
      await loader.load();
    }
  });

  test(
    'full indexing reuses bounded blocks and reduces layout requests',
    () async {
      final cases = {
        'novel': List.filled(
          700,
          '한글 소설의 문장입니다. English words in a book.\n다음 문단입니다.\n\n',
        ).join(),
        'long-paragraph': List.filled(
          2000,
          '긴 문단 📖 Reading without hard line breaks. ',
        ).join(),
        'short-lines': List.filled(1000, '짧은 줄\n\n다음 줄\n').join(),
      };
      for (final entry in cases.entries) {
        legacy.legacyLayoutCalls = 0;
        final before = Stopwatch()..start();
        var offset = 0, oldPages = 0;
        while (offset < entry.value.length) {
          offset = legacy
              .legacyNextPage(entry.value, offset, viewport, style, 12)
              .end;
          oldPages++;
        }
        before.stop();
        final watch = Stopwatch()..start();
        final pages = session(entry.value);
        await pages.countAll(pause: Duration.zero);
        watch.stop();
        final calls = pages.lineLayout.layoutCalls;
        expect(
          calls,
          lessThan(legacy.legacyLayoutCalls / 4),
          reason: entry.key,
        );
        expect(
          pages.lineLayout.cachedBlocks,
          lessThanOrEqualTo(LineLayout.maxBlocks),
        );
        expect(pages.lineLayout.cachedCharacters, lessThanOrEqualTo(32768));
        expect(pages.pageEnds.last, entry.value.length);
        print(
          'LINE_BENCH ${entry.key} chars=${entry.value.length} oldPages=$oldPages newPages=${pages.totalPages} oldCalls=${legacy.legacyLayoutCalls} newCalls=$calls oldUs=${before.elapsedMicroseconds} newUs=${watch.elapsedMicroseconds}',
        );
        pages.dispose();
      }
    },
  );

  test(
    'all fonts preserve graphemes and complete text across canonical pages',
    () async {
      final text = List.filled(
        100,
        '가나다 e\u0301 👨‍👩‍👧‍👦 🇰🇷 📖 العربية English 긴 문장입니다.\n\n다음 줄입니다.\n',
      ).join();
      final boundaries = <int>{0};
      var offset = 0;
      for (final c in text.characters) {
        offset += c.length;
        boundaries.add(offset);
      }
      for (final family in ['RIDIBatang', 'KoPubBatang', 'Pretendard']) {
        for (final size in [const Size(240, 320), const Size(420, 760)]) {
          final pages = session(
            text,
            size: size,
            font: style.copyWith(fontFamily: family, fontSize: 26),
            spacing: 24,
          );
          await pages.countAll(pause: Duration.zero);
          expect(
            pages.pageEnds.every(boundaries.contains),
            isTrue,
            reason: family,
          );
          final chunks = <String>[];
          do {
            expect(pages.range.layout!.height, lessThanOrEqualTo(size.height));
            for (final slice in pages.range.layout!.slices) {
              expect(
                slice.targetTop + slice.height,
                lessThanOrEqualTo(size.height + .01),
              );
            }
            chunks.add(text.substring(pages.range.start, pages.range.end));
          } while (pages.move(1));
          expect(chunks.join(), text);
          pages.dispose();
        }
      }
    },
  );

  test(
    'painting reuses the measured lines without clipping or rewrapping',
    () async {
      final text = List.filled(
        350,
        '한글 소설 문장과 English words를 함께 읽습니다. ',
      ).join();
      for (final family in ['RIDIBatang', 'KoPubBatang', 'Pretendard']) {
        final pages = session(
          text,
          font: style.copyWith(fontFamily: family),
          spacing: 0,
        );
        await pages.countAll(pause: Duration.zero);
        for (var i = 0; i < 3; i++) {
          final actual = await raster(pages);
          final expected = await referenceRaster(
            text.substring(pages.range.start, pages.range.end),
            pages.style,
            pages.size,
          );
          expect(actual, orderedEquals(expected), reason: '$family page $i');
          pages.move(1);
        }
        pages.dispose();
      }
    },
  );

  test(
    'current image survives counter eviction, warm restore and theme changes',
    () async {
      final text = List.filled(
        1800,
        '달빛 아래 읽는 한글 소설입니다.\nEnglish 📖 다음 문단.\n\n',
      ).join();
      final pages = session(text, offset: 5000);
      final initial = await raster(pages);
      await pages.countAll(pause: Duration.zero);
      expect(await raster(pages), orderedEquals(initial));
      final saved = pages.pageEnds;
      final found = await pages.locatePage(80);
      pages.seekOffset(found!.range.start);
      final canonical = await raster(pages);
      final restored = session(text, offset: found.range.start);
      expect(restored.restorePagePrefix(saved), isTrue);
      restored.seekOffset(found.range.start);
      expect(await raster(restored), orderedEquals(canonical));
      expect(
        await raster(restored, color: Colors.red),
        isNot(orderedEquals(canonical)),
      );
      expect(await raster(restored), orderedEquals(canonical));
      pages.dispose();
      restored.dispose();
    },
  );

  test(
    'resumed anchor navigation remains contiguous after the index completes',
    () async {
      final text = List.filled(
        120,
        '한글 📖 English mixed paragraph.\n다음 줄\n\n',
      ).join();
      final pages = session(text, offset: 1263);
      final anchor = pages.range.start;
      await pages.countAll(pause: Duration.zero);
      final prefix = <String>[];
      while (pages.move(-1)) {
        prefix.insert(0, text.substring(pages.range.start, pages.range.end));
      }
      expect(prefix.join(), text.substring(0, anchor));
      final suffix = session(text, offset: anchor);
      await suffix.countAll(pause: Duration.zero);
      final after = <String>[];
      do {
        after.add(text.substring(suffix.range.start, suffix.range.end));
      } while (suffix.move(1));
      expect(prefix.join() + after.join(), text);
      pages.dispose();
      suffix.dispose();
    },
  );

  test(
    'paragraph gaps match independent painting and produce a readable preview',
    () async {
      final text = List.filled(
        40,
        '달빛 아래에서 읽는 이야기\n한글과 English 문장을 함께 읽습니다.\n\n새로운 문단이 시작됩니다.\n',
      ).join();
      final pages = session(text);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);
      canvas.clipRect(Offset.zero & pages.size);
      var y = 0.0;
      for (final paragraph
          in text.substring(pages.range.start, pages.range.end).split('\n')) {
        final painter = TextPainter(
          text: TextSpan(
            text: paragraph,
            style: style.copyWith(color: Colors.black),
          ),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout(maxWidth: viewport.width);
        painter.paint(canvas, Offset(0, y));
        y += painter.height + 12;
        painter.dispose();
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(360, 650);
      final expected = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      expect(await raster(pages), orderedEquals(expected));
      image.dispose();
      picture.dispose();
      final directory = Platform.environment['GOYO_PREVIEW_DIR'];
      if (directory != null) {
        final record = ui.PictureRecorder();
        final c = Canvas(record);
        c.drawColor(Colors.white, BlendMode.src);
        pages.lineLayout.paint(c, pages.range.layout!, Colors.black);
        final pic = record.endRecording();
        final img = await pic.toImage(360, 650);
        await Directory(directory).create(recursive: true);
        await File('$directory/line-layout-preview.png').writeAsBytes(
          (await img.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        );
        img.dispose();
        pic.dispose();
      }
      pages.dispose();
    },
  );

  test('resume within a combined emoji starts at the complete grapheme', () {
    const text = '앞 문장 👨‍👩‍👧‍👦 뒤 문장';
    final pages = session(text, offset: text.indexOf('👩'));
    expect(pages.range.start, text.indexOf('👨'));
    pages.dispose();
  });

  test('near-end opening never measures the book prefix', () {
    final text = List.filled(300000, '가').join();
    final pages = session(text, offset: 290000);
    expect(pages.range.start, 290000);
    expect(pages.lineLayout.measuredCharacters, lessThanOrEqualTo(4096));
    expect(pages.cachedPageCount, 1);
    pages.dispose();
  });
}
