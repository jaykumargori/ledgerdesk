import Foundation

@main struct BusinessTests {
  static func main() throws {
    var books = Books()
    let bank = Ledger(name: "Bank QA", group: "Asset")
    let output = Ledger(name: "Output GST", group: "Liability")
    let input = Ledger(name: "Input GST", group: "Asset")
    let salary = Ledger(name: "Salary", group: "Expense")
    let payable = Ledger(name: "Salary Payable", group: "Liability")
    let deduction = Ledger(name: "Deductions Payable", group: "Liability")
    books.ledgers += [bank, output, input, salary, payable, deduction]
    let item = StockItem(name: "Test widget", unit: "Nos", opening: 10, rate: 10)
    books.stock = [item]
    let purchases = books.ledgers.first { $0.name == "Purchases" }!.id
    let sales = books.ledgers.first { $0.name == "Sales" }!.id
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let receipt = Invoice(
      number: "P-101", kind: "Purchase", date: date, party: bank.id, nominal: purchases,
      lines: [InvoiceLine(item: item.id, quantity: 10, ratePaise: 2000)], note: "",
      taxes: [TaxCharge(name: "Input", basisPoints: 1800, ledger: input.id)])
    try books.postInvoice(receipt)
    precondition(
      receipt.subtotalPaise == 20000 && receipt.taxPaise == 3600 && receipt.totalPaise == 23600)
    let sale = Invoice(
      number: "S-101", kind: "Sale", date: date.addingTimeInterval(60), party: bank.id,
      nominal: sales, lines: [InvoiceLine(item: item.id, quantity: 5, ratePaise: 3000)], note: "",
      taxes: [
        TaxCharge(name: "CGST", basisPoints: 900, ledger: output.id),
        TaxCharge(name: "SGST", basisPoints: 900, ledger: output.id),
      ])
    try books.postInvoice(sale)
    precondition(sale.totalPaise == 17700 && books.vouchers.count == 5)
    func balance(_ id: UUID) -> Double {
      books.vouchers.reduce(0) {
        $0 + ($1.debit == id ? $1.amount : 0) - ($1.credit == id ? $1.amount : 0)
      }
    }
    precondition(balance(bank.id) == -59 && balance(input.id) == 36 && balance(output.id) == -27)
    let average = try books.valuation(
      item: item, method: "Average", through: date.addingTimeInterval(120))
    let fifo = try books.valuation(
      item: item, method: "FIFO", through: date.addingTimeInterval(120))
    precondition(
      average.quantity == 15 && average.value == 225 && fifo.value == 250
        && average.assumedCosts == 0)
    let before = try books.valuation(
      item: item, method: "FIFO", through: date.addingTimeInterval(-1))
    precondition(before.quantity == 10 && before.value == 100)
    var wrong = sale
    wrong.number = "Invalid"
    wrong.taxes = [TaxCharge(name: "bad", basisPoints: 1800, ledger: salary.id)]
    let count = books.vouchers.count
    do {
      try books.postInvoice(wrong)
      fatalError("Invalid tax ledger accepted")
    } catch { precondition(books.vouchers.count == count) }
    books.employees = [
      Employee(name: "QA Employee", basic: 1_000_000, allowance: 200000, deduction: 50000)
    ]
    try books.postPayroll(
      period: "2026-11", date: date, expense: salary.id, payable: payable.id,
      deductions: deduction.id)
    precondition(
      books.payruns[0].net == 1_150_000 && balance(salary.id) == 12000
        && balance(payable.id) == -11500 && balance(deduction.id) == -500)
    do {
      try books.postPayroll(
        period: "2026-11", date: date, expense: salary.id, payable: payable.id,
        deductions: deduction.id)
      fatalError("Duplicate payroll accepted")
    } catch {}
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    let csv =
      "id,date,description,amount\r\nB1,\(formatter.string(from:date)),\"Purchase, widgets\",-200.00\r\nB2,\(formatter.string(from:date)),Input tax,-36.00\r\nB3,\(formatter.string(from:date)),Sale,150.00\r\n"
    try books.importStatement(csv, bank: bank.id)
    try books.autoMatch(bank: bank.id)
    precondition(books.bankLines.count == 3 && books.bankLines.allSatisfy { $0.voucher != nil })
    let bankCount = books.bankLines.count
    do {
      try books.importStatement(csv, bank: bank.id)
      fatalError("Duplicate CSV accepted")
    } catch { precondition(books.bankLines.count == bankCount) }
    try books.matchBank(line: books.bankLines[0].id, voucher: nil)
    precondition(books.bankLines[0].voucher == nil)
    do {
      try books.matchBank(line: books.bankLines[0].id, voucher: books.bankLines[1].voucher)
      fatalError("Invalid match accepted")
    } catch {}
    let parsed = try CSV.read(
      "id,date,description,amount\nQ,2026-11-01,\"Two \"\"quoted\"\"\nlines\",1.00\n")
    precondition(parsed[1][2] == "Two \"quoted\"\nlines")
    try books.validate()
    let restored = try JSONDecoder().decode(Books.self, from: JSONEncoder().encode(books))
    try restored.validate()
    precondition(
      restored.bankLines.count == 3 && restored.payruns.count == 1
        && restored.invoices[1].taxPaise == 2700)
    var ambiguous = Books()
    ambiguous.ledgers.append(bank)
    ambiguous.vouchers = [
      Voucher(date: date, debit: bank.id, credit: sales, amount: 10, narration: "A"),
      Voucher(date: date, debit: bank.id, credit: sales, amount: 10, narration: "B"),
    ]
    ambiguous.bankLines = [
      BankLine(bank: bank.id, reference: "amb", date: date, description: "Ambiguous", amount: 1000)
    ]
    try ambiguous.autoMatch(bank: bank.id)
    precondition(ambiguous.bankLines[0].voucher == nil)
    let total = books.ledgers.reduce(0) { $0 + balance($1.id) }
    precondition(abs(total) < 0.00001)
    if CommandLine.arguments.count > 1 {
      let encoder = JSONEncoder()
      encoder.outputFormatting = .prettyPrinted
      try encoder.encode(books).write(
        to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
    }
    print(
      "PASS: split/input taxes; ledger balances; FIFO and moving average; dated valuation; payroll and duplicates; quoted CSV; signed matches; ambiguous matches; unmatched handling; schema round-trip; overall accounting balance"
    )
  }
}
