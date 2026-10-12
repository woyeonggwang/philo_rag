import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:philo_rag/ui/app_theme.dart';
import 'package:philo_rag/ui/ink_portrait_background.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness: 세 인물이 순서대로 퍼지고 동일한 모양을 역순으로 거둔다', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        home: const InkPortraitBackground(),
      ));
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await t.pump();
      final dynamic painter = t.widget<CustomPaint>(find.descendant(
        of: find.byType(InkPortraitBackground), matching: find.byType(CustomPaint),
      )).painter;
      final controller = painter.cycle as AnimationController;
      controller.stop();
      Future<Uint8List> render(double value) async {
        controller.value = value;
        return (await t.runAsync(() async {
          final recorder = ui.PictureRecorder();
          painter.paint(Canvas(recorder), const Size(120, 240));
          final picture = recorder.endRecording();
          final image = await picture.toImage(120, 240);
          final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          final pixels = Uint8List.fromList(data!.buffer.asUint8List());
          image.dispose();
          picture.dispose();
          return pixels;
        }))!;
      }
      for (var person = 0; person < 3; person++) {
        Uint8List? previous;
        for (final phase in [0.02, 0.04, 0.08, 0.12, 0.18, 0.26, 0.36, 0.44, 0.5]) {
            final pixels = await render((person + phase) / 3);
            final before = previous;
            if (before != null) {
              var receding = 0;
              for (var i = 3; i < pixels.length; i += 4) {
                if (pixels[i] + 2 < before[i]) receding++;
              }
              expect(receding, 0, reason: '인물 $person, 진행 $phase에서 이미 보인 픽셀이 사라짐');
            }
            previous = Uint8List.fromList(pixels);
            final reversed = await render((person + 1 - phase) / 3);
            for (var i = 3; i < pixels.length; i += 4) {
              expect((pixels[i] - reversed[i]).abs(), lessThanOrEqualTo(2),
                reason: '인물 $person, 진행 $phase의 등장·퇴장 모양이 다름');
            }
        }
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
