import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'model.dart';
import 'pagination.dart';
import 'platform.dart';
import 'page_jump_dialog.dart';
import 'page_count_summary.dart';
import 'page_index_controller.dart';
import 'numeric_reading_setting.dart';

class ReaderScreen extends StatefulWidget {
  final LibraryModel model;
  final Book book;
  final String text;
  const ReaderScreen({
    super.key,
    required this.model,
    required this.book,
    required this.text,
  });
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  PageSession? session;
  PageIndexController? pageIndex;
  int generation = 0;
  bool paginating = true, menuOpen = false;
  String? layoutKey;
  Timer? saveTimer;
  double dragDistance = 0;
  static final Map<String, Future<void>> loadedFonts = {};
  static final Set<String> readyFonts = {};
  ReadingSettings get settings => widget.model.settings;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    widget.model.platform.setReading(true);
    ReaderPlatform.channel.setMethodCallHandler((call) async {
      if (call.method == 'volume' && !menuOpen)
        turn(call.arguments == 'next' ? 1 : -1);
    });
    // Font metrics must be loaded before pagination, including the initial font.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      pageIndex?.flush();
      widget.model.save();
    }
  }

  @override
  void dispose() {
    generation++;
    pageIndex?.close();
    pageIndex = null;
    session?.dispose();
    saveTimer?.cancel();
    widget.model.save();
    WidgetsBinding.instance.removeObserver(this);
    ReaderPlatform.channel.setMethodCallHandler(null);
    widget.model.platform.setReading(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> paginate(Size size, int token) async {
    final position = widget.book.offset;
    final style = settings.style;
    final spacing = settings.paragraphSpace;
    final font = settings.font;
    if (!readyFonts.contains(font)) {
      try {
        await loadedFonts.putIfAbsent(font, () {
          final loader = FontLoader(font)
            ..addFont(
              rootBundle.load(switch (font) {
                'KoPubBatang' => 'assets/fonts/kopub.ttf',
                'Pretendard' => 'assets/fonts/pretendard.ttf',
                _ => 'assets/fonts/ridi.otf',
              }),
            );
          return loader.load();
        });
        readyFonts.add(font);
      } finally {
        loadedFonts.remove(font);
      }
    }
    if (!mounted || token != generation) return;
    final next = PageSession(
      text: widget.text,
      offset: position,
      size: size,
      style: style,
      spacing: spacing,
    );
    pageIndex?.close();
    pageIndex = null;
    session?.dispose();
    setState(() {
      session = next;
      paginating = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && token == generation && identical(session, next))
        preparePageIndex(next, token);
    });
    if (widget.book.offset != next.range.start) {
      widget.book.offset = next.range.start;
      widget.model.save();
    }
  }

  Future<void> preparePageIndex(PageSession active, int token) async {
    bool valid() =>
        mounted && token == generation && identical(session, active);
    final layout =
        'goyo-pages-v1/flutter-3.35.7/${active.size.width}/${active.size.height}/'
        '${active.style.fontFamily}/${active.style.fontSize}/${active.style.height}/${active.spacing}/${active.style.letterSpacing}';
    if (!valid()) return;
    final controller = PageIndexController(
      session: active,
      load: () => widget.model.platform.loadPageIndex(widget.book.id, layout),
      save: (token, ends) => widget.model.platform.savePageIndex(
        widget.book.id,
        layout,
        token,
        ends,
      ),
    );
    pageIndex = controller;
    await controller.start();
  }

  void turn(int direction) {
    if (paginating || session == null || !session!.move(direction)) return;
    setState(() {});
    widget.book.offset = session!.range.start;
    saveTimer?.cancel();
    saveTimer = Timer(const Duration(milliseconds: 250), widget.model.save);
  }

  Future<void> showPageJump() async {
    final active = session;
    if (paginating || active == null || menuOpen) return;
    menuOpen = true;
    final selection = await showDialog<PageJumpSelection>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PageJumpDialog(
        session: active,
        isCurrent: () => mounted && !paginating && identical(active, session),
      ),
    );
    menuOpen = false;
    if (!mounted) return;
    if (paginating || !identical(active, session)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('화면 크기가 바뀌었습니다. 페이지 이동을 다시 열어 주세요.')),
      );
      return;
    }
    if (selection == null) return;
    active.seekOffset(selection.offset);
    setState(() {});
    widget.book.offset = active.range.start;
    saveTimer?.cancel();
    widget.model.save();
    if (selection.actualPage != null &&
        selection.actualPage != selection.requestedPage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('마지막 페이지(${selection.actualPage}쪽)로 이동했습니다.')),
      );
    }
  }

  Future<void> showSettings() async {
    menuOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, refresh) {
          void change(VoidCallback action) {
            action();
            widget.model.changed();
            refresh(() {});
            setState(() {});
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '읽기 설정',
                              style: TextStyle(fontSize: 22),
                            ),
                          ),
                          IconButton(
                            tooltip: '설정 닫기',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const Text('좌우 탭 · 스와이프 · 볼륨 버튼으로 페이지 이동'),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: settings.font,
                        decoration: const InputDecoration(labelText: '글꼴'),
                        items: const [
                          DropdownMenuItem(
                            value: 'RIDIBatang',
                            child: Text('리디바탕'),
                          ),
                          DropdownMenuItem(
                            value: 'KoPubBatang',
                            child: Text('KoPub 바탕'),
                          ),
                          DropdownMenuItem(
                            value: 'Pretendard',
                            child: Text('프리텐다드'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) change(() => settings.font = v);
                        },
                      ),
                      const SizedBox(height: 16),
                      NumericReadingSetting(
                        label: '글자 크기',
                        value: settings.fontSize,
                        min: 14,
                        max: 36,
                        onChanged: (v) => change(() => settings.fontSize = v),
                      ),
                      NumericReadingSetting(
                        label: '줄 간격',
                        value: settings.lineHeight,
                        min: 1.2,
                        max: 2.4,
                        onChanged: (v) => change(() => settings.lineHeight = v),
                      ),
                      NumericReadingSetting(
                        label: '문단 여백',
                        value: settings.paragraphSpace,
                        min: 0,
                        max: 32,
                        onChanged: (v) =>
                            change(() => settings.paragraphSpace = v),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final theme in ReaderTheme.values)
                            ChoiceChip(
                              label: Text(switch (theme) {
                                ReaderTheme.system => '시스템',
                                ReaderTheme.light => '라이트',
                                ReaderTheme.dark => '다크',
                                ReaderTheme.black => 'AMOLED 블랙',
                              }),
                              selected: settings.theme == theme,
                              onSelected: (_) =>
                                  change(() => settings.theme = theme),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.of(this.context).pop();
                        },
                        icon: const Icon(Icons.library_books_outlined),
                        label: const Text('서재로 돌아가기'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    menuOpen = false;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: false,
    body: SafeArea(
      maintainBottomViewPadding: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(
            (constraints.maxWidth - 48).clamp(1, double.infinity).toDouble(),
            (constraints.maxHeight - 84).clamp(1, double.infinity).toDouble(),
          );
          final key =
              '${size.width}/${size.height}/${settings.font}/${settings.fontSize}/${settings.lineHeight}/${settings.paragraphSpace}';
          if (key != layoutKey) {
            layoutKey = key;
            pageIndex?.close();
            pageIndex = null;
            session?.dispose();
            session = null;
            paginating = true;
            final token = ++generation;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && token == generation) paginate(size, token);
            });
          }
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (event) {
              final fraction = event.localPosition.dx / constraints.maxWidth;
              if (fraction < 0.3) {
                turn(-1);
              } else if (fraction > 0.7) {
                turn(1);
              } else {
                showSettings();
              }
            },
            onHorizontalDragStart: (_) => dragDistance = 0,
            onHorizontalDragUpdate: (event) => dragDistance += event.delta.dx,
            onHorizontalDragEnd: (event) {
              final speed = event.primaryVelocity ?? 0;
              if (dragDistance.abs() > 40 || speed.abs() > 100) {
                final motion = dragDistance.abs() > 40 ? dragDistance : speed;
                turn(motion < 0 ? 1 : -1);
              }
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Column(
                children: [
                  Expanded(
                    child: paginating
                        ? const Center(child: CircularProgressIndicator())
                        : Align(
                            alignment: Alignment.topLeft,
                            child: Text.rich(
                              readingSpan(
                                widget.text.substring(
                                  session!.range.start,
                                  session!.range.end,
                                ),
                                settings.style,
                                settings.paragraphSpace,
                              ),
                              textScaler: TextScaler.noScaling,
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: ListenableBuilder(
                      listenable: Listenable.merge([session]),
                      builder: (context, _) => Row(
                        children: [
                          IconButton(
                            tooltip: '이전 페이지',
                            onPressed:
                                !paginating && session?.canPrevious == true
                                ? () => turn(-1)
                                : null,
                            icon: const Icon(Icons.chevron_left),
                            visualDensity: VisualDensity.compact,
                          ),
                          Expanded(
                            child: paginating
                                ? const Text(
                                    '페이지 구성 중…',
                                    textAlign: TextAlign.center,
                                  )
                                : PageCountSummary(
                                    session: session!,
                                    compact: true,
                                  ),
                          ),
                          IconButton(
                            tooltip: '페이지 이동',
                            onPressed: paginating ? null : showPageJump,
                            icon: const Icon(Icons.find_in_page_outlined),
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            tooltip: '읽기 설정',
                            onPressed: showSettings,
                            icon: const Icon(Icons.tune),
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            tooltip: '다음 페이지',
                            onPressed: !paginating && session?.canNext == true
                                ? () => turn(1)
                                : null,
                            icon: const Icon(Icons.chevron_right),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
