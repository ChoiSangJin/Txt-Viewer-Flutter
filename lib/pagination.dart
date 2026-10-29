import 'dart:async';
import 'package:flutter/material.dart';
import 'line_layout.dart';
export 'line_layout.dart' show LineLayout, LinePage, LinePagePainter;

class PageRange {
  final int start, end;
  final LinePage? layout;
  const PageRange(this.start, this.end, {this.layout});
  factory PageRange.fromLayout(LinePage page) =>
      PageRange(page.start, page.end, layout: page);
}

PageRange nextPage(
  String text,
  int start,
  Size size,
  TextStyle style,
  double spacing,
) {
  final layout = LineLayout(text, size, style, spacing);
  try {
    return PageRange.fromLayout(layout.page(start, 0));
  } finally {
    layout.dispose();
  }
}

PageRange previousPage(
  String text,
  int end,
  Size size,
  TextStyle style,
  double spacing,
) {
  final layout = LineLayout(text, size, style, spacing);
  try {
    return PageRange.fromLayout(layout.previous(end));
  } finally {
    layout.dispose();
  }
}

/// Opens a single page immediately. The canonical page index can be completed
/// cooperatively after first paint, or restored from a validated layout cache.
class PageSession extends ChangeNotifier {
  final String text;
  final Size size;
  final TextStyle style;
  final double spacing;
  late final LineLayout lineLayout;
  final List<PageRange> _pages = [];
  List<int> _ends = [];
  int _current = 0;
  bool _closed = false;
  bool indexFailed = false;
  Timer? _indexTimer;
  Completer<void>? _indexWait;
  Future<void>? _counting;
  PageSession({
    required this.text,
    required this.size,
    required this.style,
    required this.spacing,
    int offset = 0,
  }) {
    lineLayout = LineLayout(text, size, style, spacing);
    seekOffset(offset);
  }

  bool get indexComplete => _ends.isNotEmpty && _ends.last >= text.length;
  int? get totalPages => indexComplete ? _ends.length : null;
  int get indexedPages => _ends.length;
  double get indexProgress => text.isEmpty
      ? (indexComplete ? 1 : 0)
      : (_ends.isEmpty ? 0 : _ends.last / text.length);
  int? get estimatedTotalPages {
    if (indexComplete) return totalPages;
    if (_ends.isEmpty || _ends.last == 0) return null;
    return (_ends.length * text.length / _ends.last).ceil().clamp(
      _ends.length + 1,
      text.length,
    );
  }

  int? estimatedPageAt(int offset) {
    final exact = pageNumberAt(offset);
    if (exact != null) return exact;
    final total = estimatedTotalPages;
    if (total == null || text.isEmpty) return null;
    return (offset.clamp(0, text.length) * total / text.length).floor().clamp(
          0,
          total - 1,
        ) +
        1;
  }

  List<int> get pageEnds => List<int>.unmodifiable(_ends);
  PageRange _pageAt(int i) {
    final first = i ~/ LineLayout.pagesPerGroup * LineLayout.pagesPerGroup;
    final groupStart = first == 0 ? 0 : _ends[first - 1];
    return PageRange.fromLayout(lineLayout.page(groupStart, i - first));
  }

  PageRange _forward(int start) =>
      PageRange.fromLayout(lineLayout.page(start, 0));
  PageRange _backward(int end) =>
      PageRange.fromLayout(lineLayout.previous(end));

  int? _containingIndex(int offset) {
    if (_ends.isEmpty || (offset >= _ends.last && !indexComplete)) return null;
    var low = 0, high = _ends.length - 1;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_ends[middle] <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int? pageNumberAt(int offset) {
    final position = offset.clamp(0, text.length);
    if (position == 0) return 1;
    final index = _containingIndex(position);
    return index == null ? null : index + 1;
  }

  int? get currentPage => pageNumberAt(range.start);

  void seekOffset(int offset) {
    var anchor = offset.clamp(0, text.length);
    _pages.clear();
    _current = 0;
    anchor = CharacterRange.at(text, anchor).stringBeforeLength;
    _pages.add(
      anchor == text.length && text.isNotEmpty
          ? (_knownPage(anchor, endingAt: true) ?? _backward(anchor))
          : (_knownPage(anchor) ?? _forward(anchor)),
    );
    if (_ends.isEmpty && range.start == 0) _ends.add(range.end);
  }

  PageRange? _knownPage(int boundary, {bool endingAt = false}) {
    var low = 0, high = _ends.length - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final value = endingAt
          ? _ends[middle]
          : (middle == 0 ? 0 : _ends[middle - 1]);
      if (value == boundary) return _pageAt(middle);
      if (value < boundary) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return null;
  }

  bool restorePageEnds(List<int> values) =>
      values.isNotEmpty &&
      values.last == text.length &&
      restorePagePrefix(values);

  /// A validated canonical prefix can be resumed without measuring it again.
  bool restorePagePrefix(List<int> values) {
    if (_closed || values.isEmpty || values.length > 200000) return false;
    var previous = 0;
    for (final end in values) {
      if (end < 0 ||
          end > text.length ||
          (end <= previous &&
              !(text.isEmpty && values.length == 1 && end == 0)))
        return false;
      if (!CharacterRange.at(text, end).isEmpty) return false;
      previous = end;
    }
    _ends = List<int>.of(values);
    indexFailed = false;
    notifyListeners();
    return true;
  }

  void _appendPage() {
    if (indexComplete) return;
    _ends.add(_pageAt(_ends.length).end);
  }

  Future<void> _pause(Duration duration) {
    final waiter = Completer<void>();
    _indexWait = waiter;
    _indexTimer = Timer(duration, () {
      _indexTimer = null;
      _indexWait = null;
      waiter.complete();
    });
    return waiter.future;
  }

  Future<void> countAll({Duration pause = const Duration(milliseconds: 1)}) {
    if (_closed) return Future<void>.value();
    if (indexFailed) _counting = null;
    return _counting ??= _countAll(pause);
  }

  Future<void> _countAll(Duration pause) async {
    indexFailed = false;
    final announcements = Stopwatch()..start();
    var lastCurrent = currentPage;
    try {
      while (!_closed && !indexComplete) {
        final budget = Stopwatch()..start();
        var batch = 0;
        do {
          _appendPage();
          batch++;
        } while (!_closed &&
            !indexComplete &&
            batch < 16 &&
            budget.elapsedMilliseconds < 4);
        if (_closed) return;
        final now = currentPage;
        if (indexComplete ||
            now != lastCurrent ||
            announcements.elapsedMilliseconds >= 80) {
          notifyListeners();
          announcements.reset();
          lastCurrent = now;
        }
        if (!indexComplete) await _pause(pause);
      }
    } catch (_) {
      if (!_closed) {
        indexFailed = true;
        notifyListeners();
      }
    }
  }

  Future<PageLocation?> locatePage(
    int number, {
    bool Function()? cancelled,
  }) async {
    if (number < 1) throw ArgumentError.value(number, 'number');
    var batch = 0;
    final budget = Stopwatch()..start();
    while (_ends.length < number) {
      if (_closed || cancelled?.call() == true) return null;
      if (indexComplete) break;
      _appendPage();
      if (++batch >= 4 || budget.elapsedMilliseconds >= 8) {
        notifyListeners();
        await Future<void>.delayed(Duration.zero);
        batch = 0;
        budget.reset();
      }
    }
    if (_closed || cancelled?.call() == true) return null;
    notifyListeners();
    final actual = number.clamp(1, _ends.length);
    return PageLocation(actual, _pageAt(actual - 1));
  }

  PageRange get range => _pages[_current];
  int get cachedPageCount => _pages.length;
  bool get canPrevious => range.start > 0;
  bool get canNext => range.end < text.length;
  double get progress => text.isEmpty ? 0 : range.end / text.length;
  bool move(int direction) {
    if (direction == 0 || _closed) return false;
    if (direction > 0) {
      if (!canNext) return false;
      if (_current + 1 == _pages.length) {
        final next = _knownPage(range.end) ?? _forward(range.end);
        _pages.add(next);
      }
      _current++;
    } else {
      if (!canPrevious) return false;
      if (_current == 0) {
        final before =
            _knownPage(range.start, endingAt: true) ?? _backward(range.start);
        _pages.insert(0, before);
      } else {
        _current--;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _closed = true;
    _indexTimer?.cancel();
    _indexTimer = null;
    final waiter = _indexWait;
    _indexWait = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    lineLayout.dispose();
    super.dispose();
  }
}

class PageLocation {
  final int number;
  final PageRange range;
  const PageLocation(this.number, this.range);
}
