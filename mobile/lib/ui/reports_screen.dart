/// 신고 내역 — 개발자만 (2026-10-12, 사용자 결정). 설정 화면의 "개발자 · 신고 내역"에서 열린다.
/// 서버가 .env 의 ADMIN_USERS 로 개발자인지 확인한다 (아니면 403). 최근 신고부터, 질문·답이 함께 보인다.
library;

import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../data/persona_profiles.dart';

class ReportsScreen extends StatefulWidget {
  final PhiloRagClient Function() client;
  const ReportsScreen({super.key, required this.client});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late Future<List<ReportItem>> _items = _load();

  Future<List<ReportItem>> _load() async {
    final c = widget.client();
    try {
      return await c.reports();
    } finally {
      c.close();
    }
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _items = f);
    await f.catchError((_) => <ReportItem>[]);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _when(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('신고 내역')),
      body: FutureBuilder<List<ReportItem>>(
        future: _items,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('불러오지 못했습니다: ${snap.error}', textAlign: TextAlign.center),
              ),
            );
          }
          final items = snap.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: items.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 120),
                    Center(child: Text('신고가 없습니다')),
                  ])
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = items[i];
                      final name = profileFor(r.persona)?.name ?? r.persona;
                      return ExpansionTile(
                        key: ValueKey('report-${r.id}'),
                        title: Text('$name · ${r.reason}'),
                        subtitle: Text('#${r.id} · ${_when(r.createdAt)} · ${r.userId}',
                            style: theme.textTheme.bodySmall),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          if (r.detail != null) ...[
                            Text('직접 입력', style: theme.textTheme.labelMedium),
                            SelectableText(r.detail!),
                            const SizedBox(height: 12),
                          ],
                          Text('질문', style: theme.textTheme.labelMedium),
                          SelectableText(r.question.isEmpty ? '(질문 없음)' : r.question),
                          const SizedBox(height: 12),
                          Text('답', style: theme.textTheme.labelMedium),
                          SelectableText(r.answer),
                        ],
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}
