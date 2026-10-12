/// 백엔드 응답 모델. backend/app/main.py 의 Pydantic 모델과 1:1 이다.
/// 필드를 바꾸면 서버 쪽도 같이 바꿔야 한다 (CLAUDE.md 9절).
library;

class Persona {
  final String key; // "nietzsche" | "jesus" | "buddha"
  final String name; // 화면에 보일 이름
  final String blurb; // 한 줄 소개
  final bool enabled;

  const Persona({
    required this.key,
    required this.name,
    required this.blurb,
    required this.enabled,
  });

  factory Persona.fromJson(Map<String, dynamic> j) => Persona(
        key: j['key'] as String,
        name: j['name'] as String,
        blurb: j['blurb'] as String? ?? '',
        enabled: j['enabled'] as bool? ?? true,
      );
}

/// 답변의 근거 구절. 위치(한글 작품명 포함)만 온다. 본문은 오지 않는다.
class Source {
  final String chunkId; // 서버 인덱스의 청크 키 (예: "jesus#12"). 디버그·대조용
  final String work; // 작품명 영어 (코퍼스 표기, "THE DHAMMAPADA")
  final String workKo; // 작품명 한글 ("법구경"). 목록에는 이걸 보여준다
  final String ref; // "17:221~17:234" 또는 "1:1"
  final String? title; // 구분(장·경) 제목 (영어, 비어 있을 수 있음)
  final double score; // 코사인 유사도 0~1

  const Source({
    required this.chunkId,
    required this.work,
    required this.workKo,
    required this.ref,
    required this.title,
    required this.score,
  });

  /// 화면에 보일 위치 표기. 예: "마태복음 6:17~6:31"
  String get label => '$workKo $ref';

  factory Source.fromJson(Map<String, dynamic> j) => Source(
        chunkId: j['chunk_id'] as String? ?? '',
        work: j['work'] as String,
        workKo: j['work_ko'] as String? ?? j['work'] as String,
        ref: j['ref'] as String,
        title: j['title'] as String?,
        score: (j['score'] as num).toDouble(),
      );

  /// 서버 응답과 같은 꼴. 폰에 대화를 저장할 때 쓴다 (state/chat_storage.dart)
  Map<String, dynamic> toJson() => {
        'chunk_id': chunkId,
        'work': work,
        'work_ko': workKo,
        'ref': ref,
        'title': title,
        'score': score,
      };
}

/// 답변 속 용어·호칭의 뜻. 각주로 보여준다 (CLAUDE.md 6.20). 지금은 부처만 채워져 있다.
class GlossaryItem {
  final String term;
  final String meaning;

  const GlossaryItem({required this.term, required this.meaning});

  factory GlossaryItem.fromJson(Map<String, dynamic> j) => GlossaryItem(
        term: j['term'] as String,
        meaning: j['meaning'] as String,
      );

  Map<String, dynamic> toJson() => {'term': term, 'meaning': meaning};
}

/// 요금제와 오늘 사용량 (backend/app/plans.py). 로그인이 없어 사용자는 기기별 ID 로 구분된다.
class UsageInfo {
  final String plan; // "personal" | "pro"
  final String planName; // 화면 표시용 ("Personal")
  final int usedToday; // 오늘 쓴 질문 수 (이번 질문 포함)
  final int? dailyLimit; // null 이면 무제한

  const UsageInfo({
    required this.plan,
    required this.planName,
    required this.usedToday,
    required this.dailyLimit,
  });

  bool get unlimited => dailyLimit == null;

  /// 오늘 남은 질문 수. 무제한이면 null.
  int? get remainingToday =>
      dailyLimit == null ? null : (dailyLimit! - usedToday).clamp(0, dailyLimit!);

  factory UsageInfo.fromJson(Map<String, dynamic> j) => UsageInfo(
        plan: j['plan'] as String,
        planName: j['plan_name'] as String? ?? j['plan'] as String,
        usedToday: j['used_today'] as int,
        dailyLimit: j['daily_limit'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'plan': plan,
        'plan_name': planName,
        'used_today': usedToday,
        'daily_limit': dailyLimit,
      };
}

class AskResponse {
  final String persona;
  final String personaName;
  final String question;
  final String answer;

  /// 근거 구절을 찾았는지. false 면 "다룬 적 없다"는 두 문장 답변이다.
  final bool grounded;

  /// 자해·자살 위기로 판단돼 앞에 상담전화 안내가 붙었는지. UI 는 이 경우 sources 를 기대하면 안 된다 (비어 있다).
  final bool safety;

  /// 말투 규칙 위반으로 다시 생성한 횟수. 디버그 표시용.
  final int retries;
  final List<GlossaryItem> glossary;
  final List<Source> sources;

  /// 요금제·오늘 사용량. 옛 서버는 보내지 않으므로 null 일 수 있다.
  final UsageInfo? usage;

  const AskResponse({
    required this.persona,
    required this.personaName,
    required this.question,
    required this.answer,
    required this.grounded,
    required this.safety,
    required this.retries,
    required this.glossary,
    required this.sources,
    this.usage,
  });

  factory AskResponse.fromJson(Map<String, dynamic> j) => AskResponse(
        persona: j['persona'] as String,
        personaName: j['persona_name'] as String,
        question: j['question'] as String,
        answer: j['answer'] as String,
        grounded: j['grounded'] as bool,
        safety: j['safety'] as bool? ?? false,
        retries: j['retries'] as int? ?? 0,
        glossary: (j['glossary'] as List<dynamic>? ?? const [])
            .map((e) => GlossaryItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        sources: (j['sources'] as List<dynamic>? ?? const [])
            .map((e) => Source.fromJson(e as Map<String, dynamic>))
            .toList(),
        usage: j['usage'] == null
            ? null
            : UsageInfo.fromJson(j['usage'] as Map<String, dynamic>),
      );

  /// 서버 응답과 같은 꼴 — 저장한 것을 fromJson 으로 그대로 되읽는다
  Map<String, dynamic> toJson() => {
        'persona': persona,
        'persona_name': personaName,
        'question': question,
        'answer': answer,
        'grounded': grounded,
        'safety': safety,
        'retries': retries,
        'glossary': glossary.map((g) => g.toJson()).toList(),
        'sources': sources.map((s) => s.toJson()).toList(),
        'usage': usage?.toJson(),
      };
}

class HealthResponse {
  final String status;
  final String llmProvider;
  final String llmModel;

  const HealthResponse({
    required this.status,
    required this.llmProvider,
    required this.llmModel,
  });

  factory HealthResponse.fromJson(Map<String, dynamic> j) => HealthResponse(
        status: j['status'] as String,
        llmProvider: j['llm_provider'] as String,
        llmModel: j['llm_model'] as String,
      );
}

/// GET /me — 요청한 사용자와 개발자 여부. 설정 화면이 신고 내역 메뉴를 보일지 정한다 (2026-10-12).
class MeInfo {
  final String userId;
  final bool admin;

  const MeInfo({required this.userId, required this.admin});

  factory MeInfo.fromJson(Map<String, dynamic> j) =>
      MeInfo(userId: j['user_id'] as String, admin: j['admin'] as bool? ?? false);
}

/// 대화 신고 한 건 (GET /reports — 개발자만). 신고한 질문·답이 함께 온다 (2026-10-12).
class ReportItem {
  final int id;
  final DateTime createdAt;
  final String userId;
  final String persona;
  final String reason;
  final String? detail; // "기타" 직접 입력
  final String question;
  final String answer;

  const ReportItem({
    required this.id,
    required this.createdAt,
    required this.userId,
    required this.persona,
    required this.reason,
    required this.detail,
    required this.question,
    required this.answer,
  });

  factory ReportItem.fromJson(Map<String, dynamic> j) => ReportItem(
        id: j['id'] as int,
        createdAt: DateTime.parse(j['created_at'] as String),
        userId: j['user_id'] as String,
        persona: j['persona'] as String,
        reason: j['reason'] as String,
        detail: j['detail'] as String?,
        question: j['question'] as String,
        answer: j['answer'] as String,
      );
}
