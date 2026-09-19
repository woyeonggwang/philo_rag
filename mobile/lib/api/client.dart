/// 백엔드 HTTP 클라이언트. 앱에서 서버를 부르는 곳은 여기뿐이다.
/// UI(lib/ui/) 는 이 파일의 함수만 쓰고 http 패키지를 직접 쓰지 않는다 (CLAUDE.md 13절).
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

/// 서버가 돌려준 오류. 백엔드는 LLM 오류를 502 + 원문 메시지로 넘기므로(9절) 그 메시지를 그대로 보여줄 수 있다.
class ApiException implements Exception {
  final int? statusCode; // null 이면 연결 자체가 안 된 것 (서버 꺼짐·주소 오류·방화벽)
  final String message;

  const ApiException(this.message, {this.statusCode});

  bool get isConnectionError => statusCode == null;

  @override
  String toString() =>
      statusCode == null ? '연결 실패: $message' : 'HTTP $statusCode: $message';
}

class PhiloRagClient {
  /// 예: http://10.0.2.2:8000 (끝에 / 없음). SettingsStore 가 준다.
  final String baseUrl;

  /// LLM 응답이 10~35초 걸린다 (CLAUDE.md 12절). 재생성이 겹치면 더 길어질 수 있어 넉넉히 잡는다.
  final Duration askTimeout;
  final http.Client _http;

  PhiloRagClient(
    this.baseUrl, {
    this.askTimeout = const Duration(seconds: 90),
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// GET /health — 서버·LLM 프리셋 확인. 설정 화면의 "연결 확인" 버튼용.
  Future<HealthResponse> health() async {
    final j = await _getJson('/health', const Duration(seconds: 5));
    return HealthResponse.fromJson(j as Map<String, dynamic>);
  }

  /// GET /personas — 선택 화면에 보일 목록. enabled=false 인 것도 오므로 UI 가 걸러 보여준다.
  Future<List<Persona>> personas() async {
    final j = await _getJson('/personas', const Duration(seconds: 10));
    return (j as List<dynamic>)
        .map((e) => Persona.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /ask — 앱이 보내는 것은 {persona, question} 뿐이다 (CLAUDE.md 2.1).
  Future<AskResponse> ask(String persona, String question) async {
    final body = jsonEncode({'persona': persona, 'question': question});
    final http.Response res;
    try {
      res = await _http
          .post(_uri('/ask'),
              headers: const {'Content-Type': 'application/json'}, body: body)
          .timeout(askTimeout);
    } on SocketException catch (e) {
      throw ApiException(e.message);
    } on HttpException catch (e) {
      throw ApiException(e.message);
    } on Exception catch (e) {
      // TimeoutException 등
      throw ApiException(e.toString());
    }
    return AskResponse.fromJson(_decode(res) as Map<String, dynamic>);
  }

  Future<dynamic> _getJson(String path, Duration timeout) async {
    final http.Response res;
    try {
      res = await _http.get(_uri(path)).timeout(timeout);
    } on SocketException catch (e) {
      throw ApiException(e.message);
    } on HttpException catch (e) {
      throw ApiException(e.message);
    } on Exception catch (e) {
      throw ApiException(e.toString());
    }
    return _decode(res);
  }

  /// 한글 응답이므로 bodyBytes 를 utf8 로 직접 푼다. res.body 는 charset 헤더가 없으면 latin1 로 깨질 수 있다.
  dynamic _decode(http.Response res) {
    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(text);
    }
    // FastAPI 오류는 {"detail": "..."} 꼴. 422 는 detail 이 리스트다.
    String msg = text;
    try {
      final j = jsonDecode(text);
      if (j is Map && j['detail'] != null) {
        msg = j['detail'] is String ? j['detail'] as String : jsonEncode(j['detail']);
      }
    } catch (_) {}
    throw ApiException(msg, statusCode: res.statusCode);
  }

  void close() => _http.close();
}
