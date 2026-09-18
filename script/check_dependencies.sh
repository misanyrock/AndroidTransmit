#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -m)" != arm64 ]]; then echo '首版需要 Apple Silicon Mac。' >&2; exit 1; fi
if [[ ! -f .build/native/include/libmtp.h && ! -f /opt/homebrew/opt/libmtp/include/libmtp.h ]]; then
  echo '缺少 libmtp。执行 brew install libmtp，或 ./script/setup_dependencies.sh 使用项目内源码构建。' >&2
  exit 1
fi
xcodebuild -version
/opt/homebrew/bin/brew list --versions libusb
