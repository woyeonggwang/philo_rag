/// 서버 주소 설정. 환경마다 주소가 다르므로(CLAUDE.md 13절) 앱 안에서 바꾸고 기기에 저장한다.
///
///   Android 에뮬레이터  http://10.0.2.2:8000   (에뮬레이터에서 PC 의 localhost)
///   실기기 (같은 Wi-Fi)  http://192.168.0.10:8000
///   Windows 데스크톱     http://localhost:8000
///
/// 사용자 ID 도 여기서 만든다. 로그인이 없어서(CLAUDE.md 13절) 처음 실행할 때 무작위 ID 를 만들어 저장하고,
/// 서버는 이 ID 로 요금제 하루 한도를 센다 (backend/app/plans.py). 앱을 지우면 ID 도 사라진다.
library;

import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore extends ChangeNotifier {
  static const _keyBaseUrl = 'base_url';
  static const _keyUserId = 'user_id';
  static const _keyWelcomeSeen = 'welcome_seen';

  /// 플랫폼별 기본값. 저장된 값이 없을 때만 쓴다.
  static String get defaultBaseUrl {
    if (kIsWeb) return 'http://localhost:8000';
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  SharedPreferences? _prefs;
  String _baseUrl = defaultBaseUrl;

  String _userId = '';
  bool _welcomeSeen = false;

  /// 첫 실행 소개 화면을 이미 봤는지. 한 번 "시작하기"를 누르면 다음부터는 로그인 화면이 바로 뜬다.
  bool get welcomeSeen => _welcomeSeen;

  Future<void> markWelcomeSeen() async {
    _welcomeSeen = true;
    await _prefs?.setBool(_keyWelcomeSeen, true);
    notifyListeners();
  }

  String get baseUrl => _baseUrl;

  /// 이 기기의 사용자 ID (UUID v4 꼴). 서버에 X-User-Id 헤더로 보낸다. load() 뒤에 쓴다.
  String get userId => _userId;

  /// 앱 시작 때 한 번 부른다. 저장된 주소를 읽고, 사용자 ID 가 없으면 만든다.
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _baseUrl = _prefs!.getString(_keyBaseUrl) ?? defaultBaseUrl;
    _userId = _prefs!.getString(_keyUserId) ?? '';
    _welcomeSeen = _prefs!.getBool(_keyWelcomeSeen) ?? false;
    if (_userId.isEmpty) {
      _userId = newUserId();
      await _prefs!.setString(_keyUserId, _userId);
    }
    notifyListeners();
  }

  /// 무작위 UUID v4. 패키지를 더하지 않으려고 직접 만든다.
  @visibleForTesting
  static String newUserId([Random? random]) {
    final r = random ?? Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  /// 끝의 '/' 는 떼고, 스킴이 없으면 http:// 를 붙여 저장한다.
  Future<void> setBaseUrl(String url) async {
    var u = url.trim();
    if (u.isEmpty) u = defaultBaseUrl;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    _baseUrl = u;
    await _prefs?.setString(_keyBaseUrl, u);
    notifyListeners();
  }

  Future<void> resetBaseUrl() => setBaseUrl(defaultBaseUrl);
}
