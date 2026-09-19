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

/// 답변의 근거 구절. 본문은 오지 않고 위치만 온다.
class Source {
  final String work; // "THE DHAMMAPADA" 같은 작품명 (영어)
  final String ref; // "17:221~17:234" 또는 "1:1"
  final String? title; // 구분(장·경) 제목
  final double score; // 코사인 유사도 0~1

  const Source({
    required this.work,
    required this.ref,
    required this.title,
    required this.score,
  });

  factory Source.fromJson(Map<String, dynamic> j) => Source(
        work: j['work'] as String,
        ref: j['ref'] as String,
        title: j['title'] as String?,
        score: (j['score'] as num).toDouble(),
      );
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
      );
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
