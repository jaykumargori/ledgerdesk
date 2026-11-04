# Latest TallyPrime feature coverage — checked 4 November 2026

Target reference: TallyPrime 7.2, released 12 October 2026. LedgerDesk is an independent development application and does not have complete feature parity.

## Release 7.2
Source: [official release notes](https://help.tallysolutions.com/release-notes-tallyprime-7-2/).

| Feature | LedgerDesk 0.6 status |
|---|---|
| Purchase-order print templates | Basic local orders and three template styles implemented; full original catalogue absent |
| Automatic template configuration saving | Implemented for local invoice/order settings; print/export/share parity incomplete |
| Try Now discovery | Local tile, navigation, hiding, minimisation and feature list implemented |
| TallyIra entry in Help | External documentation link only; no service connection |
| Updated FVU 1.2 TDS/TCS workflows | Not implemented; requires verified formats, validation tooling and statutory testing |
| Extended e-invoice/e-way-bill sessions | Not implemented; requires authorized service integration |
| Tobacco MRP/deemed-value tax treatment | Not implemented |
| GSTR-9 export | Not implemented; no official-format tax-return export |
| UAE e-invoice exchange | Not implemented; requires external provider integration |

## Features inherited from 7.1
Source: [official 7.1 notes](https://help.tallysolutions.com/release-notes-tallyprime-7-1/).

| Feature | LedgerDesk 0.6 status |
|---|---|
| Personalised invoice templates | Basic styles, fonts, colours, header/footer and saved preferences; no logos/watermarks or full designer |
| Auto Wrap Text | Print-template option; no universal master/report configuration |
| Potential-match reconciliation summaries | Basic same-amount/30-day suggestions, exact manual linking and unique same-date auto-match; advanced rules/partial/multiple matching absent |
| Bill allocation during bank-driven vouchers | Single corresponding ledger supported; bill allocation absent |
| IMS party lookup and reconciliation | Not implemented |
| ICICI connected payments | Not connected |
| Schedule III financial statements | Not implemented |
| Percentage/amount discounts | Not implemented |
| OAuth e-mail | Not connected |
| Subscription and TallyDrive status | Not connected |
| Updated statutory/GST workflows | User-configured invoice charges only; validation, eligibility, returns and filing absent |

## Features inherited from 7.0
Source: [official 7.0 notes](https://help.tallysolutions.com/release-notes-tallyprime-7-0/).

| Feature | LedgerDesk 0.6 status |
|---|---|
| SmartFind | Local substring search across supported records; fuzzy/cross-company search absent |
| Scheduled/local/cloud backup | Manual local JSON backups and protected restore; scheduling/cloud absent |
| Online payment limits and status | Not connected |
| JSON exchange | LedgerDesk backup schema; no Tally schema compatibility |
| Migration and additional currency capabilities | Not implemented |

## Banking reference and practical limits
[Banking report guide](https://help.tallysolutions.com/bank-recon-reports/) and [reconciliation guide](https://help.tallysolutions.com/auto-bank-reconciliation/) informed the Activities → Summary → Transactions flow. The linked reference image is https://help.tallysolutions.com/wp-content/uploads/2020/08/Exact-Match-2.png ; its upload folder is old and it is used by current documentation, so it is not asserted to be a release-specific 7.2 screenshot.

LedgerDesk supports normalized CSV imports, bank metadata, cumulative balances, one-to-one reconciliation, basic candidate suggestions, and voucher creation from a bank line. No bank connection, payment authorization, tax portal login or third-party submission is performed. Integration-dependent entries above are genuinely unimplemented; they are not represented as working services.
