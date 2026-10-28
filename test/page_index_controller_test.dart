import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:txt_viewer/pagination.dart';
import 'package:txt_viewer/page_index_controller.dart';

PageSession book() => PageSession(
  text: List.filled(10000, '한글 소설 문장입니다.\n다음 문단입니다.\n').join(),
  size: const Size(300, 400),
  style: const TextStyle(fontSize: 20, height: 1.7),
  spacing: 12,
);

void main() {
  testWidgets(
    'checkpoint and close save partial counts; reopening resumes them',
    (tester) async {
      List<int>? cached;
      var writes = 0;
      PageIndexController controller(PageSession pages) => PageIndexController(
        session: pages,
        load: () async => {'token': 'book-layout', 'ends': cached},
        save: (token, ends) async {
          cached = ends;
          writes++;
        },
      );
      final first = book();
      final one = controller(first);
      final counting = one.start();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(writes, greaterThanOrEqualTo(1));
      expect(cached!.last, lessThan(first.text.length));
      await one.close();
      first.dispose();
      await counting;
      final prefix = List<int>.of(cached!);
      final second = book();
      final two = controller(second);
      final resumed = two.start();
      await tester.pump();
      expect(second.pageEnds.take(prefix.length), prefix);
      expect(second.indexedPages, greaterThan(prefix.length));
      await two.close();
      second.dispose();
      await resumed;
    },
  );

  testWidgets('slow saves stay ordered and closing queues the latest prefix', (
    tester,
  ) async {
    final gate = Completer<void>();
    final saved = <List<int>>[];
    final pages = book();
    final controller = PageIndexController(
      session: pages,
      load: () async => {'token': 'token'},
      save: (token, ends) async {
        if (saved.isEmpty) await gate.future;
        saved.add(ends);
      },
    );
    final counting = controller.start();
    await tester.pump();
    controller.flush();
    await tester.pump(const Duration(milliseconds: 100));
    final finalCount = pages.indexedPages;
    final closing = controller.close();
    pages.dispose();
    gate.complete();
    await closing;
    await counting;
    expect(saved.length, 2);
    expect(saved.last.length, finalCount);
    expect(saved.last.take(saved.first.length), saved.first);
  });

  testWidgets(
    'load and save failures do not stop counting and save can retry',
    (tester) async {
      final pages = book();
      var attempts = 0;
      final controller = PageIndexController(
        session: pages,
        load: () async => {
          'token': 'token',
          'ends': [-1, 2],
        },
        save: (token, ends) async {
          if (++attempts == 1) throw StateError('disk');
        },
      );
      final counting = controller.start();
      await tester.pump();
      await controller.flush();
      await controller.flush();
      expect(attempts, 2);
      expect(pages.indexedPages, greaterThan(1));
      await controller.close();
      pages.dispose();
      await counting;
      final unavailable = book();
      final noCache = PageIndexController(
        session: unavailable,
        load: () async => throw StateError('unavailable'),
        save: (_, _) async => fail('no valid cache token'),
      );
      final uncached = noCache.start();
      await tester.pump();
      expect(unavailable.indexedPages, greaterThan(1));
      await noCache.close();
      unavailable.dispose();
      await uncached;
    },
  );

  testWidgets('closing before load completes never starts a stale counter', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>?>();
    final pages = book();
    final controller = PageIndexController(
      session: pages,
      load: () => pending.future,
      save: (_, _) async => fail('closed before cache load'),
    );
    final counting = controller.start();
    await controller.close();
    pages.dispose();
    pending.complete({'token': 'token'});
    await counting;
    expect(pages.indexedPages, 1);
  });
}
