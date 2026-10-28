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
    painter.text = readingSpan(text.substring(start, end), style, spacing);
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
    painter.text = readingSpan(text.substring(start, end), style, spacing);
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

/// Keeps only pages actually visited. Construction never indexes the whole book,
/// including when resuming near its end or reflowing after a setting change.
class PageSession {
  final String text;
  final Size size;
  final TextStyle style;
  final double spacing;
  final List<PageRange> _pages = [];
  int _current = 0;
  PageSession({
    required this.text,
    required this.size,
    required this.style,
    required this.spacing,
    int offset = 0,
  }) {
    var anchor = offset.clamp(0, text.length);
    if (_betweenSurrogates(text, anchor)) anchor--;
    _pages.add(
      anchor == text.length && text.isNotEmpty
          ? previousPage(text, anchor, size, style, spacing)
          : nextPage(text, anchor, size, style, spacing),
    );
  }
  PageRange get range => _pages[_current];
  int get cachedPageCount => _pages.length;
  bool get canPrevious => range.start > 0;
  bool get canNext => range.end < text.length;
  double get progress => text.isEmpty ? 0 : range.end / text.length;
  bool move(int direction) {
    if (direction == 0) return false;
    if (direction > 0) {
      if (!canNext) return false;
      if (_current + 1 == _pages.length) {
        _pages.add(nextPage(text, range.end, size, style, spacing));
      }
      _current++;
    } else {
      if (!canPrevious) return false;
      if (_current == 0) {
        _pages.insert(0, previousPage(text, range.start, size, style, spacing));
      } else {
        _current--;
      }
    }
    return true;
  }
}
