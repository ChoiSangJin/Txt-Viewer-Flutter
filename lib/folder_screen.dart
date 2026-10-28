import 'dart:async';
import 'package:flutter/material.dart';
import 'folder_models.dart';
import 'model.dart';
import 'reader.dart';

class FolderScreen extends StatefulWidget {
  final LibraryModel model;
  final FavoriteFolder folder;
  const FolderScreen({super.key, required this.model, required this.folder});
  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  final search = TextEditingController();
  final List<FolderEntry> trail = [];
  FolderListing listing = const FolderListing([]);
  Timer? debounce;
  int generation = 0;
  bool loading = true, opening = false, newestFirst = false;
  String? error;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    search.dispose();
    widget.model.platform.cancelFolderScan();
    super.dispose();
  }

  Future<void> refresh() async {
    debounce?.cancel();
    final token = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.model.platform.listFolder(
        widget.folder.uri,
        parentUri: trail.isEmpty ? null : trail.last.uri,
        query: search.text.trim(),
      );
      if (mounted && token == generation) setState(() => listing = result);
    } catch (_) {
      if (mounted && token == generation)
        setState(
          () => error =
              '폴더를 읽지 못했습니다. 저장 장치 연결과 접근 권한을 확인해 주세요. '
              '권한이 해제됐다면 즐겨찾기에서 삭제 후 폴더를 다시 추가해 주세요.',
        );
    } finally {
      if (mounted && token == generation) setState(() => loading = false);
    }
  }

  void searchChanged(String value) {
    debounce?.cancel();
    generation++;
    widget.model.platform.cancelFolderScan();
    setState(() {
      loading = true;
      error = null;
    });
    debounce = Timer(const Duration(milliseconds: 300), refresh);
  }

  void enter(FolderEntry entry) {
    debounce?.cancel();
    search.clear();
    trail.add(entry);
    refresh();
  }

  void up() {
    debounce?.cancel();
    search.clear();
    trail.removeLast();
    refresh();
  }

  Future<void> open(FolderEntry entry) async {
    if (opening) return;
    setState(() {
      opening = true;
      error = null;
    });
    try {
      final imported = await widget.model.platform.importDocument(entry.uri);
      final book = widget.model.acceptImport(imported);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            model: widget.model,
            book: book,
            text: imported['text'] as String,
          ),
        ),
      );
    } catch (_) {
      if (mounted)
        setState(() => error = '파일을 열지 못했습니다. 파일이 이동되었거나 접근할 수 없는 상태일 수 있습니다.');
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = [...listing.entries];
    if (newestFirst)
      entries.sort((a, b) {
        if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
        final compared = b.modified.compareTo(a.modified);
        return compared == 0 ? a.path.compareTo(b.path) : compared;
      });
    return PopScope(
      canPop: trail.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && trail.isNotEmpty && !opening) up();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(trail.isEmpty ? widget.folder.name : trail.last.name),
          leading: BackButton(
            onPressed: opening
                ? null
                : () {
                    if (trail.isNotEmpty) {
                      up();
                    } else {
                      Navigator.pop(context);
                    }
                  },
          ),
          actions: [
            IconButton(
              tooltip: '폴더 새로고침',
              onPressed: opening ? null : refresh,
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<bool>(
              tooltip: '정렬',
              initialValue: newestFirst,
              onSelected: (value) => setState(() => newestFirst = value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: false, child: Text('이름순')),
                PopupMenuItem(value: true, child: Text('최근 수정순')),
              ],
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      [
                        widget.folder.name,
                        ...trail.map((e) => e.name),
                      ].join(' / '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: search,
                      onChanged: searchChanged,
                      enabled: !opening,
                      decoration: InputDecoration(
                        labelText: '이 폴더와 하위 폴더에서 TXT 검색',
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        suffixIcon: search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '폴더 검색 지우기',
                                onPressed: () {
                                  search.clear();
                                  searchChanged('');
                                },
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              if (loading || opening) const LinearProgressIndicator(),
              if (error case final message?)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    message,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (!loading && error == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${entries.length}개 항목'),
                  ),
                ),
              if (!loading && listing.truncated)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('파일이 많아 일부 결과만 표시합니다. 하위 폴더를 열거나 검색어를 구체화해 주세요.'),
                ),
              Expanded(
                child: loading
                    ? const SizedBox.expand()
                    : error != null
                    ? Center(
                        child: FilledButton.tonal(
                          onPressed: refresh,
                          child: const Text('다시 시도'),
                        ),
                      )
                    : entries.isEmpty
                    ? Center(
                        child: Text(
                          search.text.trim().isEmpty
                              ? '이 폴더에 TXT 파일이나 하위 폴더가 없습니다.'
                              : '검색 결과가 없습니다.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return ListTile(
                            leading: Icon(
                              entry.isDirectory
                                  ? Icons.folder_outlined
                                  : Icons.description_outlined,
                            ),
                            title: Text(entry.name),
                            subtitle: search.text.trim().isEmpty
                                ? null
                                : Text(entry.path),
                            trailing: Icon(
                              entry.isDirectory
                                  ? Icons.chevron_right
                                  : Icons.menu_book_outlined,
                            ),
                            onTap: opening
                                ? null
                                : () => entry.isDirectory
                                      ? enter(entry)
                                      : open(entry),
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
