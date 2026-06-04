#!/usr/bin/env bash
# Generate installable BuildBrowser artifacts for macOS.
set -euo pipefail

INSTALL_AFTER=0
BASE_URL=""
GIT_UPDATES=0
UPDATES_DIR_NAME="updates"
BRANCH_NAME=""
for arg in "$@"; do
  case "$arg" in
    --install)
      INSTALL_AFTER=1
      ;;
    --base-url=*)
      BASE_URL="${arg#*=}"
      BASE_URL="${BASE_URL%/}"
      ;;
    --git-updates)
      GIT_UPDATES=1
      ;;
    --updates-dir=*)
      UPDATES_DIR_NAME="${arg#*=}"
      ;;
    --branch=*)
      BRANCH_NAME="${arg#*=}"
      ;;
    -h|--help)
      echo "Usage: $0 [--install] [--base-url=https://example.com/releases] [--git-updates] [--branch=dev] [--updates-dir=updates]"
      echo ""
      echo "Generates dist/BuildBrowser-<version>-<build>.pkg and .app.zip."
      echo "  --install  Install the generated package to /Applications."
      echo "  --base-url Base URL used in dist/manifest.json for auto updates."
      echo "  --git-updates Write update files into the git repo and use GitHub raw URLs."
      echo "  --branch Branch name used for GitHub raw URLs in --git-updates mode."
      echo "  --updates-dir Repo-relative directory for update files."
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
UPDATES_DIR="$ROOT_DIR/$UPDATES_DIR_NAME"
APP_PATH="$BUILD_DIR/BuildBrowser.app"
PLIST_PATH="$APP_PATH/Contents/Info.plist"

github_raw_base_url() {
  local remote branch repo
  remote="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
  branch="$BRANCH_NAME"
  if [[ -z "$branch" ]]; then
    branch="$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true)"
  fi
  if [[ -z "$remote" || -z "$branch" ]]; then
    return 1
  fi

  case "$remote" in
    git@github.com:*)
      repo="${remote#git@github.com:}"
      repo="${repo%.git}"
      ;;
    https://github.com/*)
      repo="${remote#https://github.com/}"
      repo="${repo%.git}"
      ;;
    http://github.com/*)
      repo="${remote#http://github.com/}"
      repo="${repo%.git}"
      ;;
    *)
      return 1
      ;;
  esac

  printf 'https://raw.githubusercontent.com/%s/%s/%s' "$repo" "$branch" "$UPDATES_DIR_NAME"
}

write_manifest() {
  local path base_url
  path="$1"
  base_url="${2%/}"
  /bin/cat > "$path" <<EOF
{
  "name": "BuildBrowser",
  "version": "$VERSION",
  "build": $BUILD,
  "bundleURL": "$base_url/$BASE_NAME.app.zip",
  "notes": "Build $BUILD is ready to install."
}
EOF
}

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
MANIFEST_PATH="$DIST_DIR/manifest.json"
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

if [[ -n "$BASE_URL" ]]; then
  echo "-> Writing update manifest..."
  write_manifest "$MANIFEST_PATH" "$BASE_URL"
fi

if [[ "$GIT_UPDATES" -eq 1 ]]; then
  GIT_BASE_URL="$(github_raw_base_url)" || {
    echo "error: --git-updates requires a GitHub origin remote and a current branch." >&2
    echo "hint: use --base-url instead, or pass --branch=<name>." >&2
    exit 1
  }
  echo "-> Writing git-hosted update files..."
  mkdir -p "$UPDATES_DIR"
  /bin/cp -f "$ZIP_PATH" "$UPDATES_DIR/$BASE_NAME.app.zip"
  write_manifest "$UPDATES_DIR/manifest.json" "$GIT_BASE_URL"
fi

echo ""
echo "Done."
echo "  Installer: $PKG_PATH"
echo "  App zip:   $ZIP_PATH"
if [[ -n "$BASE_URL" ]]; then
  echo "  Manifest:  $MANIFEST_PATH"
fi
if [[ "$GIT_UPDATES" -eq 1 ]]; then
  echo "  Git zip:   $UPDATES_DIR/$BASE_NAME.app.zip"
  echo "  Git manifest: $UPDATES_DIR/manifest.json"
  echo "  Manifest URL: $GIT_BASE_URL/manifest.json"
fi
echo ""
echo "Install with:"
echo "  open $PKG_PATH"
echo "  or: ./package.sh --install"

if [[ "$INSTALL_AFTER" -eq 1 ]]; then
  echo ""
  echo "-> Installing to /Applications..."
  /usr/bin/sudo /usr/sbin/installer -pkg "$PKG_PATH" -target /
fi
