#!/usr/bin/env bash
set -euo pipefail

# 릴리즈 APK 빌드 스크립트
# API_BASE_URL, KAKAO_NATIVE_APP_KEY를 --dart-define으로 지정해 빌드한다.
# KAKAO_NATIVE_APP_KEY는 android/local.properties의 kakao.nativeAppKey와 같은 값이어야 한다.

API_BASE_URL="http://192.168.0.51:8081"
KAKAO_NATIVE_APP_KEY="여기에-실제-카카오-네이티브-앱-키-입력"

cd "$(dirname "$0")/.."

flutter build apk --release \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=KAKAO_NATIVE_APP_KEY="$KAKAO_NATIVE_APP_KEY"
