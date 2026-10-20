#!/usr/bin/env bash
# Build a signed, notarized and stapled SECHA.app plus a zip to share with other Macs.
#
#   scripts/export_macos.sh [output-dir]        (default: builds/macos, git-ignored)
#
# Needs, on the signing Mac only (nothing secret lives in the repo):
#   - Godot 4.7.2 with its export templates (GODOT overrides the path);
#   - the "Developer ID Application" identity named in export_presets.cfg, in the login keychain;
#   - a notarytool keychain profile (NOTARY_PROFILE, default SECHA-notary), created once with
#     xcrun notarytool store-credentials SECHA-notary --team-id <team id>
# macOS may ask once whether codesign may use the signing key: choose Always Allow.
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROFILE="${NOTARY_PROFILE:-SECHA-notary}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mkdir -p "${1:-$ROOT/builds/macos}" && cd "${1:-$ROOT/builds/macos}" && pwd)"
APP="$OUT/SECHA.app"
UPLOAD="$OUT/SECHA-notarize.zip"
VERSION="$(sed -n 's/^application\/short_version="\(.*\)"/\1/p' "$ROOT/export_presets.cfg")"
SHARE="$OUT/SECHA-$VERSION-macos.zip"

rm -rf "$APP" "$UPLOAD" "$SHARE"
echo "== export (Godot signs every binary with hardened runtime)"
"$GODOT" --headless --path "$ROOT" --export-release "macOS" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "== notarize with keychain profile $PROFILE"
ditto -c -k --keepParent "$APP" "$UPLOAD"
RESULT="$(xcrun notarytool submit "$UPLOAD" --keychain-profile "$PROFILE" --wait 2>&1 | tee /dev/stderr)"
rm -f "$UPLOAD"
if ! grep -q "status: Accepted" <<<"$RESULT"; then
	ID="$(sed -n 's/^ *id: \([0-9a-f-]*\)$/\1/p' <<<"$RESULT" | head -1)"
	[ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" >&2
	echo "Notarization was not accepted." >&2
	exit 1
fi

echo "== staple and check as another Mac would"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
ditto -c -k --keepParent "$APP" "$SHARE"
echo "Ready to share: $SHARE"
