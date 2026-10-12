import 'package:flutter/material.dart';

/// 원본의 어두운 종이는 제거하고 밝기 정보를 테마에 맞는 잉크로 그린다.
const portraitDarkAsset = 'assets/images/philosophers-monochrome-v2.png';
const portraitLightAsset = 'assets/images/philosophers-light-v1.png';

ColorFilter? portraitInkFilter(Brightness brightness) {
  // 라이트에서는 얼굴의 명암을 반전하지 않고 원본의 짙은 선을 유지한다.
  if (brightness == Brightness.light) {
    return null;
  }
  const ink = 238.0;
  return ColorFilter.matrix([
    0, 0, 0, 0, ink,
    0, 0, 0, 0, ink,
    0, 0, 0, 0, ink,
    0.30, 0.59, 0.11, 0, -24,
  ]);
}
