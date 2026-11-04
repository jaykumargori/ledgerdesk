#!/bin/zsh
set -eu
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
cd "${0:A:h}"
mkdir -p build
stage=$(mktemp -d "${TMPDIR:-/tmp}/ledgerdesk-build.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/LedgerDesk.app/Contents/MacOS"
swiftc -target arm64-apple-macos14.0 -module-cache-path "${TMPDIR:-/tmp}/ledgerdesk-build-cache" -parse-as-library LedgerDesk.swift Invoices.swift InvoiceViews.swift Reports.swift Business.swift BusinessViews.swift PrimeUI.swift LatestUI.swift BankReports.swift BankingUI.swift PurchaseOrders.swift DocumentUI.swift -o "$stage/LedgerDesk.app/Contents/MacOS/LedgerDesk"
cp -X Info.plist "$stage/LedgerDesk.app/Contents/Info.plist"
codesign --force --sign - "$stage/LedgerDesk.app"
codesign --verify --deep --strict "$stage/LedgerDesk.app"
ditto -c -k --keepParent "$stage/LedgerDesk.app" build/LedgerDesk-Mac.zip
