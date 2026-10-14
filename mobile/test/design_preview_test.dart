// 실제 화면 위젯을 가짜 서버로 렌더링한다. 실제 API·신고·저장 없이 캡처한다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:philo_rag/api/client.dart';
import 'package:philo_rag/api/models.dart';
import 'package:philo_rag/state/auth.dart';
import 'package:philo_rag/state/chat.dart';
import 'package:philo_rag/state/settings.dart';
import 'package:philo_rag/ui/app_theme.dart';
import 'package:philo_rag/ui/brand_widgets.dart';
import 'package:philo_rag/ui/main_tabs.dart';
import 'package:philo_rag/ui/persona_grid_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'text_finders.dart';

class _NoAuth implements AuthBackend {
  @override
  bool get available => false;
  @override
  Stream<AppUser?> userChanges() => const Stream.empty();
  @override
  Future<String?> idToken() async => null;
  @override
  Future<void> signOut() async {}
  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<void> signInWithApple() async {}
  @override
  Future<void> signInWithEmail(String e, String p) async {}
  @override
  Future<void> signUpWithEmail(String e, String p) async {}
  @override
  Future<void> sendPasswordReset(String e) async {}
}

const _answer = '운명을 사랑한다는 것은 필연을 견디는 데 그치지 않고, 그것을 사랑하는 것이다.';
const _sources = [
  Source(
    chunkId: 'n#1',
    work: 'ECCE HOMO',
    workKo: '이 사람을 보라',
    ref: '2:10',
    title: null,
    score: .6,
  ),
  Source(
    chunkId: 'n#2',
    work: 'TWILIGHT',
    workKo: '우상의 황혼',
    ref: '1:8',
    title: null,
    score: .5,
  ),
  Source(
    chunkId: 'n#3',
    work: 'ZARATHUSTRA',
    workKo: '차라투스트라는 이렇게 말했다',
    ref: '3:1~3:12',
    title: null,
    score: .5,
  ),
];

http.Response _json(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json'},
);

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final (scale, width) in [(1.0, 390.0), (1.3, 390.0), (1.3, 320.0)]) {
      testWidgets('${brightness.name} $scale $width: 화면·메뉴·신고·시크릿 캡처 및 넘침 검사', (
        t,
      ) async {
        t.view.physicalSize = Size(width, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await (FontLoader('GowunBatang')
              ..addFont(rootBundle.load('assets/fonts/GowunBatang-Regular.ttf'))
              ..addFont(rootBundle.load('assets/fonts/GowunBatang-Bold.ttf')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        SharedPreferences.setMockInitialValues({
          'text_size': scale == 1.3 ? 'xlarge' : 'normal',
        });
        final settings = SettingsStore();
        await settings.load();
        final auth = AuthController(_NoAuth())..useWithoutLogin();
        Completer<void>? waiting;
        var posts = 0;
        PhiloRagClient client() => PhiloRagClient(
          'http://preview',
          httpClient: MockClient((req) async {
            switch (req.url.path) {
              case '/personas':
                return _json([
                  {
                    'key': 'nietzsche',
                    'name': '니체',
                    'blurb': '망치를 든 철학자.',
                    'enabled': true,
                  },
                  {
                    'key': 'jesus',
                    'name': '예수',
                    'blurb': '공관복음의 목소리.',
                    'enabled': true,
                  },
                  {
                    'key': 'buddha',
                    'name': '부처',
                    'blurb': '초기 경전의 목소리.',
                    'enabled': true,
                  },
                ]);
              case '/me':
                return _json({'user_id': 'preview', 'admin': true});
              case '/usage':
                return _json({
                  'plan': 'personal',
                  'plan_name': 'Personal',
                  'used_today': 2,
                  'daily_limit': 5,
                });
              case '/reports':
                if (req.method == 'POST') posts++;
                return _json([
                  {
                    'id': 1,
                    'created_at': '2026-10-14T12:00:00+09:00',
                    'user_id': 'preview',
                    'persona': 'nietzsche',
                    'reason': '사실과 다른 내용 (없는 인용·잘못된 출처)',
                    'detail': '출처를 확인해 주세요.',
                    'question': '운명을 사랑한다는 것은 무엇인가요?',
                    'answer': _answer,
                    'extra': null,
                  },
                ]);
              case '/ask':
                if (waiting != null) await waiting.future;
                final q = (jsonDecode(req.body) as Map)['question'] as String;
                final open = q == '원전 밖 질문', safety = q == '안전 안내 확인';
                return _json(
                  AskResponse(
                    persona: 'nietzsche',
                    personaName: '니체',
                    question: q,
                    answer: open
                        ? '이것은 내가 책에서 다룬 문제가 아니다.'
                        : safety
                        ? '안전 안내를 확인해 주세요.'
                        : _answer,
                    grounded: !open && !safety,
                    safety: safety,
                    retries: 0,
                    glossary: [],
                    sources: open || safety ? [] : _sources,
                  ).toJson(),
                );
            }
            throw StateError('예상하지 않은 요청: ${req.url}');
          }),
        );
        final chatClient = client();
        final chat = ChatController(chatClient);
        const boundaryKey = Key('design-preview');
        await t.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: brightness == Brightness.dark
                  ? AppTheme.dark
                  : AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: MainTabs(
                settings: settings,
                auth: auth,
                chat: chat,
                client: client,
              ),
            ),
          ),
        );

        Future<void> capture(String name) async {
          await t.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 180)),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: '$name $brightness $scale');
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(boundaryKey),
          );
          await t.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final suffix =
                '${scale == 1.3 ? '-xlarge' : ''}${width == 320 ? '-narrow' : ''}';
            final file = File(
              '../output/design-2026-10-14/$name-${brightness.name}$suffix.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        Future<void> ask(String question) async {
          await t.enterText(find.byKey(const Key('question')), question);
          await t.tap(find.byKey(const Key('send')));
          await t.pumpAndSettle();
        }

        Future<void> menu() async {
          await t.longPress(findText(_answer));
          await t.pumpAndSettle();
        }

        Future<void> cancel() async {
          await t.tap(findText('취소'));
          await t.pumpAndSettle();
        }

        await t.pumpAndSettle();
        await t.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await capture('persona-grid');
        final visuals = find.byType(PersonaVisual);
        expect(visuals, findsNWidgets(3));
        for (final visual in visuals.evaluate()) {
          final painted = find.descendant(
            of: find.byWidget(visual.widget),
            matching: find.byType(CustomPaint),
          );
          expect(painted, findsOneWidget, reason: '카드 이미지 로딩');
          expect(t.getSize(painted).width, greaterThan(100));
          expect(t.getSize(painted).height, greaterThan(100));
        }
        await t.tap(find.byKey(const ValueKey('persona-nietzsche')));
        await t.pumpAndSettle();
        await capture('chat-empty');
        waiting = Completer<void>();
        await ask('아모르파티란 무엇인가요?');
        expect(findText('니체가 생각하는 중…'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await capture('chat-waiting');
        waiting.complete();
        waiting = null;
        await t.pumpAndSettle();
        // 답의 근거는 기본으로 접혀 있다 (2026-10-14 사용자 요청으로 접기를 되살림) — 펼쳐서 찍는다
        expect(findText('답의 근거 ${_sources.length}곳'), findsOneWidget);
        await t.tap(find.byKey(const Key('sources-toggle')));
        await t.pumpAndSettle();
        expect(findText(_sources.first.label), findsOneWidget);
        expect(find.byType(PersonaPortrait), findsOneWidget);
        await capture('chat-sources');

        // 실제 말풍선의 글자색과 표면색으로 대비를 계산한다.
        for (final i in [0, 1]) {
          final msg = find.byKey(ValueKey('msg-$i'));
          final container = t.widget<Container>(
            find.descendant(of: msg, matching: find.byType(Container)).first,
          );
          final text = t.widget<Text>(
            find.descendant(
              of: msg,
              matching: i == 0 ? findText('아모르파티란 무엇인가요?') : findText(_answer),
            ),
          );
          expect(
            _contrast(
              (container.decoration! as BoxDecoration).color!,
              text.style!.color!,
            ),
            greaterThanOrEqualTo(4.5),
          );
        }
        await menu();
        await capture('chat-menu');
        await t.tap(find.byKey(const ValueKey('menu-delete')));
        await t.pumpAndSettle();
        await capture('confirm-delete');
        await cancel();
        await menu();
        await t.tap(find.byKey(const ValueKey('menu-report')));
        await t.pumpAndSettle();
        await capture('report-dialog');
        await t.ensureVisible(find.byKey(const Key('report-agree')));
        await t.pumpAndSettle();
        expect(
          t
              .widget<FilledButton>(find.byKey(const Key('report-send')))
              .onPressed,
          isNull,
        );
        await capture('report-consent');
        await cancel();
        await t.tap(find.byTooltip('이 대화 지우기'));
        await t.pumpAndSettle();
        await capture('confirm-clear');
        await cancel();

        await ask('원전 밖 질문');
        expect(findText('원전에서 직접 다루지 않은 질문'), findsOneWidget);
        await capture('chat-ungrounded');
        await ask('안전 안내 확인');
        final safetyBubble = find.byKey(const ValueKey('msg-5'));
        expect(
          find.descendant(
            of: safetyBubble,
            matching: findText('원전에서 직접 다루지 않은 질문'),
          ),
          findsNothing,
        );

        await t.tap(find.byKey(const Key('secret')));
        await t.pumpAndSettle();
        await capture('secret-empty');
        await ask('시크릿으로 생각을 나눕니다');
        await capture('secret-chat');
        await t.tap(find.byKey(const Key('secret')));
        await t.pumpAndSettle();
        await capture('confirm-secret-off');
        await cancel();
        await t.pageBack();
        await t.pumpAndSettle();
        expect(chat.isSecret('nietzsche'), isFalse);
        await t.tap(findText('설정'));
        await t.pumpAndSettle();
        await capture('settings');
        await t.scrollUntilVisible(
          find.byKey(const Key('reports')),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await t.pumpAndSettle();
        await capture('settings-account-usage');
        await t.tap(find.byKey(const Key('reports')));
        await t.pumpAndSettle();
        await capture('reports');
        await t.tap(find.byKey(const ValueKey('report-1')));
        await t.pumpAndSettle();
        await capture('reports-detail');
        expect(posts, 0);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        chat.dispose();
        chatClient.close();
        auth.dispose();
        settings.dispose();
      });
    }
  }
}
