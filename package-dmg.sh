#!/bin/zsh
set -eu
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
cd "${0:A:h}"
archive=build/LedgerDesk-Mac.zip
[[ -f "$archive" ]] || { print -u2 "Build LedgerDesk first with ./build.sh"; exit 1; }
stage=$(mktemp -d "${TMPDIR:-/tmp}/ledgerdesk-dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto -x -k "$archive" "$stage"
xattr -cr "$stage/LedgerDesk.app"
codesign --verify --deep --strict "$stage/LedgerDesk.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -ov -volname LedgerDesk -srcfolder "$stage" -format UDZO build/LedgerDesk-Mac.dmg
