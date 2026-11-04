import Foundation

struct InvoiceLine: Codable, Identifiable {
  var id = UUID()
  var item: UUID
  var quantity: Double
  var ratePaise: Int64
  var totalPaise: Int64 {
    Int64(
      (Decimal(ratePaise) * Decimal(quantity) as NSDecimalNumber).rounding(
        accordingToBehavior: NSDecimalNumberHandler(
          roundingMode: .plain, scale: 0, raiseOnExactness: false, raiseOnOverflow: false,
          raiseOnUnderflow: false, raiseOnDivideByZero: false)
      ).int64Value)
  }
}
struct Invoice: Codable, Identifiable {
  var id = UUID()
  var number: String
  var kind: String
  var date: Date
  var party: UUID
  var nominal: UUID
  var lines: [InvoiceLine]
  var note: String
  var taxes: [TaxCharge]? = nil
  var subtotalPaise: Int64 { lines.reduce(0) { $0 + $1.totalPaise } }
  var totalPaise: Int64 { subtotalPaise + taxPaise }
}
enum BookError: LocalizedError {
  case invalid(String)
  var errorDescription: String? {
    switch self {
    case .invalid(let message): return message
    }
  }
}
extension Books {
  func availableStock(_ id: UUID) -> Double {
    (stock.first { $0.id == id }?.opening ?? 0)
      + movements.filter { $0.item == id }.reduce(0) { $0 + $1.quantity }
  }
  mutating func postInvoice(_ invoice: Invoice) throws {
    guard ["Sale", "Purchase"].contains(invoice.kind),
      !invoice.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !invoices.contains(where: { $0.number.caseInsensitiveCompare(invoice.number) == .orderedSame }
      ),
      !invoice.lines.isEmpty, invoice.lines.count <= 1000, invoice.party != invoice.nominal,
      let party = ledgers.first(where: { $0.id == invoice.party }),
      ["Asset", "Liability"].contains(party.group),
      let nominal = ledgers.first(where: { $0.id == invoice.nominal }),
      nominal.group == (invoice.kind == "Sale" ? "Income" : "Expense")
    else {
      throw BookError.invalid(
        "Use a unique invoice number, a cash/customer/supplier ledger and the appropriate income or expense ledger."
      )
    }
    var quantities: [UUID: Double] = [:]
    for line in invoice.lines {
      guard stock.contains(where: { $0.id == line.item }), line.quantity.isFinite,
        line.quantity > 0, line.quantity <= 1_000_000,
        line.ratePaise > 0, line.ratePaise <= 100_000_000_000
      else {
        throw BookError.invalid(
          "Each line needs an item, a positive quantity and a positive rate within supported limits."
        )
      }
      quantities[line.item, default: 0] += line.quantity
    }
    let total = invoice.lines.reduce(Decimal(0)) { $0 + Decimal($1.totalPaise) }
    guard total > 0, total <= 900_000_000_000_000 else {
      throw BookError.invalid("Invoice total is outside supported limits.")
    }
    if invoice.kind == "Sale" {
      for (id, quantity) in quantities where quantity > availableStock(id) + 0.0000001 {
        throw BookError.invalid(
          "Insufficient stock for \(stock.first { $0.id == id }?.name ?? "item").")
      }
    }
    guard invoice.lines.count <= 1000 else {
      throw BookError.invalid("An invoice supports up to 1,000 lines.")
    }
    try validateTaxes(invoice)
    let amount = Double(invoice.subtotalPaise) / 100
    vouchers.append(
      Voucher(
        date: invoice.date, debit: invoice.kind == "Sale" ? invoice.party : invoice.nominal,
        credit: invoice.kind == "Sale" ? invoice.nominal : invoice.party, amount: amount,
        narration: "\(invoice.kind) \(invoice.number) · \(invoice.note)"))
    for tax in invoice.taxes ?? [] where invoice.taxAmount(tax) > 0 {
      vouchers.append(
        Voucher(
          date: invoice.date, debit: invoice.kind == "Sale" ? invoice.party : tax.ledger,
          credit: invoice.kind == "Sale" ? tax.ledger : invoice.party,
          amount: Double(invoice.taxAmount(tax)) / 100,
          narration: "Tax \(tax.name) · \(invoice.number)"))
    }
    for line in invoice.lines {
      movements.append(
        StockMovement(
          item: line.item, date: invoice.date,
          quantity: (invoice.kind == "Sale" ? -1 : 1) * line.quantity,
          note: "\(invoice.kind) \(invoice.number)",
          costPaise: invoice.kind == "Purchase" ? line.ratePaise : nil))
    }
    invoices.append(invoice)
  }
}
extension Books {
  func validate() throws {
    try validateBusiness()
    try validateDocuments()
    let ledgerIDs = Set(ledgers.map(\.id))
    let stockIDs = Set(stock.map(\.id))
    guard !company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      ledgerIDs.count == ledgers.count, stockIDs.count == stock.count,
      ledgers.allSatisfy({
        !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && ["Asset", "Liability", "Equity", "Income", "Expense"].contains($0.group)
      }),
      stock.allSatisfy({
        !$0.name.isEmpty && !$0.unit.isEmpty && $0.opening.isFinite && $0.opening >= 0
          && $0.opening <= 1_000_000_000 && $0.rate.isFinite && $0.rate >= 0
          && $0.rate <= 1_000_000_000
      }),
      vouchers.allSatisfy({
        ledgerIDs.contains($0.debit) && ledgerIDs.contains($0.credit) && $0.debit != $0.credit
          && $0.amount.isFinite && $0.amount > 0 && $0.amount <= 9_000_000_000_000
      }),
      movements.allSatisfy({
        stockIDs.contains($0.item) && $0.quantity.isFinite && abs($0.quantity) <= 1_000_000_000
      }),
      Set(invoices.map(\.id)).count == invoices.count,
      Set(invoices.map { $0.number.lowercased() }).count == invoices.count
    else { throw BookError.invalid("Books contain invalid or duplicate records.") }
    for invoice in invoices {
      guard ["Sale", "Purchase"].contains(invoice.kind), !invoice.number.isEmpty,
        ledgerIDs.contains(invoice.party), ledgerIDs.contains(invoice.nominal),
        invoice.party != invoice.nominal,
        !invoice.lines.isEmpty, invoice.lines.count <= 1000,
        invoice.lines.allSatisfy({
          stockIDs.contains($0.item) && $0.quantity.isFinite && abs($0.quantity) <= 1_000_000_000
            && $0.quantity > 0 && $0.quantity <= 1_000_000 && $0.ratePaise > 0
            && $0.ratePaise <= 100_000_000_000
        })
      else { throw BookError.invalid("An invoice contains invalid references or amounts.") }
      let total = invoice.lines.reduce(Decimal(0)) { $0 + Decimal($1.totalPaise) }
      guard total > 0 && total <= 900_000_000_000_000 else {
        throw BookError.invalid("Invalid invoice total.")
      }
      try validateTaxes(invoice)
    }
  }
}

extension Books {
  func validateTaxes(_ invoice: Invoice) throws {
    let taxes = invoice.taxes ?? []
    guard taxes.count <= 5,
      taxes.allSatisfy({ tax in
        !tax.name.isEmpty && tax.basisPoints > 0 && tax.basisPoints <= 10000
          && tax.ledger != invoice.party && tax.ledger != invoice.nominal
          && ledgers.contains {
            $0.id == tax.ledger && $0.group == (invoice.kind == "Sale" ? "Liability" : "Asset")
          }
      }), taxes.reduce(0, { $0 + $1.basisPoints }) <= 10000
    else {
      throw BookError.invalid(
        "Tax charges need a name, rates totalling at most 100%, and separate output-liability or input-asset ledgers."
      )
    }
  }
}
