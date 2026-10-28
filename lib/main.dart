import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'model.dart';
import 'platform.dart';
import 'reader.dart';
import 'folder_models.dart';
import 'folder_screen.dart';
import 'confirmation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final entry in {
      '리디바탕': 'assets/fonts/RIDI-LICENSE.md',
      'KoPub 바탕': 'assets/fonts/KoPub-LICENSE.txt',
      'Pretendard': 'assets/fonts/Pretendard-LICENSE.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString(entry.value));
    }
  });
  final model = LibraryModel(ReaderPlatform());
  String? error;
  try {
    await model.load();
  } catch (_) {
    error = '저장된 서재를 읽지 못했습니다. 앱을 다시 시작해 주세요.';
  }
  runApp(ReaderApp(model: model, startupError: error));
}

class ReaderApp extends StatelessWidget {
  final LibraryModel model;
  final String? startupError;
  const ReaderApp({super.key, required this.model, this.startupError});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => MaterialApp(
      title: '고요 · TXT 리더',
      debugShowCheckedModeBanner: false,
      themeMode: switch (model.settings.theme) {
        ReaderTheme.system => ThemeMode.system,
        ReaderTheme.light => ThemeMode.light,
        _ => ThemeMode.dark,
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF526A58)),
        fontFamily: 'Pretendard',
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9DB5A2),
          brightness: Brightness.dark,
          surface: model.settings.theme == ReaderTheme.black
              ? Colors.black
              : null,
        ),
        scaffoldBackgroundColor: model.settings.theme == ReaderTheme.black
            ? Colors.black
            : null,
        fontFamily: 'Pretendard',
        useMaterial3: true,
      ),
      home: LibraryScreen(model: model, startupError: startupError),
    ),
  );
}

class LibraryScreen extends StatefulWidget {
  final LibraryModel model;
  final String? startupError;
  const LibraryScreen({super.key, required this.model, this.startupError});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool busy = false;
  int tab = 0;
  String? error;
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> open({Book? book}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      String text;
      if (book == null) {
        final imported = await widget.model.platform.pickBook();
        if (imported == null) return;
        book = widget.model.acceptImport(imported);
        text = imported['text'] as String;
      } else {
        text = await widget.model.platform.readBook(book.id);
        widget.model.markOpened(book);
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ReaderScreen(model: widget.model, book: book!, text: text),
        ),
      );
    } catch (_) {
      if (mounted)
        setState(() => error = '파일을 열지 못했습니다. 파일 상태와 접근 권한을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addFolder() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final folder = await widget.model.platform.pickFolder();
      if (folder != null) {
        final added = widget.model.addFolder(folder);
        if (mounted && !added)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('기존 즐겨찾기 폴더의 접근 권한을 갱신했습니다.')),
          );
      }
    } catch (_) {
      if (mounted) setState(() => error = '폴더를 추가하지 못했습니다. 폴더 읽기 권한을 허용해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> hideBook(Book book) async {
    final confirmed = await confirmAction(
      context,
      title: '최근 이력에서 지울까요?',
      message:
          '${book.name}\n\n원본 파일과 앱에 보관한 사본, 읽던 위치는 유지됩니다. 다시 열면 최근 이력에 표시됩니다.',
      confirmLabel: '이력에서 지우기',
    );
    if (!mounted || !confirmed) return;
    setState(() => widget.model.hideBook(book));
  }

  Future<void> removeFolder(FavoriteFolder folder) async {
    final confirmed = await confirmAction(
      context,
      title: '폴더 즐겨찾기를 해제할까요?',
      message: '${folder.name}\n\n원본 폴더와 파일, 앱의 읽기 사본은 유지됩니다.',
      confirmLabel: '즐겨찾기 해제',
    );
    if (!mounted || !confirmed) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.model.removeFolder(folder);
    } catch (_) {
      if (mounted) setState(() => error = '즐겨찾기를 해제하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = busy || widget.startupError != null;
    final query = search.text.trim().toLowerCase();
    final books = widget.model.recentBooks
        .where((book) => book.name.toLowerCase().contains(query))
        .toList();
    final folders =
        widget.model.folders
            .where((folder) => folder.name.toLowerCase().contains(query))
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return Scaffold(
      appBar: AppBar(
        title: const Text('고요'),
        actions: [
          IconButton(
            tooltip: '앱과 글꼴 정보',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showLicensePage(
              context: context,
              applicationName: '고요 · TXT 리더',
              applicationVersion: '1.2.0',
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: busy
            ? null
            : (value) => setState(() {
                tab = value;
                search.clear();
                error = null;
              }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: '최근 이력',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_special),
            label: '즐겨찾기 폴더',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: blocked
            ? null
            : tab == 0
            ? () => open()
            : addFolder,
        icon: Icon(tab == 0 ? Icons.add : Icons.create_new_folder_outlined),
        label: Text(tab == 0 ? 'TXT 불러오기' : '폴더 추가'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tab == 0 ? '최근 읽은 책' : '자주 읽는 폴더',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(tab == 0 ? '연결 없이, 이야기 속으로.' : '폴더를 저장하고 TXT 파일을 바로 찾아보세요.'),
              const SizedBox(height: 16),
              TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: tab == 0 ? '최근 이력에서 책 제목 검색' : '즐겨찾기 폴더 검색',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '검색 지우기',
                          onPressed: () => setState(search.clear),
                          icon: const Icon(Icons.clear),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              if (busy) const LinearProgressIndicator(),
              if (widget.startupError ?? error ?? widget.model.persistenceError
                  case final message?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: tab == 0
                    ? books.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.auto_stories_outlined,
                                    size: 56,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    query.isEmpty
                                        ? (widget.model.books.isEmpty
                                              ? '첫 번째 이야기를 추가해 보세요'
                                              : '최근 이력이 없습니다.')
                                        : '검색 결과가 없습니다.',
                                  ),
                                  if (query.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Text(
                                        'TXT 파일을 앱에 복사해 오프라인으로 보관합니다.',
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.only(bottom: 88),
                              itemCount: books.length,
                              separatorBuilder: (_, index) => const Divider(),
                              itemBuilder: (context, index) {
                                final book = books[index];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.menu_book_outlined),
                                  title: Text(book.name),
                                  subtitle: Text(
                                    book.offset > 0
                                        ? '읽던 곳부터 계속 읽기'
                                        : '새로운 이야기',
                                  ),
                                  trailing: IconButton(
                                    tooltip: '이력에서 지우기',
                                    icon: const Icon(Icons.close),
                                    onPressed: blocked
                                        ? null
                                        : () => hideBook(book),
                                  ),
                                  onTap: blocked
                                      ? null
                                      : () => open(book: book),
                                );
                              },
                            )
                    : folders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.folder_special_outlined, size: 56),
                            const SizedBox(height: 16),
                            Text(
                              query.isEmpty
                                  ? '자주 읽는 폴더를 추가해 보세요'
                                  : '검색 결과가 없습니다.',
                            ),
                            if (query.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(8),
                                child: Text('선택한 폴더와 하위 폴더의 TXT 파일을 탐색합니다.'),
                              ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: folders.length,
                        itemBuilder: (context, index) {
                          final folder = folders[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.folder_special_outlined),
                            title: Text(folder.name),
                            subtitle: const Text('폴더 열기 · TXT 파일 검색'),
                            trailing: IconButton(
                              tooltip: '즐겨찾기 해제',
                              icon: const Icon(Icons.star),
                              onPressed: blocked
                                  ? null
                                  : () => removeFolder(folder),
                            ),
                            onTap: blocked
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => FolderScreen(
                                        model: widget.model,
                                        folder: folder,
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
