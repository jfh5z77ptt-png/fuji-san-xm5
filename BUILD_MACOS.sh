#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
flutter pub get
flutter analyze
flutter test
flutter build macos --release --dart-define=FUJI_DEFAULT_MODEL=X-M5
printf '%s\n' 'App: build/macos/Build/Products/Release/fuji_san.app'
