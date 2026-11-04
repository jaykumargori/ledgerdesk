import AppKit
import SwiftUI
import UniformTypeIdentifiers

func enteredMoney(_ text: String) throws -> Int64 {
  guard text.range(of: "^[0-9]+(?:\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
    let number = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
    number <= 1_000_000_000
  else { throw BookError.invalid("Enter a non-negative amount with up to two decimal places.") }
  return paise(number * 100)
}
struct ValuationRow: Identifiable {
  var id: UUID
  var name: String
  var quantity: Double
  var value: Double
  var assumed: Int
  var issue: String
}
struct ValuationView: View {
  @ObservedObject var store: Store
  @State private var method = "Average"
  @State private var date = Date()
  var rows: [ValuationRow] {
    let end = Calendar.current.date(
      byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))!.addingTimeInterval(
        -0.001)
    return store.books.stock.map { item in
      do {
        let result = try store.books.valuation(item: item, method: method, through: end)
        return ValuationRow(
          id: item.id, name: item.name, quantity: result.quantity,
          value: NSDecimalNumber(decimal: result.value).doubleValue, assumed: result.assumedCosts,
          issue: "")
      } catch {
        return ValuationRow(
          id: item.id, name: item.name, quantity: 0, value: 0, assumed: 0,
          issue: error.localizedDescription)
      }
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Picker("Method", selection: $method) {
          Text("Moving average").tag("Average")
          Text("FIFO").tag("FIFO")
        }
        DatePicker("Through", selection: $date, displayedComponents: .date)
      }
      Text(
        "Opening stock precedes all movements. Receipts without a cost use the opening rate and are flagged below. Valuation is a report; it does not post accounting adjustments."
      ).foregroundStyle(.secondary)
      Table(rows) {
        TableColumn("Item", value: \.name)
        TableColumn("Quantity") { r in Text(r.quantity.formatted()) }
        TableColumn("Value") { r in
          Text(r.issue.isEmpty ? r.value.formatted(currency) : "Unavailable")
        }
        TableColumn("Notes") { r in
          Text(
            r.issue.isEmpty
              ? (r.assumed > 0 ? "\(r.assumed) receipts use opening rate" : "") : r.issue
          ).foregroundStyle(r.issue.isEmpty ? Color.secondary : Color.red)
        }
      }
      Text(
        "Valued items total: \(rows.filter{$0.issue.isEmpty}.reduce(0){$0+$1.value}.formatted(currency))"
      ).bold()
    }
  }
}
struct PayrollView: View {
  @ObservedObject var store: Store
  @State private var employeeSheet = false
  @State private var runSheet = false
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Employees & pay runs").font(.headline)
        Spacer()
        Button("New employee") { employeeSheet = true }
        Button("Post monthly payroll") { runSheet = true }.disabled(store.books.employees.isEmpty)
      }
      Text(
        "Configured earnings and deductions only. Posting accrues salary and deduction liabilities; it does not pay employees or calculate statutory deductions."
      ).foregroundStyle(.secondary)
      Table(store.books.employees) {
        TableColumn("Employee", value: \.name)
        TableColumn("Basic") { e in Text((Double(e.basic) / 100).formatted(currency)) }
        TableColumn("Allowance") { e in Text((Double(e.allowance) / 100).formatted(currency)) }
        TableColumn("Deductions") { e in Text((Double(e.deduction) / 100).formatted(currency)) }
      }
      Text("Posted payroll").font(.headline)
      Table(store.books.payruns.reversed()) {
        TableColumn("Period", value: \.period)
        TableColumn("Employee", value: \.name)
        TableColumn("Gross") { r in Text((Double(r.gross) / 100).formatted(currency)) }
        TableColumn("Deductions") { r in Text((Double(r.deduction) / 100).formatted(currency)) }
        TableColumn("Net payable") { r in Text((Double(r.net) / 100).formatted(currency)) }
      }
    }.sheet(isPresented: $employeeSheet) { EmployeeForm(store: store) }.sheet(
      isPresented: $runSheet
    ) { PayrollForm(store: store) }
  }
}
struct EmployeeForm: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  @State private var name = ""
  @State private var basic = ""
  @State private var allowance = "0"
  @State private var deduction = "0"
  @State private var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Employee").font(.title2.bold())
      TextField("Name", text: $name)
      TextField("Monthly basic (₹)", text: $basic)
      TextField("Monthly allowance (₹)", text: $allowance)
      TextField("Monthly deduction (₹)", text: $deduction)
      Text(error).foregroundStyle(.red)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Save") {
          do {
            let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty,
              !store.books.employees.contains(where: {
                $0.name.localizedCaseInsensitiveCompare(n) == .orderedSame
              })
            else { throw BookError.invalid("Enter a unique employee name.") }
            let employee = Employee(
              name: n, basic: try enteredMoney(basic), allowance: try enteredMoney(allowance),
              deduction: try enteredMoney(deduction))
            guard employee.basic + employee.allowance > 0 else {
              throw BookError.invalid("Gross earnings must be positive.")
            }
            try store.transaction { $0.employees.append(employee) }
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.buttonStyle(.borderedProminent)
      }
    }.padding(24).frame(width: 420)
  }
}
struct PayrollForm: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  @State private var period = ""
  @State private var date = Date()
  @State private var expense: UUID?
  @State private var payable: UUID?
  @State private var deductions: UUID?
  @State private var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Post monthly payroll").font(.title2.bold())
      TextField("Period, YYYY-MM", text: $period)
      DatePicker("Posting date", selection: $date, displayedComponents: .date)
      picker("Salary expense", selection: $expense, group: "Expense")
      picker("Salary payable", selection: $payable, group: "Liability")
      picker("Deductions payable", selection: $deductions, group: "Liability")
      Text("Posts all employees for the period. The same period cannot be posted twice.")
        .foregroundStyle(.secondary)
      Text(error).foregroundStyle(.red)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Post payroll") {
          do {
            guard let e = expense, let p = payable, let d = deductions else {
              throw BookError.invalid("Select all three ledgers.")
            }
            try store.transaction {
              try $0.postPayroll(period: period, date: date, expense: e, payable: p, deductions: d)
            }
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.buttonStyle(.borderedProminent)
      }
    }.padding(24).frame(width: 470)
  }
  func picker(_ label: String, selection: Binding<UUID?>, group: String) -> some View {
    Picker(label, selection: selection) {
      Text("Select ledger").tag(Optional<UUID>.none)
      ForEach(store.books.ledgers.filter { $0.group == group }) {
        Text($0.name).tag(Optional($0.id))
      }
    }
  }
}
struct BankingView: View {
  @ObservedObject var store: Store
  @State private var bank: UUID?
  @State private var selected: BankLine?
  @State private var message = ""
  var lines: [BankLine] { store.books.bankLines.filter { $0.bank == bank } }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Picker("Bank ledger", selection: $bank) {
          Text("Select bank asset ledger").tag(Optional<UUID>.none)
          ForEach(store.books.ledgers.filter { $0.group == "Asset" }) {
            Text($0.name).tag(Optional($0.id))
          }
        }
        Button("Import CSV") { importCSV() }.disabled(bank == nil)
        Button("Match unique entries") {
          do {
            if let bank {
              try store.transaction { try $0.autoMatch(bank: bank) }
              message = "Matched unique transactions with the same amount and date."
            }
          } catch { message = error.localizedDescription }
        }.disabled(bank == nil)
      }
      Text(
        "CSV columns: id,date,description,amount. Dates: YYYY-MM-DD. Positive amounts are receipts; negative amounts are payments. Click a statement row to match or unmatch it."
      ).foregroundStyle(.secondary)
      if bank == nil {
        ContentUnavailableView("Select a bank", systemImage: "building.columns")
      } else {
        List(lines) { line in
          Button {
            selected = line
          } label: {
            HStack {
              Text(line.date, style: .date).frame(width: 100)
              Text(line.reference).frame(width: 100)
              Text(line.description)
              Spacer()
              Text((Double(line.amount) / 100).formatted(currency))
              Text(line.voucher == nil ? "Unmatched" : "Matched").foregroundStyle(
                line.voucher == nil ? Color.secondary : Color.green)
            }
          }.buttonStyle(.plain)
        }
        HStack {
          Text("Statement rows: \(lines.count)")
          Text("Matched: \(lines.filter{$0.voucher != nil}.count)")
          Text("Unmatched: \(lines.filter{$0.voucher == nil}.count)")
        }
        Text("Unmatched book entries").font(.headline)
        List(unmatchedBookEntries) { v in
          HStack {
            Text(v.date, style: .date)
            Text(v.narration)
            Spacer()
            Text((Double(store.books.bankAmount(v, bank: bank!)) / 100).formatted(currency))
          }
        }.frame(maxHeight: 160)
      }
      Text(message).foregroundStyle(.secondary)
    }.sheet(item: $selected) { line in BankMatchForm(store: store, line: line) }
  }
  var unmatchedBookEntries: [Voucher] {
    guard let bank else { return [] }
    let matched = Set(lines.compactMap(\.voucher))
    return store.books.vouchers.filter {
      ($0.debit == bank || $0.credit == bank) && !matched.contains($0.id)
    }
  }
  func importCSV() {
    guard let bank else { return }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.commaSeparatedText, .plainText]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let text = try String(contentsOf: url, encoding: .utf8)
      try store.transaction { try $0.importStatement(text, bank: bank) }
      message = "Statement imported."
    } catch { message = error.localizedDescription }
  }
}
struct BankMatchForm: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  let line: BankLine
  var suggested: UUID? = nil
  @State private var voucher: UUID?
  @State private var error = ""
  var candidates: [Voucher] {
    let used = Set(
      store.books.bankLines.filter { $0.bank == line.bank && $0.id != line.id }.compactMap(
        \.voucher))
    return store.books.vouchers.filter {
      store.books.bankAmount($0, bank: line.bank) == line.amount && !used.contains($0.id)
    }.sorted {
      abs($0.date.timeIntervalSince(line.date)) < abs($1.date.timeIntervalSince(line.date))
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Bank Reconciliation – Find Matches").bold().foregroundStyle(.white).padding(9).frame(
        maxWidth: .infinity, alignment: .leading
      ).background(Prime.blue)
      Text("Bank transaction").bold().padding(12)
      HStack {
        Text(line.date, style: .date)
        Text(line.description)
        Spacer()
        Text(bankMoney(Decimal(line.amount)))
      }.padding(12).background(Prime.pale)
      Text("Book transactions with the same signed amount").foregroundStyle(Prime.label).padding(12)
      ScrollView {
        VStack(spacing: 0) {
          ForEach(candidates) { candidate in
            Button {
              voucher = candidate.id
            } label: {
              HStack {
                Text(candidate.date, style: .date).frame(width: 100, alignment: .leading)
                Text(candidate.narration).frame(maxWidth: .infinity, alignment: .leading)
                Text(candidate.amount.formatted(currency)).frame(width: 120, alignment: .trailing)
              }.padding(10).contentShape(Rectangle())
            }.buttonStyle(.plain).background(voucher == candidate.id ? Prime.yellow : Color.clear)
          }
          if candidates.isEmpty {
            Text(
              "No matching book entries. Create a voucher from the bank entry if it is missing from your books."
            ).foregroundStyle(.secondary).padding(16)
          }
        }
      }.frame(height: 220)
      Text(error).foregroundStyle(.red).padding(.horizontal, 12)
      HStack {
        Button("Cancel") { dismiss() }
        Button("Unlink") {
          voucher = nil
          save()
        }.disabled(line.voucher == nil)
        Spacer()
        Button("Reconcile") { save() }.disabled(voucher == nil).keyboardShortcut(
          "a", modifiers: .control)
      }.padding(12).background(Prime.pale)
    }.font(Prime.font).frame(width: 760).background(.white).onAppear {
      voucher = line.voucher ?? suggested
    }
  }
  func save() {
    do {
      try store.transaction { try $0.matchBank(line: line.id, voucher: voucher) }
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
struct TaxSummaryView: View {
  @ObservedObject var store: Store
  @State private var from = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
  @State private var to = Date()
  var invoices: [Invoice] {
    let start = Calendar.current.startOfDay(for: from)
    let end = Calendar.current.date(
      byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to))!
    return store.books.invoices.filter {
      $0.date >= start && $0.date < end && !($0.taxes ?? []).isEmpty
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        DatePicker("From", selection: $from, displayedComponents: .date)
        DatePicker("To", selection: $to, displayedComponents: .date)
      }
      Text(
        "Tax postings from configured invoice charges. This summary does not determine credit eligibility, classify supplies or generate statutory returns."
      ).foregroundStyle(.secondary)
      Table(invoices) {
        TableColumn("Invoice", value: \.number)
        TableColumn("Type", value: \.kind)
        TableColumn("Taxable value") { i in
          Text((Double(i.subtotalPaise) / 100).formatted(currency))
        }
        TableColumn("Tax") { i in Text((Double(i.taxPaise) / 100).formatted(currency)) }
        TableColumn("Total") { i in Text((Double(i.totalPaise) / 100).formatted(currency)) }
      }
      Text(
        "Sales tax: \(total("Sale").formatted(currency))    Purchase tax: \(total("Purchase").formatted(currency))"
      ).bold()
    }
  }
  func total(_ kind: String) -> Double {
    invoices.filter { $0.kind == kind }.reduce(0) { $0 + Double($1.taxPaise) / 100 }
  }
}
