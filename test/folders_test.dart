import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txt_viewer/folder_models.dart';
import 'package:txt_viewer/folder_screen.dart';
import 'package:txt_viewer/main.dart';
import 'package:txt_viewer/model.dart';
import 'package:txt_viewer/platform.dart';

const favorite = FavoriteFolder(uri: 'content://books/tree/novels', name: '소설');
const subfolder = FolderEntry(
  uri: 'content://books/sub',
  name: '시리즈',
  path: '시리즈',
  isDirectory: true,
);
const novel = FolderEntry(
  uri: 'content://books/moon',
  name: '달빛.txt',
  path: '시리즈/달빛.txt',
  isDirectory: false,
);

class FolderPlatform extends ReaderPlatform {
  String? state;
  final released = <String>[];
  final calls = <({String? parent, String query})>[];
  int cancellations = 0;
  bool denied = false;
  Future<FolderListing> Function(String? parent, String query)? resolve;
  @override
  Future<String?> loadState() async => state;
  @override
  Future<void> saveState(String value) async {
    state = value;
  }

  @override
  Future<FavoriteFolder?> pickFolder() async => favorite;
  @override
  Future<void> releaseFolder(String uri) async {
    released.add(uri);
  }

  @override
  Future<void> cancelFolderScan() async {
    cancellations++;
  }

  @override
  Future<void> setReading(bool value) async {}
  @override
  Future<FolderListing> listFolder(
    String uri, {
    String? parentUri,
    String query = '',
  }) async {
    calls.add((parent: parentUri, query: query));
    if (denied) throw StateError('permission revoked');
    if (resolve != null) return resolve!(parentUri, query);
    if (query.isNotEmpty || parentUri != null)
      return const FolderListing([novel]);
    return const FolderListing([subfolder]);
  }

  @override
  Future<Map<String, dynamic>> importDocument(String uri) async => {
    'id': 'moon',
    'name': novel.name,
    'sourceUri': novel.uri,
    'text': List.filled(200, '달빛 아래 펼쳐진 소설입니다.\n').join(),
  };
}

Future<void> showFolder(WidgetTester tester, FolderPlatform platform) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FolderScreen(model: LibraryModel(platform), folder: favorite),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'v1 library migrates without losing books or reading position',
    () async {
      final platform = FolderPlatform()
        ..state = jsonEncode({
          'settings': {'font': 'Pretendard'},
          'books': [
            {'id': 'legacy', 'name': '기존.txt', 'offset': 125},
          ],
        });
      final model = LibraryModel(platform);
      await model.load();
      expect(model.folders, isEmpty);
      expect(model.books.single.offset, 125);
      expect(model.books.single.sourceUri, isNull);
      expect(model.settings.font, 'Pretendard');
    },
  );

  test(
    'favorites persist, duplicate additions do not duplicate, removal keeps books',
    () async {
      final platform = FolderPlatform();
      final model = LibraryModel(platform);
      model.books.add(Book('saved', '보관.txt', offset: 75));
      expect(model.addFolder(favorite), isTrue);
      expect(model.addFolder(favorite), isFalse);
      await model.save();
      final restored = LibraryModel(platform);
      await restored.load();
      expect(restored.folders.single.uri, favorite.uri);
      await restored.removeFolder(restored.folders.single);
      await restored.save();
      expect(platform.released, [favorite.uri]);
      expect(restored.books.single.offset, 75);
      final reopened = LibraryModel(platform);
      await reopened.load();
      expect(reopened.folders, isEmpty);
      expect(reopened.books.single.name, '보관.txt');
    },
  );

  test(
    'reopening a document preserves position and updates its title',
    () async {
      final platform = FolderPlatform();
      final model = LibraryModel(platform);
      final first = model.acceptImport(
        await platform.importDocument(novel.uri),
      );
      first.offset = 140;
      final second = model.acceptImport({
        ...await platform.importDocument(novel.uri),
        'name': '새 제목.txt',
      });
      await model.save();
      expect(identical(first, second), isTrue);
      expect(model.books, hasLength(1));
      expect(second.offset, 140);
      final restored = LibraryModel(platform);
      await restored.load();
      expect(restored.books.single.name, '새 제목.txt');
      expect(restored.books.single.sourceUri, novel.uri);
      expect(restored.books.single.offset, 140);
    },
  );

  testWidgets(
    'home adds favorite, filters saved books, and removes only the favorite',
    (tester) async {
      final platform = FolderPlatform();
      final model = LibraryModel(platform);
      model.books.addAll([Book('a', 'Moon.txt'), Book('b', '다른 책.txt')]);
      await tester.pumpWidget(ReaderApp(model: model));
      await tester.enterText(find.byType(TextField), 'MOON');
      await tester.pump();
      expect(find.text('Moon.txt'), findsOneWidget);
      expect(find.text('다른 책.txt'), findsNothing);
      await tester.tap(find.text('즐겨찾기 폴더'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('폴더 추가'));
      await tester.pumpAndSettle();
      expect(find.text('소설'), findsOneWidget);
      await tester.tap(find.byTooltip('즐겨찾기 해제'));
      await tester.pumpAndSettle();
      expect(model.folders, isEmpty);
      expect(model.books, hasLength(2));
      expect(platform.released, [favorite.uri]);
    },
  );

  testWidgets('browse a child directory and return to root', (tester) async {
    final platform = FolderPlatform();
    await showFolder(tester, platform);
    await tester.tap(find.text('시리즈'));
    await tester.pumpAndSettle();
    expect(find.text('달빛.txt'), findsOneWidget);
    expect(platform.calls.last.parent, subfolder.uri);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(platform.calls.last.parent, isNull);
    expect(find.text('시리즈'), findsOneWidget);
  });

  testWidgets(
    'folder search requests descendants and renders the relative path',
    (tester) async {
      final platform = FolderPlatform();
      await showFolder(tester, platform);
      await tester.enterText(find.byType(TextField), '달빛');
      await tester.pump(const Duration(milliseconds: 310));
      await tester.pumpAndSettle();
      expect(platform.calls.last.query, '달빛');
      expect(find.text('달빛.txt'), findsOneWidget);
      expect(find.text('시리즈/달빛.txt'), findsOneWidget);
      await tester.tap(find.byTooltip('폴더 검색 지우기'));
      await tester.pump(const Duration(milliseconds: 310));
      await tester.pumpAndSettle();
      expect(platform.calls.last.query, '');
      expect(find.text('시리즈'), findsOneWidget);
    },
  );

  testWidgets('revoked folder access shows recovery and supports retry', (
    tester,
  ) async {
    final platform = FolderPlatform()..denied = true;
    await showFolder(tester, platform);
    expect(find.textContaining('권한이 해제됐다면'), findsOneWidget);
    platform.denied = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('시리즈'), findsOneWidget);
    expect(find.textContaining('권한이 해제됐다면'), findsNothing);
  });

  testWidgets('older search results cannot replace a newer query', (
    tester,
  ) async {
    final old = Completer<FolderListing>(), recent = Completer<FolderListing>();
    final platform = FolderPlatform()
      ..resolve = (_, query) => query == 'old'
          ? old.future
          : query == 'new'
          ? recent.future
          : Future.value(const FolderListing([]));
    await showFolder(tester, platform);
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 310));
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump(const Duration(milliseconds: 310));
    recent.complete(const FolderListing([novel]));
    await tester.pumpAndSettle();
    old.complete(const FolderListing([]));
    await tester.pumpAndSettle();
    expect(find.text('달빛.txt'), findsOneWidget);
    expect(platform.cancellations, greaterThanOrEqualTo(2));
  });

  testWidgets('opening a folder file reuses its saved book', (tester) async {
    final platform = FolderPlatform();
    final model = LibraryModel(platform);
    model.books.add(
      Book('moon', novel.name, sourceUri: novel.uri, offset: 140),
    );
    platform.resolve = (_, query) async => const FolderListing([novel]);
    await tester.pumpWidget(
      MaterialApp(
        home: FolderScreen(model: model, folder: favorite),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(novel.name));
    for (var i = 0; i < 80; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 30));
      if (find.byTooltip('읽기 설정').evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty)
        break;
    }
    expect(find.byTooltip('읽기 설정'), findsOneWidget);
    expect(model.books, hasLength(1));
    expect(model.books.single.offset, 140);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
