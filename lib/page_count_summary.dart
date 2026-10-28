import 'package:flutter/material.dart';
import 'pagination.dart';

class PageCountSummary extends StatelessWidget {
  final PageSession session;
  final bool compact;
  const PageCountSummary({
    super.key,
    required this.session,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final current = session.currentPage;
      final total = session.totalPages;
      final estimated = session.estimatedTotalPages;
      final estimate = estimated == null ? '전체 예상 준비 중' : '전체 약 $estimated쪽';
      final calculating =
          '쪽수 계산 ${(session.indexProgress * 100).toStringAsFixed(0)}%';
      final text = total != null
          ? '$current / $total쪽'
          : session.indexFailed
          ? '전체 쪽수 계산 실패'
          : current != null
          ? '$current쪽 / $estimate · 계산 중'
          : '$estimate · 현재 쪽수 계산 중';
      if (compact)
        return Text(
          '${session.indexFailed
              ? '쪽수 계산 실패'
              : total != null
              ? '$current / $total쪽'
              : current != null
              ? '$current / 약 ${estimated ?? '?'}쪽 · $calculating'
              : '$estimate · $calculating'} · 읽기 ${(session.progress * 100).toStringAsFixed(1)}%',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall,
        );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            total != null ? '현재 $current쪽 / 전체 $total쪽' : text,
            key: const ValueKey('page-count-summary'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (total == null && !session.indexFailed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$calculating · 예상 쪽수는 달라질 수 있습니다. 계산 중에도 읽거나 이동할 수 있습니다.',
              ),
            ),
        ],
      );
    },
  );
}
