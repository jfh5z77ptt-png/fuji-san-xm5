#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' '이 설치 준비 스크립트는 Xcode가 설치된 Mac에서 실행하세요.' >&2
  exit 1
fi
if ! xcrun --find xcodebuild >/dev/null 2>&1; then
  printf '%s\n' '먼저 Xcode를 설치하고 한 번 실행해 초기 설정을 완료하세요.' >&2
  exit 1
fi
if ! command -v flutter >/dev/null 2>&1; then
  printf '%s\n' 'Flutter 3.47.6을 설치하고 flutter 명령을 사용할 수 있게 설정하세요.' >&2
  exit 1
fi
flutter pub get
dart run tool/sync_apple.dart --check
flutter build ios --debug --no-codesign --dart-define=FUJI_DEFAULT_MODEL=X-M5
open ios/Runner.xcworkspace
printf '%s\n' '컴파일 완료. 아직 아이폰에 설치된 것은 아닙니다.' \
  'Xcode에서 Runner → Signing & Capabilities → Team에 본인의 Apple 계정을 선택하세요.' \
  '연결한 아이폰을 실행 대상으로 선택하고 ▶ Run을 누르세요. 자세한 단계: IOS_USB_GUIDE.md'
