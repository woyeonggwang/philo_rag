import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philo_rag/ui/app_theme.dart';
import 'package:philo_rag/ui/welcome_screen.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('초기 화면 $brightness: 글쓰기 완료 및 20초 반복에서 렌더링 오류 없음', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader('GowunBatang')
            ..addFont(rootBundle.load('assets/fonts/GowunBatang-Regular.ttf')))
          .load();
      const key = Key('preview');
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme:
                (brightness == Brightness.dark ? AppTheme.dark : AppTheme.light)
                    .copyWith(
                      textTheme:
                          (brightness == Brightness.dark
                                  ? AppTheme.dark
                                  : AppTheme.light)
                              .textTheme
                              .apply(fontFamily: 'GowunBatang'),
                    ),
            debugShowCheckedModeBanner: false,
            home: WelcomeScreen(onStart: () {}),
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          '../output/design-2026-10-14/welcome-${brightness.name}.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pump(const Duration(seconds: 14));
      await tester.pump(const Duration(milliseconds: 1600));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
