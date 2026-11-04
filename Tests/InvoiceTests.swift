import Foundation

@main struct InvoiceTests {
  static func main() throws {
    var b = Books()
    let item = StockItem(name: "Widget", unit: "Nos", opening: 10, rate: 25)
    b.stock.append(item)
    let cash = b.ledgers.first { $0.name == "Cash" }!.id
    let sales = b.ledgers.first { $0.name == "Sales" }!.id
    let purchases = b.ledgers.first { $0.name == "Purchases" }!.id
    let sale = Invoice(
      number: "S-1", kind: "Sale", date: Date(), party: cash, nominal: sales,
      lines: [InvoiceLine(item: item.id, quantity: 2, ratePaise: 12550)], note: "Test")
    try b.postInvoice(sale)
    precondition(b.invoices.count == 1 && b.vouchers.count == 1 && b.movements.count == 1)
    precondition(
      b.availableStock(item.id) == 8 && b.vouchers[0].amount == 251 && b.vouchers[0].debit == cash
        && b.vouchers[0].credit == sales)
    func rejects(_ candidate: Invoice, _ books: Books) {
      var copy = books
      do {
        try copy.postInvoice(candidate)
        fatalError("Invalid invoice accepted")
      } catch {
        precondition(
          copy.invoices.count == books.invoices.count && copy.vouchers.count == books.vouchers.count
            && copy.movements.count == books.movements.count)
      }
    }
    rejects(sale, b)
    var tooMuch = sale
    tooMuch.number = "S-2"
    tooMuch.lines = [
      InvoiceLine(item: item.id, quantity: 5, ratePaise: 100),
      InvoiceLine(item: item.id, quantity: 5, ratePaise: 100),
    ]
    rejects(tooMuch, b)
    var invalid = sale
    invalid.number = "S-3"
    invalid.lines[0].quantity = Double.nan
    rejects(invalid, b)
    invalid = sale
    invalid.number = "S-4"
    invalid.nominal = purchases
    rejects(invalid, b)
    let purchase = Invoice(
      number: "P-1", kind: "Purchase", date: Date(), party: cash, nominal: purchases,
      lines: [InvoiceLine(item: item.id, quantity: 3, ratePaise: 1000)], note: "")
    try b.postInvoice(purchase)
    precondition(
      b.availableStock(item.id) == 11 && b.vouchers[1].debit == purchases
        && b.vouchers[1].credit == cash)
    try b.validate()
    var broken = b
    broken.movements[0].item = UUID()
    do {
      try broken.validate()
      fatalError("Invalid stock reference accepted")
    } catch {}
    let restored = try JSONDecoder().decode(Books.self, from: JSONEncoder().encode(b))
    precondition(restored.invoices.count == 2 && restored.availableStock(item.id) == 11)
    let legacy = Data("{\"company\":\"Legacy\",\"ledgers\":[],\"vouchers\":[]}".utf8)
    let old = try JSONDecoder().decode(Books.self, from: legacy)
    precondition(old.invoices.isEmpty && old.movements.isEmpty)
    let half = InvoiceLine(item: item.id, quantity: 0.5, ratePaise: 101)
    precondition(half.totalPaise == 51)
    print(
      "PASS: sales posting, purchases posting, stock, duplicate rejection, aggregated stock check, invalid numbers, ledger validation, persistence, legacy migration, paise rounding"
    )
  }
}
