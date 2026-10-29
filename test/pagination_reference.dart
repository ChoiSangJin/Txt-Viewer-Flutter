// Previous release's exact boundary search, retained as a regression oracle.
import 'package:flutter/material.dart';
import 'package:txt_viewer/pagination.dart' show PageRange;

int legacyLayoutCalls = 0;
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

bool _betweenSurrogates(String text, int index) =>
    index > 0 &&
    index < text.length &&
    text.codeUnitAt(index - 1) >= 0xD800 &&
    text.codeUnitAt(index - 1) <= 0xDBFF &&
    text.codeUnitAt(index) >= 0xDC00 &&
    text.codeUnitAt(index) <= 0xDFFF;

const _maxPageWindow = 12000;
final _pageWhitespace = RegExp(r'\s');

PageRange legacyNextPage(
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
    legacyLayoutCalls++;
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
    // The oversized paragraph already knows where the bottom visible line is.
    // Probe its start to narrow the exact search to roughly one line, rather
    // than repeatedly laying out every possible page-sized substring.
    // Paragraph spacing can make a trailing newline's height differ from the
    // same newline followed by text. Keep the established search for those
    // mixed-height spans; use the shortcut only within a single paragraph.
    if (low < high && !text.substring(start, high).contains('\n')) {
      final local = painter.getPositionForOffset(Offset(0, size.height)).offset;
      var probe =
          start + painter.getLineBoundary(TextPosition(offset: local)).start;
      if (_betweenSurrogates(text, probe)) probe--;
      if (probe > low && probe < high) {
        if (fits(probe)) {
          low = probe;
        } else {
          high = probe - 1;
        }
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
