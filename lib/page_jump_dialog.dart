import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pagination.dart';
import 'page_count_summary.dart';

class PageJumpSelection {
  final int offset;
  final int? requestedPage, actualPage;
  const PageJumpSelection(this.offset, {this.requestedPage, this.actualPage});
}

class PageJumpDialog extends StatefulWidget {
  final PageSession session;
  final bool Function()? isCurrent;
  const PageJumpDialog({super.key, required this.session, this.isCurrent});
  @override
  State<PageJumpDialog> createState() => _PageJumpDialogState();
}

class _PageJumpDialogState extends State<PageJumpDialog> {
  late double percent;
  late final TextEditingController percentText;
  final pageText = TextEditingController();
  bool validPercent = true, busy = false, cancelled = false;
  String? error;
  @override
  void initState() {
    super.initState();
    percent = widget.session.text.isEmpty
        ? 0
        : widget.session.range.start * 100 / widget.session.text.length;
    percentText = TextEditingController(text: percent.toStringAsFixed(1));
  }

  @override
  void dispose() {
    cancelled = true;
    percentText.dispose();
    pageText.dispose();
    super.dispose();
  }

  Future<void> locate() async {
    final number = int.tryParse(pageText.text);
    if (number == null || number < 1 || number > 1000000) {
      setState(() => error = '1~1,000,000 사이의 쪽 번호를 입력해 주세요.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final page = await widget.session.locatePage(
        number,
        cancelled: () => cancelled || widget.isCurrent?.call() == false,
      );
      if (!mounted || cancelled) return;
      if (page == null) {
        Navigator.pop(context);
        return;
      }
      Navigator.pop(
        context,
        PageJumpSelection(
          page.range.start,
          requestedPage: number,
          actualPage: page.number,
        ),
      );
    } catch (_) {
      if (mounted)
        setState(() {
          busy = false;
          error = '쪽 번호를 계산하지 못했습니다. 다시 시도해 주세요.';
        });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) => AlertDialog(
      scrollable: true,
      title: const Text('페이지 이동'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageCountSummary(session: widget.session),
            const SizedBox(height: 16),
            const Text('진행률로 바로 이동'),
            Slider(
              value: percent.clamp(0, 100),
              min: 0,
              max: 100,
              label: '${percent.toStringAsFixed(1)}%',
              onChanged: busy
                  ? null
                  : (value) => setState(() {
                      percent = value;
                      validPercent = true;
                      percentText.text = value.toStringAsFixed(1);
                    }),
            ),
            TextField(
              controller: percentText,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: '이동할 위치 (%)',
                border: const OutlineInputBorder(),
                errorText: validPercent ? null : '0~100 사이의 값을 입력해 주세요.',
              ),
              onChanged: (value) => setState(() {
                final parsed = double.tryParse(value.replaceAll(',', '.'));
                validPercent =
                    parsed != null &&
                    parsed.isFinite &&
                    parsed >= 0 &&
                    parsed <= 100;
                if (validPercent) percent = parsed!;
              }),
            ),
            const SizedBox(height: 8),
            Text(
              '이동할 쪽: ${widget.session.pageNumberAt((widget.session.text.length * percent / 100).floor()) ?? '약 ${widget.session.estimatedPageAt((widget.session.text.length * percent / 100).floor()) ?? '?'}'} / ${widget.session.totalPages ?? '약 ${widget.session.estimatedTotalPages ?? '?'}'}쪽',
              key: const ValueKey('target-page-preview'),
            ),
            FilledButton(
              onPressed: busy || !validPercent
                  ? null
                  : () => Navigator.pop(
                      context,
                      PageJumpSelection(
                        (widget.session.text.length * percent / 100).floor(),
                      ),
                    ),
              child: const Text('위치로 이동'),
            ),
            const Divider(height: 28),
            const Text('쪽 번호로 이동'),
            const SizedBox(height: 8),
            TextField(
              controller: pageText,
              enabled: !busy,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(7),
              ],
              decoration: InputDecoration(
                labelText: widget.session.totalPages == null
                    ? '이동할 쪽 번호'
                    : '이동할 쪽 번호 (1~${widget.session.totalPages})',
                hintText: '예: 100',
                border: OutlineInputBorder(),
              ),
              onSubmitted: busy ? null : (_) => locate(),
            ),
            const SizedBox(height: 8),
            const Text('쪽 번호는 현재 글꼴과 화면 크기 기준입니다. 큰 번호는 계산 시간이 걸릴 수 있습니다.'),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Expanded(child: Text('쪽 번호 계산 중…')),
                  ],
                ),
              ),
            if (error case final message?)
              Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            OutlinedButton(
              onPressed: busy ? null : locate,
              child: const Text('쪽으로 이동'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            cancelled = true;
            Navigator.pop(context);
          },
          child: const Text('취소'),
        ),
      ],
    ),
  );
}
