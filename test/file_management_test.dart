import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txt_viewer/folder_models.dart';
import 'package:txt_viewer/folder_screen.dart';
import 'package:txt_viewer/main.dart';
import 'package:txt_viewer/model.dart';
import 'package:txt_viewer/platform.dart';

const folder = FavoriteFolder(uri: 'content://test/tree/root', name: '소설 폴더');
const fileUri = 'content://test/tree/root/document/novel';

class FilePlatform extends ReaderPlatform {
  String? saved;
  bool write = true, deleted = false, rejectDelete = false;
  int authorizationCalls = 0;
  final deletionCalls = <(String, String, String)>[];
  final releases = <String>[];
  @override
  Future<String?> loadState() async => saved;
  @override
  Future<void> saveState(String value) async {
    saved = value;
  }

  @override
  Future<void> cancelFolderScan() async {}
  @override
  Future<void> setReading(bool value) async {}
  @override
  Future<void> releaseFolder(String uri) async {
    releases.add(uri);
  }

  @override
  Future<String> readBook(String id) async => '앱에 보관한 원본 사본';
  @override
  Future<Map<String, dynamic>> importDocument(String uri) async => {
    'id': 'novel',
    'name': '소설.txt',
    'sourceUri': fileUri,
    'text': '앱에 보관한 원본 사본',
  };
  @override
  Future<bool> authorizeFolder(String uri) async {
    expect(uri, folder.uri);
    authorizationCalls++;
    write = true;
    return true;
  }

  @override
  Future<FolderListing> listFolder(
    String uri, {
    String? parentUri,
    String query = '',
  }) async => FolderListing([
    const FolderEntry(
      uri: 'content://test/tree/root/document/sub',
      name: '하위 폴더',
      path: '하위 폴더',
      isDirectory: true,
    ),
    if (!deleted)
      FolderEntry(
        uri: fileUri,
        name: '소설.txt',
        path: '소설.txt',
        isDirectory: false,
        supportsDelete: true,
        canDelete: write,
      ),
  ]);
  @override
  Future<void> deleteDocument(String tree, String uri, String name) async {
    deletionCalls.add((tree, uri, name));
    if (rejectDelete || !write) throw StateError('not allowed');
    deleted = true;
  }
}

LibraryModel history(FilePlatform platform) =>
    LibraryModel(platform)
      ..books.add(Book('novel', '소설.txt', sourceUri: fileUri, offset: 37));

Future<void> showFolder(WidgetTester tester, LibraryModel model) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FolderScreen(model: model, folder: folder),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'hidden history persists without deleting its copy or reading position',
    () async {
      final platform = FilePlatform();
      final model = history(platform);
      model.hideBook(model.books.single);
      await model.save();
      final restored = LibraryModel(platform);
      await restored.load();
      expect(restored.recentBooks, isEmpty);
      expect(restored.books.single.offset, 37);
      expect(await platform.readBook('novel'), '앱에 보관한 원본 사본');
      expect(platform.deletionCalls, isEmpty);
      expect(platform.deleted, isFalse);
      final book = restored.acceptImport(
        await platform.importDocument(fileUri),
      );
      expect(restored.recentBooks.single, same(book));
      expect(restored.books, hasLength(1));
      expect(book.offset, 37);
      expect(book.hidden, isFalse);
    },
  );

  test('opening an older book moves it to the front and unhides it', () {
    final model = history(FilePlatform());
    final old = model.books.single;
    model.books.insert(0, Book('new', '최근.txt'));
    old.hidden = true;
    model.markOpened(old);
    expect(model.recentBooks.first, same(old));
    expect(old.hidden, isFalse);
  });

  testWidgets('history removal requires confirmation and only hides the row', (
    tester,
  ) async {
    final platform = FilePlatform();
    final model = history(platform);
    await tester.pumpWidget(ReaderApp(model: model));
    await tester.tap(find.byTooltip('이력에서 지우기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('원본 파일과 앱에 보관한 사본'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('소설.txt'), findsOneWidget);
    expect(model.books.single.hidden, isFalse);
    await tester.tap(find.byTooltip('이력에서 지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '이력에서 지우기'));
    await tester.pumpAndSettle();
    expect(find.text('소설.txt'), findsNothing);
    expect(find.text('최근 이력이 없습니다.'), findsOneWidget);
    expect(model.books.single.offset, 37);
    expect(platform.deletionCalls, isEmpty);
    final restored = LibraryModel(platform);
    await restored.load();
    expect(restored.recentBooks, isEmpty);
  });

  testWidgets(
    'original file deletion cancels safely then deletes only the selected file',
    (tester) async {
      final platform = FilePlatform();
      final model = history(platform);
      await showFolder(tester, model);
      await tester.tap(find.byTooltip('원본 파일 삭제'));
      await tester.pumpAndSettle();
      expect(find.textContaining('기기의 원본 파일이 삭제'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(platform.deletionCalls, isEmpty);
      expect(find.text('소설.txt'), findsOneWidget);
      await tester.tap(find.byTooltip('원본 파일 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '원본 파일 삭제'));
      await tester.pumpAndSettle();
      expect(platform.deletionCalls, [(folder.uri, fileUri, '소설.txt')]);
      expect(find.text('소설.txt'), findsNothing);
      expect(find.text('하위 폴더'), findsOneWidget);
      expect(model.books.single.offset, 37);
      expect(await platform.readBook('novel'), '앱에 보관한 원본 사본');
    },
  );

  testWidgets(
    'provider deletion failure preserves the row and reports failure',
    (tester) async {
      final platform = FilePlatform()..rejectDelete = true;
      await showFolder(tester, history(platform));
      await tester.tap(find.byTooltip('원본 파일 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '원본 파일 삭제'));
      await tester.pumpAndSettle();
      expect(find.text('소설.txt'), findsOneWidget);
      expect(platform.deleted, isFalse);
      expect(find.textContaining('삭제 완료를 확인하지 못했습니다.'), findsOneWidget);
    },
  );

  testWidgets(
    'read-only files require explicit permission renewal before deletion',
    (tester) async {
      final platform = FilePlatform()..write = false;
      await showFolder(tester, history(platform));
      expect(find.byTooltip('원본 파일 삭제'), findsNothing);
      expect(find.text('삭제 권한 허용'), findsOneWidget);
      await tester.tap(find.text('삭제 권한 허용'));
      await tester.pumpAndSettle();
      expect(platform.authorizationCalls, 1);
      expect(find.byTooltip('원본 파일 삭제'), findsOneWidget);
      expect(platform.deletionCalls, isEmpty);
    },
  );

  testWidgets('unfavoriting a folder also requires confirmation', (
    tester,
  ) async {
    final platform = FilePlatform();
    final model = history(platform)..folders.add(folder);
    await tester.pumpWidget(ReaderApp(model: model));
    await tester.tap(find.text('즐겨찾기 폴더'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('즐겨찾기 해제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(model.folders, hasLength(1));
    expect(platform.releases, isEmpty);
    expect(platform.deletionCalls, isEmpty);
  });
}
