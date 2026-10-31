#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

./script/check_dependencies.sh
LIBMTP="$(pwd)/.build/native/lib/libmtp.9.dylib"
LIBUSB="$(brew --prefix libusb)/lib/libusb-1.0.0.dylib"
test -f "$LIBMTP"
test -f .build/dependencies/libmtp-1.1.23.tar.gz

CONFIGURATION=Release ./script/build_and_run.sh --build
STAGE="$(mktemp -d "$(pwd)/.build/dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/AndroidTransmit.app"
ditto .build/Build/Products/Release/AndroidTransmit.app "$APP"
FRAMEWORKS="$APP/Contents/Frameworks"
NOTICES="$APP/Contents/Resources/ThirdParty"
mkdir -p "$FRAMEWORKS" "$NOTICES"
cp "$LIBMTP" "$LIBUSB" "$FRAMEWORKS/"
chmod u+w "$FRAMEWORKS/"*.dylib
cp .build/dependencies/libmtp-1.1.23/COPYING "$NOTICES/libmtp-COPYING"
cp .build/dependencies/libmtp-1.1.23.tar.gz "$NOTICES/"
cp "$(brew --prefix libusb)/COPYING" "$NOTICES/libusb-COPYING"
cp "$(brew --prefix libusb)/sbom.spdx.json" "$NOTICES/libusb-sbom.spdx.json"
cp LICENSE "$APP/Contents/Resources/LICENSE"

# Use the installed bottle's source metadata so a later brew upgrade cannot mismatch the binary.
python3 - "$NOTICES" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
import urllib.request

destination = Path(sys.argv[1])
sbom = json.loads((destination / "libusb-sbom.spdx.json").read_text())
source = next(p for p in sbom["packages"] if p["SPDXID"] == "SPDXRef-Archive-libusb-src")
url = source["downloadLocation"]
assert url.startswith("https://github.com/libusb/libusb/releases/download/"), url
checksum = next(c["checksumValue"] for c in source["checksums"] if c["algorithm"] == "SHA256")
archive = destination / ("libusb-" + source["versionInfo"] + ".tar.bz2")
with urllib.request.urlopen(url, timeout=120) as response:
    archive.write_bytes(response.read())
if hashlib.sha256(archive.read_bytes()).hexdigest() != checksum:
    raise SystemExit("libusb source SHA-256 mismatch")
PY

cp THIRD_PARTY_NOTICES.md "$NOTICES/README.md"
BINARIES=("$APP/Contents/MacOS/AndroidTransmit" "$FRAMEWORKS/"*.dylib)
for binary in "${BINARIES[@]}"; do
  while IFS= read -r dependency; do
    case "$dependency" in
      */libmtp.9.dylib|*/libusb-1.0.0.dylib)
        install_name_tool -change "$dependency" "@rpath/$(basename "$dependency")" "$binary"
        ;;
    esac
  done < <(otool -L "$binary" | tail -n +2 | sed -E 's/^[[:space:]]+//; s/ \(compatibility version.*//')
done
for library in "$FRAMEWORKS/"*.dylib; do
  install_name_tool -id "@rpath/$(basename "$library")" "$library"
  codesign --force --sign - "$library"
done
# shortcut: ad-hoc signing needs no secrets; use Developer ID and notarization for trusted public installs.
codesign --force --sign - --options runtime --entitlements AndroidTransmit/AndroidTransmit.entitlements "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# Fail packaging if any Mach-O still needs a library outside this bundle or macOS.
for binary in "${BINARIES[@]}"; do
  while IFS= read -r dependency; do
    case "$dependency" in
      /usr/lib/*|/System/Library/*) ;;
      @rpath/*) test -f "$FRAMEWORKS/${dependency#@rpath/}" ;;
      *) echo "Unbundled dependency: $dependency ($binary)" >&2; exit 1 ;;
    esac
  done < <(otool -L "$binary" | tail -n +2 | sed -E 's/^[[:space:]]+//; s/ \(compatibility version.*//')
done
ln -s /Applications "$STAGE/Applications"
mkdir -p dist
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="dist/AndroidTransmit-$VERSION-arm64.dmg"
hdiutil create -volname AndroidTransmit -srcfolder "$STAGE" -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
(cd dist; shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "$DMG"
