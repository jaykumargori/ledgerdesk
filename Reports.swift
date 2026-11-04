import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StatementRow: Identifiable {
  var id: UUID
  var date: Date
  var narration: String
  var debit: Double
  var credit: Double
  var balance: Double
}
struct StatementView: View {
  @ObservedObject var store: Store
  @State private var ledger: UUID?
  @State private var from = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
  @State private var to = Date()
  var beginning: Date { Calendar.current.startOfDay(for: from) }
  var ending: Date {
    Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to))!
  }
  var transactions: [Voucher] {
    store.books.vouchers.enumerated().filter {
      $0.element.debit == ledger || $0.element.credit == ledger
    }.sorted { a, b in
      a.element.date == b.element.date ? a.offset < b.offset : a.element.date < b.element.date
    }.map(\.element)
  }
  var opening: Double {
    transactions.filter { $0.date < beginning }.reduce(0) {
      $0 + ($1.debit == ledger ? $1.amount : -$1.amount)
    }
  }
  var rows: [StatementRow] {
    var running = opening
    return transactions.filter { $0.date >= beginning && $0.date < ending }.map { v in
      let dr = v.debit == ledger ? v.amount : 0
      let cr = v.credit == ledger ? v.amount : 0
      running += dr - cr
      return StatementRow(
        id: v.id, date: v.date, narration: v.narration, debit: dr, credit: cr, balance: running)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Picker("Ledger", selection: $ledger) {
          Text("Select ledger").tag(Optional<UUID>.none)
          ForEach(store.books.ledgers) { Text($0.name).tag(Optional($0.id)) }
        }
        DatePicker("From", selection: $from, displayedComponents: .date)
        DatePicker("To", selection: $to, displayedComponents: .date)
        Button("Export CSV") { export() }.disabled(ledger == nil || from > to)
      }
      if from > to {
        Text("The start date must precede the end date.").foregroundStyle(.red)
      } else if ledger == nil {
        ContentUnavailableView(
          "Choose a ledger", systemImage: "book",
          description: Text("Review its vouchers and running balance for a period."))
      } else {
        Text("Opening balance: \(opening.formatted(currency))").bold()
        Table(rows) {
          TableColumn("Date") { r in Text(r.date, style: .date) }
          TableColumn("Narration", value: \.narration)
          TableColumn("Debit") { r in Text(r.debit.formatted(currency)) }
          TableColumn("Credit") { r in Text(r.credit.formatted(currency)) }
          TableColumn("Balance") { r in Text(r.balance.formatted(currency)) }
        }
        Text("Closing balance: \((rows.last?.balance ?? opening).formatted(currency))").bold()
        Text("Positive balances are debit; negative balances are credit.").foregroundStyle(
          .secondary
        ).font(.caption)
      }
    }
  }
  func export() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = "ledger-statement.csv"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    func quoted(_ s: String) -> String {
      "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    let header = "Date,Narration,Debit,Credit,Balance\r\n"
    let content =
      header
      + rows.map { r in
        [
          quoted(r.date.formatted(.iso8601.year().month().day())), quoted(r.narration),
          String(r.debit), String(r.credit), String(r.balance),
        ].joined(separator: ",")
      }.joined(separator: "\r\n")
    do { try content.write(to: url, atomically: true, encoding: .utf8) } catch {
      store.error = error.localizedDescription
    }
  }
}
struct BalanceSheetView: View {
  @ObservedObject var store: Store
  func total(_ group: String) -> Double {
    store.books.ledgers.filter { $0.group == group }.reduce(0) { $0 + store.balance($1.id) }
  }
  var result: Double { -total("Income") - total("Expense") }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("All-time balances from posted accounting vouchers").foregroundStyle(.secondary)
      HStack(alignment: .top, spacing: 30) {
        column("Assets", groups: ["Asset"], sign: 1)
        column("Liabilities & equity", groups: ["Liability", "Equity"], sign: -1)
      }
      Divider()
      HStack {
        Text("Assets: \(total("Asset").formatted(currency))").bold()
        Spacer()
        Text(
          "Liabilities, equity & result: \((-total("Liability")-total("Equity")+result).formatted(currency))"
        ).bold()
      }
      Text(
        "Stock records alone do not post opening inventory or valuation adjustments to the accounts."
      ).font(.caption).foregroundStyle(.secondary)
    }
  }
  func column(_ title: String, groups: [String], sign: Double) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title).font(.title2.bold())
      ForEach(store.books.ledgers.filter { groups.contains($0.group) }) { a in
        HStack {
          Text(a.name)
          Spacer()
          Text((sign * store.balance(a.id)).formatted(currency))
        }
      }
      if sign < 0 {
        HStack {
          Text("Current profit / loss")
          Spacer()
          Text(result.formatted(currency))
        }
      }
    }.padding().frame(maxWidth: .infinity, alignment: .topLeading).background(
      .quaternary, in: RoundedRectangle(cornerRadius: 8))
  }
}
