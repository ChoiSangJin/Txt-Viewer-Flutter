import 'package:flutter/material.dart';

/// The same spans and constraints are used for measuring and rendering pages.
TextSpan readingSpan(String text, TextStyle style, double paragraphSpace) {
  final parts = text.split('\n');
  return TextSpan(style: style, children: [
    for (var i = 0; i < parts.length; i++) ...[
      TextSpan(text: parts[i]),
      if (i < parts.length - 1)
        TextSpan(text: '\n', style: TextStyle(
          height: style.height! + paragraphSpace / style.fontSize!)),
    ],
  ]);
}

class PageRange {
  final int start, end;
  const PageRange(this.start, this.end);
}

bool _betweenSurrogates(String text, int index) => index > 0 && index < text.length &&
  text.codeUnitAt(index - 1) >= 0xD800 && text.codeUnitAt(index - 1) <= 0xDBFF &&
  text.codeUnitAt(index) >= 0xDC00 && text.codeUnitAt(index) <= 0xDFFF;

PageRange nextPage(String text, int start, Size size, TextStyle style, double spacing) {
  final painter = TextPainter(textDirection: TextDirection.ltr, textScaler: TextScaler.noScaling);
  bool fits(int end) {
    painter.text = readingSpan(text.substring(start, end), style, spacing);
    painter.layout(maxWidth: size.width);
    return painter.height <= size.height;
  }
  var low = start, high = (start + 12000).clamp(0, text.length);
  while (low < high) {
    final middle = (low + high + 1) ~/ 2;
    if (fits(middle)) { low = middle; } else { high = middle - 1; }
  }
  var end = low;
  // Never split UTF-16 pairs. A normal reader viewport always fits a glyph.
  if (_betweenSurrogates(text, end)) end--;
  if (end <= start) {
    end = start + 1;
    if (_betweenSurrogates(text, end)) end++;
  }
  if (end < text.length) {
    final whitespace = text.lastIndexOf(RegExp(r'\s'), end - 1);
    if (whitespace > start + (end - start) * 0.8) end = whitespace + 1;
  }
  painter.dispose();
  return PageRange(start, end);
}
