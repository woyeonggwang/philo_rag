// 철학자 2열 바둑판 → 누르면 대화창 (ui/persona_grid_screen.dart, ui/chat_screen.dart). 서버는 MockClient.
// 실행: mobile 폴더에서  flutter test
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:philo_rag/api/client.dart';
import 'package:philo_rag/state/chat.dart';
import 'package:philo_rag/state/settings.dart';
import 'package:philo_rag/ui/chat_screen.dart';
import 'package:philo_rag/ui/persona_grid_screen.dart';
import 'package:philo_rag/ui/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'text_finders.dart';

const _personas = [
  {'key': 'nietzsche', 'name': '니체', 'blurb': '망치를 든 철학자.', 'enabled': true},
  {'key': 'jesus', 'name': '예수', 'blurb': '복음서의 목소리.', 'enabled': true},
  {'key': 'buddha', 'name': '부처', 'blurb': '초기 경전의 목소리.', 'enabled': true},
  {'key': 'hidden', 'name': '숨김', 'blurb': '', 'enabled': false},
];

http.Response _json(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
    headers: {'content-type': 'application/json'});

PhiloRagClient _server({int failFirst = 0}) {
  var calls = 0;
  return PhiloRagClient('http://x', httpClient: MockClient((req) async {
    if (req.url.path == '/personas') {
      calls++;
      if (calls <= failFirst) throw const SocketException('서버 켜지는 중');
      return _json(_personas);
    }
    final q = (jsonDecode(req.body) as Map)['question'];
    return _json({
      'persona': 'jesus', 'persona_name': '예수', 'question': q, 'answer': '보라, 염려하지 말라.',
      'grounded': true, 'safety': false, 'retries': 0, 'glossary': [], 'sources': [],
    });
  }));
}

Future<void> _pump(WidgetTester t, PhiloRagClient client) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsStore();
  await settings.load();
  await t.pumpWidget(RepaintBoundary(key: const Key('grid-preview'), child: MaterialApp(
    theme: AppTheme.dark,
    home: PersonaGridScreen(
      settings: settings,
      chat: ChatController(client), // 저장 없음
      client: () => client,
      retryDelay: const Duration(milliseconds: 10),
    ),
  )));
}

void main() {
  testWidgets('테마를 바꾸면 기존 인물 위젯이 전용 이미지로 전환된다', (t) async {
    Future<void> showTheme(ThemeData theme) async {
      await t.pumpWidget(MaterialApp(
        theme: theme,
        home: const SizedBox(width: 200, height: 300, child: PersonaVisual(name: '니체')),
      ));
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await t.pumpAndSettle();
    }
    dynamic painter() => t.widget<CustomPaint>(find.descendant(
      of: find.byType(PersonaVisual), matching: find.byType(CustomPaint),
    )).painter;
    await showTheme(AppTheme.dark);
    final ui.Image darkImage = painter().image;
    await showTheme(AppTheme.light);
    final ui.Image lightImage = painter().image;
    expect(identical(darkImage, lightImage), isFalse);
    expect(painter().brightness, Brightness.light);
    await showTheme(AppTheme.dark);
    expect(identical(painter().image, darkImage), isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('철학자가 2열 바둑판으로 뜬다 (서버 주소·연결 줄 없음, 꺼진 철학자 빼고)', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await _pump(t, _server());
    await t.pumpAndSettle();
    final grid = t.widget<GridView>(find.byType(GridView));
    expect((grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount, 2);
    expect(find.byKey(const ValueKey('persona-nietzsche')), findsOneWidget);
    expect(find.byKey(const ValueKey('persona-jesus')), findsOneWidget);
    expect(find.byKey(const ValueKey('persona-buddha')), findsOneWidget);
    expect(find.byType(PersonaVisual), findsNWidgets(3));
    expect(findText('니체'), findsNothing);
    expect(findText('예수'), findsNothing);
    expect(findText('부처'), findsNothing);
    expect(findText('쉼표,'), findsNothing);
    expect(findText('숨김'), findsNothing);
    expect(findText('연결'), findsNothing);
    expect(find.byType(ChatScreen), findsNothing); // 대화창은 아직 안 열렸다
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await t.pumpAndSettle();
    final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(const Key('grid-preview')));
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('../output/illustration-samples/persona-grid-v2-preview.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });

  testWidgets('철학자를 누르면 그 철학자의 대화창이 열리고, 질문하면 답이 붙는다', (t) async {
    await _pump(t, _server());
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('persona-jesus')));
    await t.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(findText('예수에게 물어보세요.'), findsOneWidget);

    await t.enterText(find.byKey(const Key('question')), '돈 걱정으로 잠이 안 옵니다');
    await t.tap(find.byKey(const Key('send')));
    await t.pumpAndSettle();
    expect(findText('돈 걱정으로 잠이 안 옵니다'), findsOneWidget);
    expect(findText('보라, 염려하지 말라.'), findsOneWidget);

    await t.pageBack(); // 뒤로 가면 바둑판
    await t.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
  });

  testWidgets('서버가 켜지는 중이면 기다렸다 다시 묻는다 (연결 버튼 대신)', (t) async {
    await _pump(t, _server(failFirst: 2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('persona-jesus')), findsOneWidget);
  });
}
