/// 로그인 뒤의 기본 화면 — 아래 탭 세 개 (2026-10-12, 사용자 결정).
///   대화   철학자 바둑판 (persona_grid_screen.dart) → 누르면 대화창
///   소개   철학자 슬라이드 → 누르면 사상·서적 페이지 (persona_intro_screen.dart)
///   설정   테마·글씨 크기·계정·남은 사용량·결제(준비 중) (settings_screen.dart)
/// 대화창과 소개 상세 페이지는 탭을 덮는 전체 화면으로 열린다 — 대화 중에는 탭이 보이지 않는다.
/// 탭 화면은 IndexedStack 으로 살려 두어, 탭을 오가도 스크롤·슬라이드 위치가 남는다.
library;

import 'package:flutter/material.dart';

import '../api/client.dart';
import '../state/auth.dart';
import '../state/chat.dart';
import '../state/settings.dart';
import 'persona_grid_screen.dart';
import 'persona_intro_screen.dart';
import 'settings_screen.dart';

class MainTabs extends StatefulWidget {
  final SettingsStore settings;
  final AuthController auth;
  final ChatController chat;
  final PhiloRagClient Function() client;

  const MainTabs({
    super.key,
    required this.settings,
    required this.auth,
    required this.chat,
    required this.client,
  });

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> {
  int _index = 0;
  int _settingsVisits = 0; // 설정 탭을 열 때마다 남은 사용량을 다시 읽게 한다

  void _select(int i) {
    setState(() {
      _index = i;
      if (i == 2) _settingsVisits++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          PersonaGridScreen(
            settings: widget.settings,
            chat: widget.chat,
            auth: widget.auth,
            client: widget.client,
          ),
          const PersonaIntroScreen(),
          Theme(
            data: Theme.of(context),
            child: SettingsScreen(
              settings: widget.settings,
              auth: widget.auth,
              client: widget.client,
              refreshToken: _settingsVisits,
            ),
          ),
        ],
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.forum_outlined),
              selectedIcon: Icon(Icons.forum),
              label: '대화',
            ),
            NavigationDestination(
              icon: Icon(Icons.auto_stories_outlined),
              selectedIcon: Icon(Icons.auto_stories),
              label: '소개',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '설정',
            ),
          ],
        ),
      ),
    );
  }
}
