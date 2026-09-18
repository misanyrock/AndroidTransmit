#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./script/check_dependencies.sh
PREFIX=/opt/homebrew/opt/libmtp
[[ -f .build/native/include/libmtp.h ]] && PREFIX="$(pwd)/.build/native"
mkdir -p .build/tests
xcrun clang -c AndroidTransmit/Support/MTPBridge.c -I"$PREFIX/include" -o .build/tests/MTPBridge.o
xcrun swiftc -swift-version 5 -parse-as-library -import-objc-header AndroidTransmit/Support/MTPBridge.h \
  -I"$PREFIX/include" -L"$PREFIX/lib" -lmtp \
  AndroidTransmit/Models/Models.swift AndroidTransmit/Services/MTPService.swift \
  AndroidTransmit/Services/NativeMTPService.swift AndroidTransmit/Services/USBIdentity.swift \
  AndroidTransmit/Services/TransferEngine.swift AndroidTransmit/Stores/TransferQueue.swift \
  Tests/TestRunner.swift .build/tests/MTPBridge.o -o .build/tests/AndroidTransmitTests
.build/tests/AndroidTransmitTests "$@"
