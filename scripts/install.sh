#!/usr/bin/env bash
#
# Build, sign and install the Safari extension.
#
#   scripts/install.sh              build, sign, install, report
#   scripts/install.sh --reconvert  regenerate the Xcode project first
#   scripts/install.sh --no-prune   leave stray registrations alone
#
# Why signing rather than ad-hoc: docs/signing.md
# Why converting once, and the two traps below: docs/building.md
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUNDLE="$ROOT/out/extension"
PROJECT_DIR="$ROOT/out/safari"
APP_NAME="SharePointVideoDL"
PROJECT="$PROJECT_DIR/$APP_NAME/$APP_NAME.xcodeproj"
DERIVED="$PROJECT_DIR/DerivedData"
BUILT="$DERIVED/Build/Products/Release/$APP_NAME.app"
INSTALLED="$HOME/Applications/$APP_NAME.app"
APPEX_REL="Contents/PlugIns/$APP_NAME Extension.appex/Contents/Resources"
# Last component must equal APP_NAME exactly, casing included. docs/building.md
BUNDLE_ID="io.akst.$APP_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
LOG="$PROJECT_DIR/xcodebuild.log"

RECONVERT=0
PRUNE=1
for arg in "$@"; do
  case "$arg" in
    --reconvert) RECONVERT=1 ;;
    --no-prune)  PRUNE=0 ;;
    -h|--help)   sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $arg (try --help)" >&2; exit 2 ;;
  esac
done

say() { printf '\n== %s\n' "$*"; }
die() { printf '\nREFUSING: %s\n' "$*" >&2; exit 1; }
version_of() { python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['version'])" "$1"; }

# -- preflight -----------------------------------------------------------------
say "preflight"
developer="$(xcode-select -p 2>/dev/null || true)"
case "$developer" in
  *Xcode.app*) printf '  xcode-select -> %s\n' "$developer" ;;
  "") die "xcode-select found nothing. Install Xcode, then:
    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" ;;
  *) die "xcode-select points at $developer, the Command Line Tools.
The converter and xcodebuild both live in Xcode proper:
    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" ;;
esac
xcrun --find safari-web-extension-converter >/dev/null 2>&1 \
  || die "xcrun cannot find safari-web-extension-converter under $developer"

# Developer ID first, Apple Development second, never ad-hoc. docs/signing.md
if [ -z "${IDENTITY:-}" ]; then
  IDENTITY="$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "${IDENTITY:-}" ]; then
  IDENTITY="$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
fi
[ -n "${IDENTITY:-}" ] || die "no Developer ID or Apple Development certificate in the keychain.
Safari only keeps an extension enabled if its app is signed by one -- see
docs/signing.md. Open Xcode > Settings > Accounts, add your Apple ID and let it
create a development certificate; a free account is enough. Then re-run this.
Already have one under another name? IDENTITY='Apple Development: ...' $0"

TEAM="${TEAM:-$(security find-certificate -c "$IDENTITY" -p 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null \
  | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')}"
[ -n "$TEAM" ] || die "could not read the team (certificate OU) from '$IDENTITY'. Pass TEAM=... to override."

printf '  signing as: %s\n  team:       %s\n' "$IDENTITY" "$TEAM"
printf '  currently installed: %s\n' \
  "$([ -d "$INSTALLED" ] && version_of "$INSTALLED/$APPEX_REL/manifest.json" || echo 'nothing')"

# -- compile and test ----------------------------------------------------------
say "compiling src/"
[ -d node_modules ] || npm install --silent
./scripts/build.sh | sed 's/^/  /'
version="$(version_of "$BUNDLE/manifest.json")"

say "testing the compiled extension"
node --test scripts/test.mjs >/dev/null 2>&1 \
  || { node --test scripts/test.mjs 2>&1 | tail -30; die "tests failed -- not installing this"; }
printf '  passed\n'

# -- convert, only when there is nothing to update -----------------------------
if [ "$RECONVERT" = 1 ] || [ ! -d "$PROJECT" ]; then
  if [ "$RECONVERT" = 1 ] && [ -d "$PROJECT_DIR/$APP_NAME" ]; then
    say "regenerating the Xcode project (--reconvert)"
    rm -rf "$PROJECT_DIR/$APP_NAME"
  else
    say "generating the Xcode project (none yet)"
  fi
  mkdir -p "$PROJECT_DIR"
  xcrun safari-web-extension-converter "$BUNDLE" \
    --project-location "$PROJECT_DIR" --app-name "$APP_NAME" \
    --bundle-identifier "$BUNDLE_ID" --macos-only --no-open --no-prompt --force
else
  say "reusing the Xcode project"
  printf '  %s\n  it references out/extension in place, so the new build is in it already\n' "$PROJECT"
fi

app_id="$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = \(.*\);/\1/p' "$PROJECT/project.pbxproj" | grep -v '\.Extension$' | head -1)"
ext_id="$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = \(.*\);/\1/p' "$PROJECT/project.pbxproj" | grep '\.Extension$' | head -1)"
case "$ext_id" in
  "$app_id".*) ;;
  *) die "the converter wrote identifiers that do not nest:
    app:       $app_id
    extension: $ext_id
BUNDLE_ID's last component must equal APP_NAME exactly, casing included.
See docs/building.md. Fix it at the top of this script, re-run with --reconvert." ;;
esac

# -- build and sign ------------------------------------------------------------
say "building $APP_NAME.app"
xcodebuild -project "$PROJECT" -scheme "$APP_NAME" -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  build >"$LOG" 2>&1 \
  || { tail -40 "$LOG"; die "xcodebuild failed -- full log at $LOG"; }
printf '  built\n'

# A green build is not a signed one, and ad-hoc is the failure to prevent.
codesign --verify --deep --strict "$BUILT" 2>&1 | sed 's/^/  codesign: /'
authority="$(codesign -dvv "$BUILT" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
[ -n "$authority" ] || die "the app came out ad-hoc signed, not signed by a certificate.
That is the state Safari calls unsigned, so this is not worth installing.
See docs/signing.md. Full log at $LOG"
printf '  signed by: %s\n' "$authority"

# -- verify BEFORE touching what is installed ----------------------------------
say "verifying the build carries what we just made"
[ -d "$BUILT/$APPEX_REL" ] || die "no extension resources at $BUILT/$APPEX_REL"
built_version="$(version_of "$BUILT/$APPEX_REL/manifest.json")"
[ "$built_version" = "$version" ] \
  || die "the app carries v$built_version and the build is v$version -- Xcode built something stale"
printf '  v%s, hosts: %s\n' "$built_version" \
  "$(python3 -c "import json,sys;print(', '.join(json.load(open(sys.argv[1]))['host_permissions']))" "$BUILT/$APPEX_REL/manifest.json")"

# -- install, last, now that the build is proven good --------------------------
say "installing to ~/Applications"
mkdir -p "$HOME/Applications"
rm -rf "$INSTALLED"
cp -R "$BUILT" "$INSTALLED"
installed_version="$(version_of "$INSTALLED/$APPEX_REL/manifest.json")"
[ "$installed_version" = "$version" ] || die "installed v$installed_version, expected v$version"
printf '  %s is v%s\n' "$INSTALLED" "$installed_version"

# -- one app, not several ------------------------------------------------------
say "registered copies"
strays="$("$LSREGISTER" -dump 2>/dev/null \
  | grep -io "path: *[^(]*$APP_NAME\.app" \
  | sed 's/^[Pp]ath: *//' | sed 's/ *$//' | sort -u | grep -Fxv "$INSTALLED" || true)"
if [ -n "$strays" ]; then
  printf '%s\n' "$strays" | while IFS= read -r stray; do
    [ -n "$stray" ] || continue
    if [ "$PRUNE" = 1 ]; then
      printf '  unregistering: %s\n' "$stray"
      "$LSREGISTER" -u "$stray" >/dev/null 2>&1 || true
    else
      printf '  STRAY (left, --no-prune): %s\n' "$stray"
    fi
  done
  printf '  strays are why Safari lists the same extension more than once. docs/building.md\n'
else
  printf '  just the installed one\n'
fi
"$LSREGISTER" -f "$INSTALLED" >/dev/null 2>&1 || true
open "$INSTALLED"

# -- what only you can do ------------------------------------------------------
say "over to you, in Safari"
cat <<INSTRUCTIONS
  The app has been opened so Safari can see the extension.

  1. Settings > Extensions, tick "SharePoint Video Downloader" (v$version).
     There is NO Develop > Allow Unsigned Extensions step: it is signed by
     $IDENTITY,
     so the tick survives quitting Safari.
  2. Click the toolbar button once on a sharepoint.com page and allow it on the
     site, so it stops asking on every course page.

  Then open a lecture video and click the button, or press Cmd+Shift+Y. A green
  toast names the file as the download starts; a red one says what was wrong.

  On a rebuild the extension STAYS ENABLED; re-running this script is enough.
INSTRUCTIONS
