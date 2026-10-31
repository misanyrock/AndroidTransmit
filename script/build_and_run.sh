#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-run}"
case "$MODE" in run|--debug|--logs|--telemetry|--verify|--build) ;; *) echo "usage: $0 [--build|--debug|--logs|--telemetry|--verify]" >&2; exit 2;; esac
./script/check_dependencies.sh
MTP_PREFIX="$(pwd)/.build/native"
[[ -f "$MTP_PREFIX/include/libmtp.h" ]] || MTP_PREFIX="$(brew --prefix libmtp)"
if [[ "$MODE" != "--build" ]]; then pkill -x AndroidTransmit >/dev/null 2>&1 || true; fi
xcodebuild -project AndroidTransmit.xcodeproj -scheme AndroidTransmit -configuration "${CONFIGURATION:-Debug}" -derivedDataPath .build MTP_PREFIX="$MTP_PREFIX" CODE_SIGN_IDENTITY=- build
APP="$(pwd)/.build/Build/Products/${CONFIGURATION:-Debug}/AndroidTransmit.app"
# Xcode omits the runtime flag for ad-hoc identities; explicitly retain it for self-use.
codesign --force --sign - --options runtime --entitlements AndroidTransmit/AndroidTransmit.entitlements "$APP"
case "$MODE" in
 --build) echo "$APP" ;;
 --debug) lldb -- "$APP/Contents/MacOS/AndroidTransmit" ;;
 --logs) open "$APP"; /usr/bin/log stream --info --style compact --predicate 'process == "AndroidTransmit"' ;;
 --telemetry) open "$APP"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.misanyrock.AndroidTransmit"' ;;
 --verify) open "$APP"; sleep 2; pgrep -x AndroidTransmit >/dev/null; echo 'AndroidTransmit 已启动' ;;
 *) open "$APP" ;;
esac
