import 'package:flutter/material.dart' hide Text;

import 'app_theme.dart';
import 'keep_words.dart';
import 'persona_grid_screen.dart' show PersonaVisual;

/// 기존 먹 일러스트에서 얼굴만 보여 주는 작은 초상.
class PersonaPortrait extends StatelessWidget {
  final String name;
  final double size;
  const PersonaPortrait({super.key, required this.name, this.size = 40});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.controlRadius),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: PersonaVisual(name: name, faceOnly: true),
    ),
  );
}

/// 설정의 제목과 표면. 간격·모서리·색은 공통 테마를 따른다.
class SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const SettingsGroup({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppTheme.sectionGap),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    ),
  );
}
