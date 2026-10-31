# Third-party libraries

AndroidTransmit dynamically links the unmodified libmtp 1.1.23 and libusb libraries,
both licensed under LGPL-2.1-or-later. The installed libusb version and source
checksum are recorded in `libusb-sbom.spdx.json` inside the application bundle.

The DMG includes the corresponding source archives, license texts, and this notice
in `AndroidTransmit.app/Contents/Resources/ThirdParty/`. libusb's Homebrew build
metadata is included in its SBOM. libmtp is built using
`script/setup_dependencies.sh` in the AndroidTransmit repository. Bundling changes
only library install names and code signatures, not third-party source code.

- libmtp: https://github.com/libmtp/libmtp
- libusb: https://github.com/libusb/libusb
- Build and packaging scripts: https://github.com/misanyrock/AndroidTransmit

You may replace the dynamic libraries in `Contents/Frameworks` with compatible
modified builds for your own use. After replacement, ad-hoc sign the libraries
and application again; the packaging script shows the required commands.
