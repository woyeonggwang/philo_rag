/// 대화 내용을 폰(기기)에 저장한다 (2026-10-10, CLAUDE.md 13절).
///
/// 페르소나마다 JSON 파일 하나: `(앱 전용 폴더)/chats/(persona).json`
///   Android  /data/user/0/com.philorag.philo_rag/files/chats/   (다른 앱은 못 읽는다)
///   Windows  %APPDATA%\com.philorag\philo_rag\chats\
/// 앱을 지우면 같이 지워진다. 서버로는 보내지 않는다 (서버는 여전히 stateless).
/// 위기 상담 안내가 나간 대화도 저장한다 (사용자 결정).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'chat.dart';

class ChatStorage {
  /// 저장 폴더를 돌려주는 함수. 테스트에서는 임시 폴더를 넣는다.
  final Future<Directory> Function() _dir;

  ChatStorage({Future<Directory> Function()? directory})
      : _dir = directory ??
            (() async => Directory(
                '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}chats'));

  Future<File> _file(String persona) async {
    final d = await _dir();
    return File('${d.path}${Platform.pathSeparator}$persona.json');
  }

  /// 저장된 모든 페르소나의 대화. 파일이 깨졌으면 그 페르소나만 건너뛴다 (앱이 죽지 않게).
  Future<Map<String, List<ChatMessage>>> loadAll() async {
    final d = await _dir();
    final out = <String, List<ChatMessage>>{};
    if (!await d.exists()) return out;
    await for (final f in d.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      final name = f.uri.pathSegments.last;
      final persona = name.substring(0, name.length - '.json'.length);
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        out[persona] = (j['messages'] as List<dynamic>)
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        debugPrint('대화 파일을 읽지 못해 건너뜀: ${f.path} ($e)');
      }
    }
    return out;
  }

  /// 한 페르소나의 대화 전체를 덮어쓴다. 임시 파일에 쓰고 바꿔치기해서, 쓰는 도중 앱이 꺼져도 파일이 반쯤 깨지지 않게 한다.
  Future<void> save(String persona, List<ChatMessage> messages) async {
    final f = await _file(persona);
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'version': 1,
      'messages': messages.map((m) => m.toJson()).toList(),
    }), flush: true);
    await tmp.rename(f.path);
  }

  Future<void> delete(String persona) async {
    final f = await _file(persona);
    if (await f.exists()) await f.delete();
  }
}
