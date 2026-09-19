/// 서버 주소 설정. 환경마다 주소가 다르므로(CLAUDE.md 13절) 앱 안에서 바꾸고 기기에 저장한다.
///
///   Android 에뮬레이터  http://10.0.2.2:8000   (에뮬레이터에서 PC 의 localhost)
///   실기기 (같은 Wi-Fi)  http://192.168.0.10:8000
///   Windows 데스크톱     http://localhost:8000
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore extends ChangeNotifier {
  static const _keyBaseUrl = 'base_url';

  /// 플랫폼별 기본값. 저장된 값이 없을 때만 쓴다.
  static String get defaultBaseUrl {
    if (kIsWeb) return 'http://localhost:8000';
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  SharedPreferences? _prefs;
  String _baseUrl = defaultBaseUrl;

  String get baseUrl => _baseUrl;

  /// 앱 시작 때 한 번 부른다. 저장된 주소를 읽어 온다.
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _baseUrl = _prefs!.getString(_keyBaseUrl) ?? defaultBaseUrl;
    notifyListeners();
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
