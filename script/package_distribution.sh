#!/usr/bin/env bash
set -euo pipefail

PRODUCT_NAME="Suiji"
APP_NAME="拾序"
VERSION="0.1.1"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$PRODUCT_NAME"
ARM_BUILD_DIR="$ROOT_DIR/.build-distribution-arm64"
INTEL_BUILD_DIR="$ROOT_DIR/.build-distribution-x86_64"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-macOS-universal.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

cleanup() {
  if [[ -n "${MOUNT_DEVICE:-}" ]]; then
    hdiutil detach "$MOUNT_DEVICE" >/dev/null 2>&1 || true
  fi
  if [[ -n "${MOUNT_DIR:-}" && -d "$MOUNT_DIR" ]]; then
    rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
  fi
  if [[ -n "${STAGING_DIR:-}" && -d "$STAGING_DIR" ]]; then
    rm -rf "$STAGING_DIR"
  fi
  if [[ -n "${UNIVERSAL_BINARY:-}" && -f "$UNIVERSAL_BINARY" ]]; then
    rm -f "$UNIVERSAL_BINARY"
  fi
}
trap cleanup EXIT

cd "$ROOT_DIR"
"$ROOT_DIR/script/build_and_run.sh" --build-only

swift build -c release --arch arm64 --scratch-path "$ARM_BUILD_DIR"
ARM_BINARY="$(swift build -c release --arch arm64 --scratch-path "$ARM_BUILD_DIR" --show-bin-path)/$PRODUCT_NAME"

swift build -c release --arch x86_64 --scratch-path "$INTEL_BUILD_DIR"
INTEL_BINARY="$(swift build -c release --arch x86_64 --scratch-path "$INTEL_BUILD_DIR" --show-bin-path)/$PRODUCT_NAME"

UNIVERSAL_BINARY="$(mktemp -t shixu-universal-binary)"
lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$UNIVERSAL_BINARY"
cp "$UNIVERSAL_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  codesign --force --deep --options runtime --sign - "$APP_BUNDLE"
fi

codesign --verify --deep --strict "$APP_BUNDLE"
lipo "$APP_BINARY" -verify_arch arm64 x86_64

STAGING_DIR="$(mktemp -d -t shixu-dmg)"
ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/应用程序"
cp "$ROOT_DIR/distribution/安装说明.txt" "$STAGING_DIR/安装说明.txt"

rm -f "$DMG_PATH" "$CHECKSUM_PATH"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG_PATH"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "NOTARY_PROFILE 需要与 SIGN_IDENTITY 一起使用。" >&2
    exit 2
  fi
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH"

MOUNT_DIR="$(mktemp -d -t shixu-mounted-dmg)"
MOUNT_DEVICE="$(hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$DMG_PATH" | tail -1 | awk '{print $1}')"
MOUNTED_APP="$MOUNT_DIR/$APP_NAME.app"
test -d "$MOUNTED_APP"
test -L "$MOUNT_DIR/应用程序"
test -f "$MOUNT_DIR/安装说明.txt"
codesign --verify --deep --strict "$MOUNTED_APP"
lipo "$MOUNTED_APP/Contents/MacOS/$PRODUCT_NAME" -verify_arch arm64 x86_64
hdiutil detach "$MOUNT_DEVICE" >/dev/null
MOUNT_DEVICE=""
rmdir "$MOUNT_DIR"
MOUNT_DIR=""

shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"

echo "Created $DMG_PATH"
echo "Created $CHECKSUM_PATH"
if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "Notice: no Developer ID identity was supplied; the receiver may need to right-click the app and choose Open once."
fi
