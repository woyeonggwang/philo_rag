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

  /// 오늘 요금제 한도를 다 썼다 (429). message 에 "오늘 사용할 수 있는 질문 5건을 모두 썼습니다…" 가 들어 있다.
  bool get isQuotaExceeded => statusCode == 429;

  /// 로그인이 필요하거나 로그인 정보가 만료됐다 (401). 다시 로그인하게 한다.
  bool get isAuthError => statusCode == 401;

  @override
  String toString() {
    if (statusCode == null) return '연결 실패: $message';
    if (isQuotaExceeded) return message; // 사용자에게 그대로 보여줄 문장이다
    return 'HTTP $statusCode: $message';
  }
}

class PhiloRagClient {
  /// 예: http://10.0.2.2:8000 (끝에 / 없음). SettingsStore 가 준다.
  final String baseUrl;

  /// 기기별 사용자 ID (SettingsStore.userId). 로그인 토큰이 없을 때 서버가 요금제 한도를 이 ID 로 센다.
  final String userId;

  /// 로그인한 사용자의 Firebase ID 토큰을 돌려주는 함수 (AuthController.idToken). 있으면
  /// `Authorization: Bearer` 로 보내고, 서버는 계정 기준으로 한도를 센다 (backend/app/auth.py).
  final Future<String?> Function()? idToken;

  /// LLM 응답이 10~35초 걸린다 (CLAUDE.md 12절). 재생성이 겹치면 더 길어질 수 있어 넉넉히 잡는다.
  final Duration askTimeout;
  final http.Client _http;

  PhiloRagClient(
    this.baseUrl, {
    this.userId = '',
    this.idToken,
    this.askTimeout = const Duration(seconds: 90),
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, String>> _headers() async {
    final token = idToken == null ? null : await idToken!();
    return {
      if (userId.isNotEmpty) 'X-User-Id': userId,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

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
    final j = await _postJson(
        '/ask', {'persona': persona, 'question': question}, askTimeout);
    return AskResponse.fromJson(j as Map<String, dynamic>);
  }

  Future<dynamic> _postJson(
      String path, Map<String, dynamic> body, Duration timeout) async {
    final http.Response res;
    try {
      res = await _http
          .post(_uri(path),
              headers: {'Content-Type': 'application/json', ...await _headers()},
              body: jsonEncode(body))
          .timeout(timeout);
    } on SocketException catch (e) {
      throw ApiException(e.message);
    } on HttpException catch (e) {
      throw ApiException(e.message);
    } on Exception catch (e) {
      // TimeoutException 등
      throw ApiException(e.toString());
    }
    return _decode(res);
  }

  Future<dynamic> _getJson(String path, Duration timeout) async {
    final http.Response res;
    try {
      res = await _http.get(_uri(path), headers: await _headers()).timeout(timeout);
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
