/// 소개 탭의 철학자 소개 · 사상 요약 · 서적 목록 (2026-10-12). 앱에 넣어 두는 고정 글 — 서버를 부르지 않는다.
///
/// 원칙
/// - 사상 요약은 널리 합의된 설명만 쓴다. 해석이 갈리는 주장은 넣지 않는다.
/// - 성경 장절은 코퍼스(backend/data/corpus)와 대조해 확인했다.
/// - [Book.inApp] 은 이 앱이 답할 때 실제로 검색하는 원전이다 (CLAUDE.md 4절). 목록을 바꾸면 코퍼스와 맞는지 볼 것.
/// - 출판사·번역자처럼 확인하지 않은 서지 정보는 넣지 않는다.
library;

class KeyIdea {
  final String title;
  final String body;
  const KeyIdea(this.title, this.body);
}

class Book {
  final String title; // 한국어 제목
  final String original; // 원제 또는 원전 표기
  final String year; // 출간 연도 또는 성립 시기
  final String? note;

  /// 이 앱이 답할 때 근거로 검색하는 원전인지
  final bool inApp;

  const Book(
    this.title,
    this.original,
    this.year, {
    this.note,
    this.inApp = false,
  });
}

class PersonaProfile {
  final String key; // 서버 페르소나 키 ("nietzsche" | "jesus" | "buddha")
  final String name;
  final String lifespan; // "1844–1900 · 독일"
  final String tagline; // 슬라이드에 보일 한 줄 소개
  final String summary; // 사상 응축 (한 문단)
  final List<KeyIdea> ideas;
  final String booksIntro; // 서적 목록 위 한두 줄
  final List<Book> books;

  const PersonaProfile({
    required this.key,
    required this.name,
    required this.lifespan,
    required this.tagline,
    required this.summary,
    required this.ideas,
    required this.booksIntro,
    required this.books,
  });
}

const personaProfiles = <PersonaProfile>[
  PersonaProfile(
    key: 'nietzsche',
    name: '니체',
    lifespan: '프리드리히 니체 · 1844–1900 · 독일',
    tagline: '망치를 든 철학자. 낡은 가치를 의심하고 삶을 끝까지 긍정하라고 말한다.',
    summary:
        '니체는 서양을 오래 떠받쳐 온 가치들 — 기독교 도덕, 절대적 진리, 이 세상 너머의 "참된 세계" — 가 힘을 잃었다고 보았다. '
        '"신은 죽었다"는 말은 그 상실을 가리킨다. 그는 그 빈자리를 허무로 남겨 두지 말고, 사람이 스스로 가치를 세워 '
        '자기 삶을 긍정하라고 요구했다.',
    ideas: [
      KeyIdea('신의 죽음', '믿음의 토대가 무너졌다는 진단이다. 니체는 그 뒤에 오는 허무주의를 넘어서야 할 과제로 보았다.'),
      KeyIdea(
        '가치의 재평가',
        '선과 악 같은 도덕이 어디서 생겨났는지 캐묻는다. 『도덕의 계보』에서 약자의 원한(르상티망)이 만든 "노예 도덕"을 비판했다.',
      ),
      KeyIdea('힘에의 의지', '살아 있는 것은 그저 살아남는 데 그치지 않고, 스스로를 넘어서 더 커지려 한다.'),
      KeyIdea('초인', '낡은 가치를 넘어 스스로 가치를 만드는 인간. 『차라투스트라는 이렇게 말했다』의 중심 형상이다.'),
      KeyIdea(
        '영원회귀와 운명애',
        '지금의 삶이 똑같이 끝없이 되풀이된다 해도 긍정할 수 있는가를 묻는다. "운명을 사랑하라(amor fati)."',
      ),
    ],
    booksIntro: '니체가 직접 쓰고 펴낸 책들이다. ● 표시는 이 앱이 답할 때 근거로 찾는 책이다. 그가 출간하지 않은 노트를 엮은 『권력에의 의지』는 넣지 않았다.',
    books: [
      Book('비극의 탄생', 'Die Geburt der Tragödie', '1872'),
      Book('반시대적 고찰', 'Unzeitgemäße Betrachtungen', '1873–1876'),
      Book('인간적인, 너무나 인간적인', 'Menschliches, Allzumenschliches', '1878–1880'),
      Book('아침놀', 'Morgenröte', '1881'),
      Book('즐거운 학문', 'Die fröhliche Wissenschaft', '1882 · 증보 1887'),
      Book(
        '차라투스트라는 이렇게 말했다',
        'Also sprach Zarathustra',
        '1883–1885',
        inApp: true,
      ),
      Book('선악의 저편', 'Jenseits von Gut und Böse', '1886', inApp: true),
      Book('도덕의 계보', 'Zur Genealogie der Moral', '1887', inApp: true),
      Book('바그너의 경우', 'Der Fall Wagner', '1888'),
      Book('우상의 황혼', 'Götzen-Dämmerung', '1889', inApp: true),
      Book('안티크리스트', 'Der Antichrist', '1888 집필 · 1895 출간', inApp: true),
      Book('이 사람을 보라', 'Ecce Homo', '1888 집필 · 1908 출간', inApp: true),
    ],
  ),
  PersonaProfile(
    key: 'jesus',
    name: '예수',
    // 나사렛은 성씨가 아니고 예수에게는 성씨가 없다. 출생지는 유대 베들레헴(마 2:1),
    // 나사렛은 갈릴리 땅이라(눅 2:4) "유대 나사렛"은 틀린다 (사용자 지적 2026-10-12)
    lifespan: '예수 그리스도 · 기원전 4년경–기원후 30년경 · 유대 베들레헴',
    tagline: '공관복음의 목소리. 하나님 나라와 사랑, 용서를 비유로 전한다.',
    summary:
        '마태·마가·누가 세 복음서에 기록된 예수의 가르침은 "때가 찼고 하나님의 나라가 가까이 왔으니 회개하고 복음을 믿으라"(막 1:15)는 '
        '선포에서 시작한다. 그는 율법의 핵심을 하나님 사랑과 이웃 사랑으로 요약했고, 원수까지 사랑하고 끝없이 용서하라고 가르쳤다. '
        '가난한 이와 병든 이, 죄인이라 불리던 이들 곁에 섰고, 일상의 장면을 빌린 비유로 가르쳤다.',
    ideas: [
      KeyIdea('하나님 나라', '하나님의 다스림이 가까이 왔다는 선포. 회개하고 믿으라는 부름이 함께한다 (막 1:15).'),
      KeyIdea(
        '가장 큰 계명',
        '마음과 목숨과 뜻을 다해 하나님을 사랑하고, 이웃을 네 몸같이 사랑하라 (마 22:37–39, 막 12:30–31).',
      ),
      KeyIdea(
        '원수 사랑과 용서',
        '원수를 사랑하고 박해하는 자를 위해 기도하라 (마 5:44). 일곱 번이 아니라 일흔 번씩 일곱 번이라도 용서하라 (마 18:22).',
      ),
      KeyIdea('지극히 작은 자', '가장 작은 이에게 한 것이 곧 내게 한 것이다 (마 25:40).'),
      KeyIdea('염려하지 말라', '공중의 새와 들의 백합을 보라. 내일 일은 내일이 염려할 것이다 (마 6:25–34).'),
      KeyIdea(
        '비유',
        '씨 뿌리는 자 (마 13:3), 선한 사마리아인 (눅 10:30–37), 돌아온 아들 (눅 15:11–32) 처럼 일상의 이야기로 가르쳤다.',
      ),
    ],
    booksIntro: '예수는 직접 글을 남기지 않았다. 그의 말과 행적은 제자들과 초대 교회가 전한 복음서에 기록돼 있다. ● 표시는 이 앱이 답할 때 근거로 찾는 책이다 (킹 제임스 영어 성경).',
    books: [
      Book('마태복음', 'The Gospel According to Matthew', '1세기 후반', inApp: true),
      Book(
        '마가복음',
        'The Gospel According to Mark',
        '1세기 후반',
        note: '네 복음서 가운데 대체로 가장 이른 것으로 본다',
        inApp: true,
      ),
      Book('누가복음', 'The Gospel According to Luke', '1세기 후반', inApp: true),
      Book(
        '요한복음',
        'The Gospel According to John',
        '1세기 말',
        note: '앞의 세 복음서와 문체·화법이 달라 이 앱의 근거에서는 뺐다',
      ),
    ],
  ),
  PersonaProfile(
    key: 'buddha',
    name: '부처',
    lifespan: '고따마 붓다 · 기원전 6–5세기경 · 인도',
    tagline: '깨달은 사람. 괴로움의 원인과 그것을 끝내는 길을 가리킨다.',
    summary:
        '붓다는 삶에 괴로움이 있다는 사실에서 출발했다. 괴로움에는 원인이 있고 — 그치지 않는 목마름, 곧 갈애 — 그 원인이 사라지면 '
        '괴로움도 끝나며, 그 끝에 이르는 길이 있다고 가르쳤다. 이것이 네 가지 성스러운 진리(사성제)다. 그는 쾌락과 고행이라는 두 극단을 '
        '피한 중도를 걸으라 했고, 모든 것은 변하며 고정된 "나"는 없다고 보았다. 자신의 가르침조차 그냥 믿지 말고 스스로 살펴 확인하라고 했다.',
    ideas: [
      KeyIdea(
        '사성제',
        '괴로움이 있다 · 괴로움에는 원인(갈애)이 있다 · 괴로움은 끝날 수 있다 · 끝에 이르는 길이 있다.',
      ),
      KeyIdea('팔정도', '그 길의 여덟 갈래 — 바른 견해·사유·말·행위·생계·정진·마음챙김·삼매.'),
      KeyIdea('중도', '감각적 쾌락에 빠지는 것과 몸을 괴롭히는 고행, 두 극단을 모두 피한다 (초전법륜경).'),
      KeyIdea('무상과 무아', '조건 지어진 모든 것은 변하고 사라진다. 변하지 않는 "나"라 할 만한 실체는 없다.'),
      KeyIdea('연기', '모든 것은 조건에 기대어 일어나고, 조건이 사라지면 사라진다.'),
      KeyIdea(
        '스스로 확인하라',
        '전해 들은 말이나 경전, 스승의 권위만으로 믿지 말고, 해로움과 이로움을 스스로 살펴 받아들이라 (깔라마경).',
      ),
    ],
    booksIntro: '붓다도 직접 글을 쓰지 않았다. 제자들이 외워 전한 가르침이 빠알리어 경전(니까야)으로 남았다. ● 표시는 이 앱이 답할 때 근거로 찾는 경전이다 (비구 수자또의 영어 번역).',
    books: [
      Book('법구경', 'Dhammapada', '소부 니까야', note: '짧은 게송 423편', inApp: true),
      Book(
        '숫타니파타',
        'Sutta Nipāta',
        '소부 니까야',
        note: '가장 오래된 층의 경전으로 꼽힌다. 자애경이 들어 있다',
        inApp: true,
      ),
      Book(
        '우다나',
        'Udāna',
        '소부 니까야',
        note: '감흥어 — 붓다가 감흥에 겨워 읊은 말',
        inApp: true,
      ),
      Book(
        '여시어경',
        'Itivuttaka',
        '소부 니까야',
        note: '"세존께서 이렇게 말씀하셨다고 나는 들었다"로 시작하는 짧은 경들',
        inApp: true,
      ),
      Book(
        '초전법륜경',
        'Dhammacakkappavattana Sutta',
        '상윳따 니까야 56.11',
        note: '깨달은 뒤 처음 한 설법. 사성제와 중도',
        inApp: true,
      ),
      Book(
        '염처경',
        'Satipaṭṭhāna Sutta',
        '맛지마 니까야 10',
        note: '마음챙김 수행의 네 가지 토대',
        inApp: true,
      ),
      Book(
        '깔라마경',
        'Kālāma Sutta',
        '앙굿따라 니까야 3.65',
        note: '무엇을 믿을 것인가',
        inApp: true,
      ),
      Book(
        '대반열반경',
        'Mahāparinibbāna Sutta',
        '디가 니까야 16',
        note: '붓다의 마지막 여정과 마지막 말',
        inApp: true,
      ),
      Book(
        '그 밖의 니까야',
        'Dīgha · Majjhima · Saṃyutta · Aṅguttara Nikāya',
        '경장',
        note: '긴·중간·주제별·숫자별 모음. 이 앱에는 위의 일부만 들어 있다',
      ),
    ],
  ),
];

PersonaProfile? profileFor(String key) {
  for (final p in personaProfiles) {
    if (p.key == key) return p;
  }
  return null;
}
