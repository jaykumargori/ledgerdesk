#!/bin/zsh
set -eu
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
cd "${0:A:h}"
mkdir -p build
sparkle_dir="${SPARKLE_DIR:-../sparkle}"
if [[ ! -d "$sparkle_dir/Sparkle.framework" ]]; then
  print -u2 "Sparkle.framework not found in $sparkle_dir. Set SPARKLE_DIR to the extracted Sparkle distribution."
  exit 1
fi
stage=$(mktemp -d "${TMPDIR:-/tmp}/ledgerdesk-build.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/LedgerDesk.app/Contents/MacOS" "$stage/LedgerDesk.app/Contents/Frameworks" "$stage/LedgerDesk.app/Contents/Resources"
cp -X assets/LedgerDesk.icns "$stage/LedgerDesk.app/Contents/Resources/LedgerDesk.icns"
ditto "$sparkle_dir/Sparkle.framework" "$stage/LedgerDesk.app/Contents/Frameworks/Sparkle.framework"
xattr -cr "$stage/LedgerDesk.app/Contents/Frameworks/Sparkle.framework"
swiftc -target arm64-apple-macos14.0 -module-cache-path "${TMPDIR:-/tmp}/ledgerdesk-build-cache" -F "$stage/LedgerDesk.app/Contents/Frameworks" -framework Sparkle -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' -parse-as-library LedgerDesk.swift Invoices.swift InvoiceViews.swift Reports.swift Business.swift BusinessViews.swift PrimeUI.swift LatestUI.swift BankReports.swift BankingUI.swift PurchaseOrders.swift DocumentUI.swift -o "$stage/LedgerDesk.app/Contents/MacOS/LedgerDesk"
cp -X Info.plist "$stage/LedgerDesk.app/Contents/Info.plist"
codesign --force --sign - "$stage/LedgerDesk.app"
codesign --verify --deep --strict "$stage/LedgerDesk.app"
ditto -c -k --keepParent "$stage/LedgerDesk.app" build/LedgerDesk-Mac.zip
