#!/usr/bin/env bash
# Generate installable BuildBrowser artifacts for macOS.
set -euo pipefail

INSTALL_AFTER=0
for arg in "$@"; do
  case "$arg" in
    --install)
      INSTALL_AFTER=1
      ;;
    -h|--help)
      echo "Usage: $0 [--install]"
      echo ""
      echo "Generates dist/BuildBrowser-<version>-<build>.pkg and .app.zip."
      echo "  --install  Install the generated package to /Applications."
      exit 0
      ;;
    *)
      echo "error: unknown argument: $arg" >&2
      echo "Usage: $0 [--install]" >&2
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$BUILD_DIR/BuildBrowser.app"
PLIST_PATH="$APP_PATH/Contents/Info.plist"

echo "-> Building BuildBrowser..."
"$ROOT_DIR/build.sh"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found at $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_PATH")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST_PATH")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST_PATH")"
PKG_ID="$BUNDLE_ID.pkg"
BASE_NAME="BuildBrowser-$VERSION-$BUILD"
PKG_PATH="$DIST_DIR/$BASE_NAME.pkg"
ZIP_PATH="$DIST_DIR/$BASE_NAME.app.zip"
TMP_PKG="$DIST_DIR/.$BASE_NAME.pkg.$$"
TMP_ZIP="$DIST_DIR/.$BASE_NAME.app.zip.$$"
STAGE_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}BuildBrowserPackage.XXXXXX")"
APP_STAGE="$STAGE_DIR/Applications"

export COPYFILE_DISABLE=1

mkdir -p "$DIST_DIR" "$APP_STAGE"

echo "-> Staging app bundle..."
/usr/bin/ditto --noextattr --noqtn "$APP_PATH" "$APP_STAGE/BuildBrowser.app"

echo "-> Creating component package..."
/usr/bin/pkgbuild \
  --root "$STAGE_DIR" \
  --identifier "$PKG_ID" \
  --version "$VERSION.$BUILD" \
  --install-location "/" \
  "$TMP_PKG"
/bin/mv -f "$TMP_PKG" "$PKG_PATH"

echo "-> Creating update zip..."
(cd "$BUILD_DIR" && /usr/bin/zip -qry "$TMP_ZIP" "BuildBrowser.app")
/bin/mv -f "$TMP_ZIP" "$ZIP_PATH"

echo ""
echo "Done."
echo "  Installer: $PKG_PATH"
echo "  App zip:   $ZIP_PATH"
echo ""
echo "Install with:"
echo "  open $PKG_PATH"
echo "  or: ./package.sh --install"

if [[ "$INSTALL_AFTER" -eq 1 ]]; then
  echo ""
  echo "-> Installing to /Applications..."
  /usr/bin/sudo /usr/sbin/installer -pkg "$PKG_PATH" -target /
fi
