#!/bin/zsh
set -eu
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
cd "${0:A:h}"
mkdir -p build
python3 - <<'PY'
from pathlib import Path
source = Path('LedgerDesk.swift').read_text().split('@MainActor')[0]
Path('build/Models.swift').write_text(source.replace('import SwiftUI\n', '').replace('import AppKit\n', ''))
PY
swiftc -module-cache-path "${TMPDIR:-/tmp}/ledgerdesk-build-cache" -parse-as-library build/Models.swift Invoices.swift Business.swift BankReports.swift PurchaseOrders.swift Tests/InvoiceTests.swift -o build/invoice-tests
./build/invoice-tests

swiftc -module-cache-path "${TMPDIR:-/tmp}/ledgerdesk-build-cache" -parse-as-library build/Models.swift Invoices.swift Business.swift BankReports.swift PurchaseOrders.swift Tests/BusinessTests.swift -o build/business-tests
./build/business-tests

swiftc -module-cache-path "${TMPDIR:-/tmp}/ledgerdesk-build-cache" -parse-as-library build/Models.swift Invoices.swift Business.swift BankReports.swift PurchaseOrders.swift Tests/FeatureTests.swift -o build/feature-tests
./build/feature-tests
