/// 대화내용 신고 창 (2026-10-12, 사용자 결정). 철학자의 답을 길게 눌러 "대화내용 신고"를 고르면 열린다.
/// 사유 하나를 고르고, "기타"는 직접 적는다. 보내면 그 질문과 답이 함께 개발자에게 간다 (설정 → 신고 내역).
/// 대화 내용이 개발자에게 제공된다는 데 동의해야 보낼 수 있다 (사용자 결정 2026-10-12).
library;

import 'package:flutter/material.dart' hide Text;

import 'keep_words.dart';

/// 신고 사유. 첫 줄은 대화 상대의 이름이 들어간다.
List<String> reportReasons(String personaName) => [
  '$personaName의 사상과 맞지 않음',
  '폭력적인 발화',
  '혐오·차별 표현',
  '선정적인 내용',
  '사실과 다른 내용 (없는 인용·잘못된 출처)',
  '위험하거나 부적절한 조언',
];

const reportOther = '기타';

/// 고른 사유와 직접 입력한 내용. 취소하면 null.
Future<({String reason, String? detail})?> showReportDialog(
  BuildContext context, {
  required String personaName,
}) {
  return showDialog<({String reason, String? detail})>(
    context: context,
    builder: (_) => _ReportDialog(personaName: personaName),
  );
}

class _ReportDialog extends StatefulWidget {
  final String personaName;
  const _ReportDialog({required this.personaName});

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _detail = TextEditingController();
  String? _reason;
  bool _agreed = false;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  bool get _ready =>
      _agreed &&
      _reason != null &&
      (_reason != reportOther || _detail.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('대화내용 신고'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SingleChildScrollView(
        child: RadioGroup<String>(
          groupValue: _reason,
          onChanged: (v) => setState(() => _reason = v),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text(
                  '${widget.personaName}의 답변을 검토할 수 있도록 사유를 골라 주세요.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              for (final r in [
                ...reportReasons(widget.personaName),
                reportOther,
              ])
                RadioListTile<String>(
                  key: ValueKey('reason-$r'),
                  value: r,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(r == reportOther ? '기타 (직접 입력)' : r),
                ),
              if (_reason == reportOther)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    key: const Key('report-detail'),
                    controller: _detail,
                    autofocus: true,
                    maxLength: 1000,
                    maxLines: 3,
                    minLines: 1,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: '신고 사유를 적어 주세요',
                    ),
                  ),
                ),
              const Divider(height: 24),
              CheckboxListTile(
                key: const Key('report-agree'),
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text(
                  '신고한 질문과 답(대화 내용)이 확인을 위해 개발자에게 제공되는 것에 동의합니다.',
                ),
                subtitle: Text(
                  '동의해야 신고할 수 있습니다.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          key: const Key('report-send'),
          onPressed: _ready
              ? () => Navigator.pop(context, (
                  reason: _reason!,
                  detail: _reason == reportOther ? _detail.text.trim() : null,
                ))
              : null,
          child: const Text('신고'),
        ),
      ],
    );
  }
}
