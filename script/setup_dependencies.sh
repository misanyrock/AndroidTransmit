#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f /opt/homebrew/opt/libusb/lib/pkgconfig/libusb-1.0.pc ]]; then
  echo '请先安装 brew install libusb pkgconf' >&2; exit 1
fi
VERSION=1.1.23
SHA=74a2b6e8cb4a0304e95b995496ea3ac644c29371649b892b856e22f12a0bdeed
ROOT="$(pwd)"
PREFIX="$ROOT/.build/native"
mkdir -p .build/dependencies
ARCHIVE="$ROOT/.build/dependencies/libmtp-$VERSION.tar.gz"
if [[ ! -f "$ARCHIVE" ]]; then
  CACHE_FILE="$(find "$(brew --cache)/downloads" -name "*--libmtp-$VERSION.tar.gz" -print -quit)"
  if [[ -n "$CACHE_FILE" ]]; then cp "$CACHE_FILE" "$ARCHIVE";
  else curl -fL "https://downloads.sourceforge.net/project/libmtp/libmtp/$VERSION/libmtp-$VERSION.tar.gz" -o "$ARCHIVE"; fi
fi
printf '%s  %s\n' "$SHA" "$ARCHIVE" | shasum -a 256 -c -
tar -xzf "$ARCHIVE" -C .build/dependencies
cd ".build/dependencies/libmtp-$VERSION"
PKG_CONFIG_PATH=/opt/homebrew/opt/libusb/lib/pkgconfig ./configure --prefix="$PREFIX" --disable-mtpz --disable-static --disable-silent-rules
make -j4
make install
