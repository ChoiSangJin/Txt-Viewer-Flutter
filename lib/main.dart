import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'model.dart';
import 'platform.dart';
import 'reader.dart';

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
  String? error;
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
        book = Book(imported['id'] as String, imported['name'] as String);
        text = imported['text'] as String;
        widget.model.books.insert(0, book);
        await widget.model.save();
      } else {
        text = await widget.model.platform.readBook(book.id);
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ReaderScreen(model: widget.model, book: book!, text: text),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = '파일을 열지 못했습니다. $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('고요'),
      actions: [
        IconButton(
          tooltip: '앱과 글꼴 정보',
          icon: const Icon(Icons.info_outline),
          onPressed: () =>
              showLicensePage(context: context, applicationName: '고요 · TXT 리더'),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: busy || widget.startupError != null ? null : () => open(),
      icon: const Icon(Icons.add),
      label: const Text('TXT 불러오기'),
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('나만의 서재', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 8),
            const Text('연결 없이, 이야기 속으로.\nUTF-8 · UTF-16 · 한글 CP949 지원'),
            const SizedBox(height: 24),
            if (busy) const LinearProgressIndicator(),
            if (widget.startupError ?? error ?? widget.model.persistenceError
                case final message?)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: widget.model.books.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_stories_outlined, size: 64),
                          SizedBox(height: 16),
                          Text('첫 번째 이야기를 추가해 보세요'),
                          SizedBox(height: 8),
                          Text('TXT 파일을 앱에 복사해 오프라인으로 보관합니다.'),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: widget.model.books.length,
                      separatorBuilder: (_, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final book = widget.model.books[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.menu_book_outlined),
                          title: Text(book.name),
                          subtitle: Text(
                            book.offset > 0 ? '읽던 곳부터 계속 읽기' : '새로운 이야기',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: busy || widget.startupError != null
                              ? null
                              : () => open(book: book),
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
