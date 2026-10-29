import 'dart:collection';
import 'package:flutter/material.dart';

/// A bounded layout window; a page retains only offsets, never a native paragraph.
class LineSlice {
  final int blockStart, blockLimit;
  final double sourceTop, targetTop, height;
  const LineSlice(
    this.blockStart,
    this.blockLimit,
    this.sourceTop,
    this.targetTop,
    this.height,
  );
}

class LinePage {
  final int start, end;
  final double height;
  final List<LineSlice> slices;
  const LinePage(this.start, this.end, this.height, this.slices);
}

class _Line {
  final int start, end;
  final double top, height, gap;
  const _Line(this.start, this.end, this.top, this.height, this.gap);
}

class _Block {
  final int start, limit, end, rawEnd;
  final TextPainter painter;
  final List<_Line> lines;
  Color? color;
  _Block(
    this.start,
    this.limit,
    this.end,
    this.rawEnd,
    this.painter,
    this.lines,
    this.color,
  );
}

class _Group {
  final List<LinePage> pages = [];
  int cursor;
  int? blockStart, blockLimit;
  int line = 0;
  _Group(int start) : cursor = start;
}

/// Measures bounded text windows once, then packs their existing lines into pages.
/// Canonical groups restart every four pages, so a restored page index needs no
/// book-prefix layout to recover the exact shaping context used by the renderer.
class LineLayout {
  static const pagesPerGroup = 4;
  static const windowCharacters = 2048;
  static const maxBlocks = 12;
  static const maxWindowCharacters = 16384;
  final String text;
  final Size size;
  final TextStyle style;
  final double spacing;
  final _blocks = LinkedHashMap<String, _Block>();
  final _groups = LinkedHashMap<int, _Group>();
  bool closed = false;
  int layoutCalls = 0, measuredCharacters = 0;
  Color _paintColor = Colors.black;
  int get cachedBlocks => _blocks.length;
  int get cachedCharacters =>
      _blocks.values.fold(0, (n, b) => n + b.rawEnd - b.start);
  LineLayout(this.text, this.size, this.style, this.spacing);

  int safeOffset(int value) {
    var offset = value.clamp(0, text.length);
    if (offset > 0 &&
        offset < text.length &&
        text.codeUnitAt(offset - 1) >= 0xD800 &&
        text.codeUnitAt(offset - 1) <= 0xDBFF &&
        text.codeUnitAt(offset) >= 0xDC00 &&
        text.codeUnitAt(offset) <= 0xDFFF)
      offset--;
    return offset;
  }

  _Block _block(int start, {int? limit}) {
    final stop = limit ?? text.length;
    final key = '$start/$stop';
    final hit = _blocks.remove(key);
    if (hit != null) {
      _blocks[key] = hit;
      return hit;
    }
    var end = safeOffset((start + windowCharacters).clamp(start, stop));
    _Block? result;
    while (true) {
      final painter = TextPainter(
        text: TextSpan(
          text: text.substring(start, end),
          style: style.copyWith(color: _paintColor),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout(maxWidth: size.width);
      layoutCalls++;
      measuredCharacters += end - start;
      final metrics = painter.computeLineMetrics();
      final lines = <_Line>[];
      var cursor = start;
      for (final line in metrics) {
        if (cursor >= end)
          break; // Ignore the synthetic empty line after a final LF.
        int lineEnd;
        if (line.hardBreak) {
          final localNewline = painter.plainText.indexOf('\n', cursor - start);
          lineEnd = localNewline >= 0 ? start + localNewline + 1 : end;
        } else {
          final position = painter.getPositionForOffset(
            Offset(
              line.left + line.width / 2,
              line.baseline - line.unscaledAscent / 2,
            ),
          );
          lineEnd = start + painter.getLineBoundary(position).end;
        }
        lineEnd = safeOffset(lineEnd.clamp(cursor, end));
        if (lineEnd <= cursor) continue;
        lines.add(
          _Line(
            cursor,
            lineEnd,
            line.baseline - line.ascent,
            line.height,
            text.codeUnitAt(lineEnd - 1) == 10 ? spacing : 0,
          ),
        );
        cursor = lineEnd;
      }
      // A truncated last line may wrap differently when more text arrives.
      // Commit only complete lines and shape the remaining tail in the next window.
      if (end < stop && lines.isNotEmpty && text.codeUnitAt(end - 1) != 10) {
        lines.removeLast();
      }
      if (lines.isNotEmpty ||
          end >= stop ||
          end - start >= maxWindowCharacters) {
        if (lines.isEmpty && start < stop) {
          // An exceptionally long indivisible cluster or very wide single line.
          // Keep forward progress while retaining every UTF-16 code unit.
          final m = metrics.first;
          lines.add(_Line(start, end, 0, m.height, 0));
        }
        result = _Block(
          start,
          stop,
          lines.isEmpty ? start : lines.last.end,
          end,
          painter,
          lines,
          _paintColor,
        );
        break;
      }
      painter.dispose();
      end = safeOffset((start + (end - start) * 2).clamp(start, stop));
    }
    _blocks[key] = result;
    // Bound native paragraphs by both item count and measured source length.
    while (_blocks.length > maxBlocks ||
        (cachedCharacters > 32768 && _blocks.length > 1)) {
      final first = _blocks.remove(_blocks.keys.first)!;
      first.painter.dispose();
    }
    return result;
  }

  void _addSlice(List<LineSlice> slices, _Block block, _Line line, double y) {
    if (slices.isNotEmpty) {
      final last = slices.last;
      if (last.blockStart == block.start &&
          last.blockLimit == block.limit &&
          (last.sourceTop + last.height - line.top).abs() < 0.01 &&
          (last.targetTop + last.height - y).abs() < 0.01) {
        slices[slices.length - 1] = LineSlice(
          last.blockStart,
          last.blockLimit,
          last.sourceTop,
          last.targetTop,
          last.height + line.height,
        );
        return;
      }
    }
    slices.add(LineSlice(block.start, block.limit, line.top, y, line.height));
  }

  LinePage page(int groupStart, int index) {
    assert(index >= 0 && index < pagesPerGroup);
    final group = _groups.remove(groupStart) ?? _Group(groupStart);
    _groups[groupStart] = group;
    while (_groups.length > 4) {
      _groups.remove(_groups.keys.first);
    }
    while (group.pages.length <= index) {
      final start = group.cursor;
      var y = 0.0;
      final slices = <LineSlice>[];
      while (group.cursor < text.length) {
        final block = _block(
          group.blockStart ?? group.cursor,
          limit: group.blockLimit,
        );
        group.blockStart = block.start;
        group.blockLimit = block.limit;
        if (group.line >= block.lines.length) {
          group.blockStart = block.end;
          group.blockLimit = null;
          group.line = 0;
          continue;
        }
        final line = block.lines[group.line];
        if (slices.isNotEmpty && y + line.height > size.height + 0.01) break;
        _addSlice(slices, block, line, y);
        group.cursor = line.end;
        group.line++;
        y += line.height + line.gap;
        if (y >= size.height) break;
      }
      group.pages.add(
        LinePage(start, group.cursor, y.clamp(0, size.height), slices),
      );
    }
    return group.pages[index];
  }

  /// A nearby bounded suffix is sufficient to show the page preceding an anchor.
  LinePage previous(int end) {
    if (end <= 0) return const LinePage(0, 0, 0, []);
    final start = CharacterRange.at(
      text,
      safeOffset((end - windowCharacters).clamp(0, end)),
    ).stringBeforeLength;
    var cursor = start;
    final rows = <(_Block, _Line)>[];
    while (cursor < end) {
      final block = _block(cursor, limit: end);
      for (final row in block.lines) {
        rows.add((block, row));
      }
      cursor = block.end;
    }
    var first = rows.length - 1;
    var height = rows.last.$2.height;
    while (first > 0) {
      final row = rows[first - 1].$2;
      final extra = row.height + row.gap;
      if (height + extra > size.height + 0.01) break;
      height += extra;
      first--;
    }
    final slices = <LineSlice>[];
    var y = 0.0;
    for (var i = first; i < rows.length; i++) {
      _addSlice(slices, rows[i].$1, rows[i].$2, y);
      y += rows[i].$2.height + rows[i].$2.gap;
    }
    return LinePage(
      rows[first].$2.start,
      end,
      height.clamp(0, size.height),
      slices,
    );
  }

  void paint(Canvas canvas, LinePage page, Color color) {
    if (closed) return;
    _paintColor = color;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final slice in page.slices) {
      final block = _block(slice.blockStart, limit: slice.blockLimit);
      if (block.color != color) {
        block.painter.text = TextSpan(
          text: text.substring(block.start, block.rawEnd),
          style: style.copyWith(color: color),
        );
        block.painter.layout(maxWidth: size.width);
        block.color = color;
      }
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(0, slice.targetTop, size.width, slice.height),
      );
      block.painter.paint(canvas, Offset(0, slice.targetTop - slice.sourceTop));
      canvas.restore();
    }
    canvas.restore();
  }

  void dispose() {
    if (closed) return;
    closed = true;
    for (final block in _blocks.values) {
      block.painter.dispose();
    }
    _blocks.clear();
    _groups.clear();
  }
}

class LinePagePainter extends CustomPainter {
  final LineLayout layout;
  final LinePage page;
  final Color color;
  LinePagePainter(this.layout, this.page, this.color);
  @override
  void paint(Canvas canvas, Size size) => layout.paint(canvas, page, color);
  @override
  bool shouldRepaint(covariant LinePagePainter old) =>
      old.layout != layout || old.page != page || old.color != color;
}
