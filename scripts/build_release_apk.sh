#!/usr/bin/env bash
set -euo pipefail

# 릴리즈 APK 빌드 스크립트
# API_BASE_URL은 --dart-define으로 지정하고, 카카오/네이버 SDK 키는
# android/local.properties에서 네이티브 빌드에 주입한다.

API_BASE_URL="https://api.bookumi.app"

cd "$(dirname "$0")/.."

flutter build apk --release \
  --dart-define=API_BASE_URL="$API_BASE_URL" --dart-define=ALLOW_TEST_ADS=true
