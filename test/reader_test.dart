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
  @override Future<String?> loadState() async => state;
  @override Future<void> saveState(String value) async { state = value; }
  @override Future<void> setReading(bool enabled) async {}
  @override Future<String> readBook(String id) async => text;
  @override Future<Map<String, dynamic>?> pickBook() async => {
    'id': 'test-book', 'name': '이야기.txt', 'text': text,
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
    final restored = LibraryModel(platform); await restored.load();
    expect(restored.books.single.offset, 123);
    expect(restored.settings.font, 'Pretendard');
    expect(restored.settings.theme, ReaderTheme.black);
    expect(restored.settings.paragraphSpace, 24);
    expect(jsonDecode(platform.state!)['books'], hasLength(1));
  });
  testWidgets('import, next page, volume previous, and return to library', (tester) async {
    final model = LibraryModel(FakePlatform());
    await tester.pumpWidget(ReaderApp(model: model));
    expect(find.text('첫 번째 이야기를 추가해 보세요'), findsOneWidget);
    await tester.tap(find.text('TXT 불러오기'));
    // Pagination yields while loading bundled fonts and measuring long text.
    for (var i = 0; i < 80; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 30));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byTooltip('다음 페이지').evaluate().isNotEmpty) break;
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.byTooltip('다음 페이지')); await tester.pump();
    expect(model.books.single.offset, greaterThan(0));
    final message = const StandardMethodCodec().encodeMethodCall(const MethodCall('volume', 'previous'));
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'txt_viewer/storage', message, (_) {});
    await tester.pump();
    expect(model.books.single.offset, 0);
    await tester.tap(find.byTooltip('읽기 설정')); await tester.pumpAndSettle();
    expect(find.text('AMOLED 블랙'), findsOneWidget);
    await tester.tap(find.text('AMOLED 블랙')); await tester.pumpAndSettle();
    expect(model.settings.theme, ReaderTheme.black);
    await tester.tap(find.text('서재로 돌아가기')); await tester.pumpAndSettle();
    expect(find.text('이야기.txt'), findsOneWidget);
  });
}
