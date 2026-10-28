import 'dart:async';
import 'pagination.dart';

/// Saves growing prefixes in order, including on close or application pause.
class PageIndexController {
  final PageSession session;
  final Future<Map<String, dynamic>?> Function() load;
  final Future<void> Function(String token, List<int> ends) save;
  final Duration interval;
  String? _token;
  bool _closed = false;
  int _saved = 0;
  Timer? _timer;
  Future<void> _writes = Future<void>.value();
  PageIndexController({
    required this.session,
    required this.load,
    required this.save,
    this.interval = const Duration(seconds: 2),
  });

  Future<void> start() async {
    Map<String, dynamic>? cached;
    try {
      cached = await load();
    } catch (_) {
      /* A cache failure must not stop reading or counting. */
    }
    if (_closed) return;
    _token = cached?['token'] is String ? cached!['token'] as String : null;
    final raw = cached?['ends'];
    if (raw is List &&
        raw.every((e) => e is int) &&
        session.restorePagePrefix(raw.cast<int>())) {
      _saved = raw.length;
    }
    session.addListener(_changed);
    _changed();
    await session.countAll();
    if (!_closed) await flush();
  }

  void _changed() {
    if (_closed || _timer != null) return;
    _timer = Timer(interval, () {
      _timer = null;
      flush();
    });
  }

  Future<void> flush() {
    final token = _token;
    final count = session.indexedPages;
    if (token == null || count <= _saved || count > 200000) return _writes;
    final ends = session.pageEnds;
    _saved = count;
    _writes = _writes.then((_) async {
      try {
        await save(token, ends);
      } catch (_) {
        // Retry the latest prefix on the next checkpoint or close.
        if (_saved == count) _saved = 0;
      }
    });
    return _writes;
  }

  Future<void> close() {
    if (_closed) return _writes;
    _closed = true;
    _timer?.cancel();
    session.removeListener(_changed);
    return flush();
  }
}
