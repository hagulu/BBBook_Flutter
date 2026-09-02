#!/usr/bin/env bash
set -euo pipefail

# 릴리즈 APK 빌드 스크립트
# API_BASE_URL을 --dart-define으로 지정해 빌드한다.

API_BASE_URL="http://192.168.0.51:8081"

cd "$(dirname "$0")/.."

flutter build apk --release --dart-define=API_BASE_URL="$API_BASE_URL"
