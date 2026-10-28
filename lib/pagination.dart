import 'dart:async';
import 'package:flutter/material.dart';

/// The same spans and constraints are used for measuring and rendering pages.
TextSpan readingSpan(String text, TextStyle style, double paragraphSpace) {
  final parts = text.split('\n');
  return TextSpan(
    style: style,
    children: [
      for (var i = 0; i < parts.length; i++) ...[
        TextSpan(text: parts[i]),
        if (i < parts.length - 1)
          TextSpan(
            text: '\n',
            style: TextStyle(
              height: style.height! + paragraphSpace / style.fontSize!,
            ),
          ),
      ],
    ],
  );
}

class PageRange {
  final int start, end;
  const PageRange(this.start, this.end);
}

bool _betweenSurrogates(String text, int index) =>
    index > 0 &&
    index < text.length &&
    text.codeUnitAt(index - 1) >= 0xD800 &&
    text.codeUnitAt(index - 1) <= 0xDBFF &&
    text.codeUnitAt(index) >= 0xDC00 &&
    text.codeUnitAt(index) <= 0xDFFF;

const _maxPageWindow = 12000;
final _pageWhitespace = RegExp(r'\s');

PageRange nextPage(
  String text,
  int start,
  Size size,
  TextStyle style,
  double spacing,
) {
  if (start >= text.length) return PageRange(text.length, text.length);
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  );
  bool fits(int end) {
    final safeEnd = _betweenSurrogates(text, end) ? end - 1 : end;
    painter.text = readingSpan(text.substring(start, safeEnd), style, spacing);
    painter.layout(maxWidth: size.width);
    return painter.height <= size.height;
  }

  try {
    // Grow from a small candidate instead of laying out 6,000 characters first.
    final ceiling = (start + _maxPageWindow).clamp(0, text.length);
    var low = start, high = (start + 512).clamp(0, ceiling);
    if (fits(high)) {
      low = high;
      while (low < ceiling) {
        high = (start + (high - start) * 2).clamp(0, ceiling);
        if (!fits(high)) break;
        low = high;
      }
    }
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (fits(middle)) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    var end = low;
    if (_betweenSurrogates(text, end)) end--;
    if (end <= start) {
      end = start + 1;
      if (_betweenSurrogates(text, end)) end++;
    }
    if (end < text.length) {
      // Search only this page's tail. Without nearby whitespace, a search
      // on the whole novel can walk back through all preceding pages.
      final tailStart = start + ((end - start) * 0.8).floor();
      final whitespace = text
          .substring(tailStart, end)
          .lastIndexOf(_pageWhitespace);
      if (whitespace >= 0) end = tailStart + whitespace + 1;
    }
    return PageRange(start, end);
  } finally {
    painter.dispose();
  }
}

/// Measure a contiguous preceding page without scanning from the book's start.
PageRange previousPage(
  String text,
  int end,
  Size size,
  TextStyle style,
  double spacing,
) {
  if (end <= 0) return const PageRange(0, 0);
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.noScaling,
  );
  bool fits(int start) {
    final safeStart = _betweenSurrogates(text, start) ? start + 1 : start;
    painter.text = readingSpan(text.substring(safeStart, end), style, spacing);
    painter.layout(maxWidth: size.width);
    return painter.height <= size.height;
  }

  try {
    final floor = (end - _maxPageWindow).clamp(0, end);
    var low = (end - 512).clamp(floor, end), high = end;
    if (fits(low)) {
      high = low;
      while (high > floor) {
        low = (end - (end - low) * 2).clamp(floor, end);
        if (!fits(low)) break;
        high = low;
      }
    }
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (fits(middle)) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    var start = high;
    if (_betweenSurrogates(text, start)) start++;
    if (start >= end) {
      start = end - 1;
      if (_betweenSurrogates(text, start)) start--;
    }
    if (start > 0) {
      final prefixEnd = start + ((end - start) * 0.2).floor();
      final whitespace = text
          .substring(start, prefixEnd)
          .indexOf(_pageWhitespace);
      if (whitespace >= 0) start += whitespace + 1;
    }
    return PageRange(start, end);
  } finally {
    painter.dispose();
  }
}

/// Opens a single page immediately. The canonical page index can be completed
/// cooperatively after first paint, or restored from a validated layout cache.
class PageSession extends ChangeNotifier {
  final String text;
  final Size size;
  final TextStyle style;
  final double spacing;
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
    seekOffset(offset);
  }

  bool get indexComplete => _ends.isNotEmpty && _ends.last >= text.length;
  int? get totalPages => indexComplete ? _ends.length : null;
  int get indexedPages => _ends.length;
  double get indexProgress => text.isEmpty
      ? (indexComplete ? 1 : 0)
      : (_ends.isEmpty ? 0 : _ends.last / text.length);
  List<int> get pageEnds => List<int>.unmodifiable(_ends);
  PageRange _pageAt(int i) => PageRange(i == 0 ? 0 : _ends[i - 1], _ends[i]);

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
    if (_betweenSurrogates(text, anchor)) anchor--;
    _pages.add(
      anchor == text.length && text.isNotEmpty
          ? (_knownPage(anchor, endingAt: true) ??
                previousPage(text, anchor, size, style, spacing))
          : (_knownPage(anchor) ??
                nextPage(text, anchor, size, style, spacing)),
    );
    if (_ends.isEmpty && range.start == 0) _ends.add(range.end);
  }

  PageRange? _knownPage(int boundary, {bool endingAt = false}) {
    var low = 0, high = _ends.length - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final page = _pageAt(middle);
      final value = endingAt ? page.end : page.start;
      if (value == boundary) return page;
      if (value < boundary) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return null;
  }

  bool restorePageEnds(List<int> values) {
    if (_closed ||
        values.isEmpty ||
        values.length > 200000 ||
        values.last != text.length)
      return false;
    var previous = 0;
    for (final end in values) {
      if (end < 0 ||
          end > text.length ||
          (end <= previous &&
              !(text.isEmpty && values.length == 1 && end == 0)))
        return false;
      if (_betweenSurrogates(text, end)) return false;
      previous = end;
    }
    _ends = List<int>.of(values);
    indexFailed = false;
    notifyListeners();
    return true;
  }

  void _appendPage() {
    if (indexComplete) return;
    _ends.add(
      nextPage(text, _ends.isEmpty ? 0 : _ends.last, size, style, spacing).end,
    );
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

  Future<void> countAll({Duration pause = const Duration(milliseconds: 8)}) {
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
            batch < 4 &&
            budget.elapsedMilliseconds < 6);
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
  bool get canNext =>
      indexComplete ? currentPage! < totalPages! : range.end < text.length;
  double get progress => text.isEmpty ? 0 : range.end / text.length;
  bool move(int direction) {
    if (direction == 0 || _closed) return false;
    if (direction > 0) {
      if (!canNext) return false;
      if (_current + 1 == _pages.length) {
        final next = indexComplete
            ? _pageAt(_containingIndex(range.start)! + 1)
            : (_knownPage(range.end) ??
                  nextPage(text, range.end, size, style, spacing));
        _pages.add(next);
      }
      _current++;
    } else {
      if (!canPrevious) return false;
      if (_current == 0) {
        final before = indexComplete
            ? _pageAt(
                (_containingIndex(range.start)! - 1).clamp(0, _ends.length - 1),
              )
            : (_knownPage(range.start, endingAt: true) ??
                  previousPage(text, range.start, size, style, spacing));
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
    super.dispose();
  }
}

class PageLocation {
  final int number;
  final PageRange range;
  const PageLocation(this.number, this.range);
}
