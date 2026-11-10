import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txt_viewer/main.dart';
import 'package:txt_viewer/model.dart';
import 'package:txt_viewer/platform.dart';

class FakePlatform extends ReaderPlatform {
  String? state;
  String text = List.filled(150, '한글과 English 소설의 한 문단입니다.\n').join();
  @override
  Future<String?> loadState() async => state;
  @override
  Future<void> saveState(String value) async {
    state = value;
  }

  @override
  Future<void> setReading(bool enabled) async {}
  @override
  Future<String> readBook(String id) async => text;
  @override
  Future<Map<String, dynamic>?> pickBook() async => {
    'id': 'test-book',
    'name': '이야기.txt',
    'text': text,
  };
}

void main() {
  test('settings and reading offset survive a new model', () async {
    final platform = FakePlatform();
    final original = LibraryModel(platform);
    original.books.add(Book('book', '이야기.txt', offset: 123));
    original.settings.theme = ReaderTheme.black;
    original.settings.font = 'Pretendard';
    original.settings.paragraphSpace = 24;
    await original.save();
    final restored = LibraryModel(platform);
    await restored.load();
    expect(restored.books.single.offset, 123);
    expect(restored.settings.font, 'Pretendard');
    expect(restored.settings.theme, ReaderTheme.black);
    expect(restored.settings.paragraphSpace, 24);
    expect(jsonDecode(platform.state!)['books'], hasLength(1));
  });
  testWidgets(
    'numeric reading settings apply, preserve position and persist with keyboard open',
    (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final platform = FakePlatform();
      final model = LibraryModel(platform);
      model.books.add(Book('numeric', '숫자 설정.txt', offset: 200));
      await tester.pumpWidget(ReaderApp(model: model));
      await tester.tap(find.text('숫자 설정.txt'));
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 30));
        if (find.byTooltip('읽기 설정').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty)
          break;
      }
      final anchor = model.books.single.offset;
      await tester.tap(find.byTooltip('읽기 설정'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      for (var i = 0; i < 3; i++) {
        await tester.ensureVisible(fields.at(i));
        await tester.enterText(fields.at(i), ['25.5', '1.85', '0'][i]);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(model.settings.fontSize, 25.5);
      expect(model.settings.lineHeight, 1.85);
      expect(model.settings.paragraphSpace, 0);
      expect(model.books.single.offset, anchor);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('설정 닫기'));
      await tester.tap(find.byTooltip('설정 닫기'));
      await tester.pumpAndSettle();
      final restored = LibraryModel(platform);
      await restored.load();
      expect(restored.settings.fontSize, 25.5);
      expect(restored.settings.lineHeight, 1.85);
      expect(restored.settings.paragraphSpace, 0);
      expect(restored.books.single.offset, anchor);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets('import, next page, volume previous, and return to library', (
    tester,
  ) async {
    final model = LibraryModel(FakePlatform());
    await tester.pumpWidget(ReaderApp(model: model));
    expect(find.text('첫 번째 이야기를 추가해 보세요'), findsOneWidget);
    await tester.tap(find.text('TXT 불러오기'));
    // Pagination yields while loading bundled fonts and measuring long text.
    for (var i = 0; i < 80; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 30));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byTooltip('다음 페이지').evaluate().isNotEmpty)
        break;
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byTooltip('다음 페이지'));
    await tester.pump();
    expect(model.books.single.offset, greaterThan(0));
    final message = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('volume', 'previous'),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'txt_viewer/storage',
      message,
      (_) {},
    );
    await tester.pump();
    expect(model.books.single.offset, 0);
    await tester.tap(find.byTooltip('읽기 설정'));
    await tester.pumpAndSettle();
    expect(find.text('AMOLED 블랙'), findsOneWidget);
    await tester.ensureVisible(find.text('AMOLED 블랙'));
    await tester.tap(find.text('AMOLED 블랙'));
    await tester.pumpAndSettle();
    expect(model.settings.theme, ReaderTheme.black);
    await tester.ensureVisible(find.text('서재로 돌아가기'));
    await tester.tap(find.text('서재로 돌아가기'));
    await tester.pumpAndSettle();
    expect(find.text('이야기.txt'), findsOneWidget);
  });
  testWidgets('each reading theme paints its own page colour', (tester) async {
    final model = LibraryModel(FakePlatform());
    await tester.pumpWidget(ReaderApp(model: model));
    for (final entry in {
      ReaderTheme.light: const Color(0xFFF8F4EA),
      ReaderTheme.sepia: const Color(0xFFF1E7D0),
      ReaderTheme.dark: const Color(0xFF1E1E1E),
      ReaderTheme.green: const Color(0xFF1B2A22),
      ReaderTheme.black: Colors.black,
    }.entries) {
      model.settings.theme = entry.key;
      model.changed();
      await tester.pumpAndSettle();
      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(
        theme.scaffoldBackgroundColor,
        entry.value,
        reason: '${entry.key}',
      );
    }
  });
  test('the last read page survives a new model', () async {
    final platform = FakePlatform();
    final original = LibraryModel(platform);
    original.books.add(
      Book('paged', '쪽수.txt', offset: 900)
        ..page = 3
        ..pages = 40,
    );
    original.books.add(Book('unknown', '모름.txt'));
    await original.save();
    final restored = LibraryModel(platform);
    await restored.load();
    expect(restored.books.first.page, 3);
    expect(restored.books.first.pages, 40);
    expect(restored.books.last.page, isNull);
  });
  testWidgets(
    'tapping the page only turns pages and history shows the current page',
    (tester) async {
      final platform = FakePlatform();
      final model = LibraryModel(platform);
      final book = Book('tap-book', '탭 넘김.txt');
      model.books.add(book);
      await tester.pumpWidget(ReaderApp(model: model));
      expect(find.text('새로운 이야기'), findsOneWidget);
      await tester.tap(find.text(book.name));
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 30));
        if (book.pages != null) break;
      }
      expect(book.page, 1);
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      // The centre used to open the settings sheet; it now belongs to "next".
      await tester.tapAt(Offset(size.width * .55, size.height * .5));
      await tester.pump();
      expect(find.text('서재로 돌아가기'), findsNothing);
      expect(book.page, 2);
      await tester.tapAt(Offset(size.width * .55, size.height * .5));
      await tester.pump();
      expect(book.page, 3);
      await tester.tapAt(Offset(size.width * .45, size.height * .5));
      await tester.pump();
      expect(book.page, 2);
      await tester.tap(find.byTooltip('읽기 설정'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('서재로 돌아가기'));
      await tester.tap(find.text('서재로 돌아가기'));
      await tester.pumpAndSettle();
      expect(find.text('2쪽 / ${book.pages}쪽'), findsOneWidget);
    },
  );
  testWidgets(
    'long-book resume opens immediately and reflow preserves its anchor',
    (tester) async {
      final platform = FakePlatform()
        ..text = List.filled(
          10000,
          '한글 소설의 문장입니다. Reading a novel offline.\n다음 문단을 읽습니다.\n\n',
        ).join();
      final model = LibraryModel(platform);
      final book = Book('long-book', '긴 소설.txt', offset: 500000);
      model.books.add(book);
      await tester.pumpWidget(ReaderApp(model: model));
      await tester.tap(find.text('긴 소설.txt'));
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 30));
        if (find.byTooltip('읽기 설정').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty)
          break;
      }
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(book.offset, 500000);
      expect(find.textContaining('%'), findsOneWidget);
      await tester.tap(find.byTooltip('이전 페이지'));
      await tester.pump();
      expect(book.offset, lessThan(500000));
      await tester.tap(find.byTooltip('다음 페이지'));
      await tester.pump();
      expect(book.offset, 500000);
      await tester.tap(find.byTooltip('읽기 설정'));
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider).first).onChanged!(30);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('설정 닫기'));
      await tester.pumpAndSettle();
      expect(book.offset, 500000);
      expect(model.settings.fontSize, 30);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
  testWidgets(
    'page jump with the keyboard visible updates and persists reading position',
    (tester) async {
      addTearDown(tester.view.resetViewInsets);
      final platform = FakePlatform()
        ..text = List.filled(3000, '한글 소설의 문장입니다. 다음 문단을 읽습니다.\n').join();
      final model = LibraryModel(platform);
      final book = Book('jump-book', '이동할 책.txt');
      model.books.add(book);
      await tester.pumpWidget(ReaderApp(model: model));
      await tester.tap(find.text(book.name));
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 30));
        if (find.byTooltip('페이지 이동').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty)
          break;
      }
      await tester.tap(find.byTooltip('페이지 이동'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '50');
      await tester.pump();
      await tester.ensureVisible(find.text('위치로 이동'));
      await tester.tap(find.text('위치로 이동'));
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(book.offset, (platform.text.length / 2).floor());
      await model.save();
      final restored = LibraryModel(platform);
      await restored.load();
      expect(restored.books.single.offset, book.offset);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
