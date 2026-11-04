import SwiftUI

struct TipCard: Identifiable {
  var id: String
  var title: String
  var text: String
  var target: String
}
struct TryNowTile: View {
  let navigate: (String) -> Void
  @AppStorage("showTryNow") private var enabled = true
  @AppStorage("hiddenTryNow") private var hidden = ""
  @State private var collapsed = false
  @State private var index = 0
  static let cards = [
    TipCard(
      id: "bank", title: "Reconcile your bank statement",
      text:
        "Import a bank statement and compare it with your book entries. Review matched and unmatched transactions in one place.",
      target: "Banking"),
    TipCard(
      id: "invoice", title: "Record sales and purchases",
      text:
        "Create an item invoice to record the transaction and stock movement together. Review the invoice before printing.",
      target: "Invoices"),
    TipCard(
      id: "stock", title: "Explore stock valuation",
      text:
        "Compare FIFO and moving-average costs for your stock items, and review receipts with missing acquisition costs.",
      target: "Stock Valuation"),
  ]
  var cards: [TipCard] {
    Self.cards.filter { !hidden.split(separator: "|").contains(Substring($0.id)) }
  }
  var body: some View {
    if enabled, !cards.isEmpty {
      let card = cards[index % cards.count]
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Image(systemName: "arrow.right.circle")
          Text("Try Now").bold()
          Spacer()
          Button {
            collapsed.toggle()
          } label: {
            Image(systemName: collapsed ? "plus" : "minus")
          }.help(collapsed ? "Expand messages" : "Minimise messages")
        }.padding(.horizontal, 8).frame(height: 23).background(Prime.blue).foregroundStyle(.white)
        if !collapsed {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
              Text(card.title).bold()
              Text(card.text).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 5)
            Button {
              hidden += "|" + card.id
              index = 0
            } label: {
              Image(systemName: "nosign")
            }.foregroundStyle(Prime.label).help("Hide this message")
          }.padding(9).frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
          HStack(spacing: 4) {
            Button {
              index = (index + cards.count - 1) % cards.count
            } label: {
              Image(systemName: "arrowtriangle.left.fill")
            }
            Text("(\(index%cards.count+1) of \(cards.count))").foregroundStyle(.secondary)
            Button {
              index = (index + 1) % cards.count
            } label: {
              Image(systemName: "arrowtriangle.right.fill")
            }
            Spacer()
            Button {
              navigate(card.target)
            } label: {
              Text("F7: Know More").frame(width: 145, alignment: .leading).padding(4).background(
                .white
              ).overlay(Rectangle().stroke(Prime.line, lineWidth: 1))
            }
          }.padding(.horizontal, 8).padding(.bottom, 6)
        }
      }.buttonStyle(.plain).font(.system(size: 12)).background(Prime.pale).overlay(
        Rectangle().stroke(Prime.line, lineWidth: 1))
    }
  }
}
struct FindResult: Identifiable {
  var id: String
  var kind: String
  var title: String
  var detail: String
  var target: String
  var invoice: Invoice?
}
struct SmartFindView: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  @Binding var query: String
  let navigate: (String) -> Void
  @State private var invoice: Invoice?
  @FocusState private var focused: Bool
  var results: [FindResult] {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
    let ledgers = store.books.ledgers.map {
      FindResult(
        id: $0.id.uuidString, kind: "Ledger", title: $0.name,
        detail: "\($0.group) · \(store.balance($0.id).formatted(currency))", target: "Ledgers")
    }
    let stock = store.books.stock.map {
      FindResult(
        id: $0.id.uuidString, kind: "Stock Item", title: $0.name,
        detail: "\(store.stockBalance($0.id).formatted()) \($0.unit)", target: "Inventory")
    }
    let vouchers = store.books.vouchers.map {
      FindResult(
        id: $0.id.uuidString, kind: "Voucher", title: $0.narration,
        detail:
          "\($0.date.formatted(date:.abbreviated,time:.omitted)) · \($0.amount.formatted(currency))",
        target: "Vouchers")
    }
    let invoices = store.books.invoices.map {
      FindResult(
        id: $0.id.uuidString, kind: "Invoice", title: $0.number,
        detail: "\($0.kind) · \((Double($0.totalPaise)/100).formatted(currency))",
        target: "Invoices", invoice: $0)
    }
    return (ledgers + stock + vouchers + invoices).filter {
      ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(query)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("SmartFind").bold()
        Spacer()
        Button("Close") { dismiss() }
      }.padding(10).background(Prime.blue).foregroundStyle(.white)
      TextField("Find details entered in masters and transactions", text: $query).focused($focused)
        .textFieldStyle(.plain).padding(12).background(.white)
      HStack {
        Text("Search Results").bold()
        Spacer()
        Text("\(results.count) results")
      }.padding(10).background(Prime.pale)
      if query.isEmpty {
        Text("Enter a name, invoice number, amount or narration.").foregroundStyle(.secondary)
          .padding(16)
        Spacer()
      } else {
        List(results) { result in
          Button {
            if let i = result.invoice {
              invoice = i
            } else {
              navigate(result.target)
              dismiss()
            }
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(result.title.isEmpty ? "Journal entry" : result.title).bold()
                Text(result.detail).foregroundStyle(.secondary)
              }
              Spacer()
              Text(result.kind).foregroundStyle(Prime.label)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
          }.buttonStyle(.plain)
        }
      }
    }.frame(width: 700, height: 500).font(Prime.font).background(.white).environment(
      \.colorScheme, .light
    ).onAppear { focused = true }.sheet(item: $invoice) { i in
      InvoiceDetail(store: store, invoice: i)
    }
  }
}
struct PeriodView: View {
  @Environment(\.dismiss) var dismiss
  @Binding var start: Date
  @Binding var end: Date
  @State private var from = Date()
  @State private var to = Date()
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Change Period").font(.headline)
      DatePicker("From", selection: $from, displayedComponents: .date)
      DatePicker("To", selection: $to, displayedComponents: .date)
      Text("Sets the period shown on Gateway. Reports retain their own date controls.").font(
        .caption
      ).foregroundStyle(.secondary)
      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Button("Accept") {
          start = from
          end = to
          dismiss()
        }.disabled(from > to).keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width: 400).onAppear {
      from = start
      to = end
    }
  }
}
struct SelectCompanyView: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  let details: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Select Company").bold().foregroundStyle(.white).padding(9).frame(
        maxWidth: .infinity, alignment: .leading
      ).background(Prime.blue)
      Text("Name of Company").foregroundStyle(Prime.label).padding(12)
      Button(store.books.company) { dismiss() }.buttonStyle(PrimeButton(selected: true))
      HStack {
        Button("Company details") {
          details()
          dismiss()
        }
        Spacer()
        Button("Close") { dismiss() }
      }.padding(12)
    }.font(Prime.font).frame(width: 440).background(Prime.pale)
  }
}
struct DisplaySettingsView: View {
  @Environment(\.dismiss) var dismiss
  @AppStorage("showTryNow") private var showTips = true
  @AppStorage("hiddenTryNow") private var hidden = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Display Settings").font(.headline)
      Toggle("Show the Try Now tile on Gateway", isOn: $showTips)
      Button("Show hidden messages again") { hidden = "" }
      Button("Accept") { dismiss() }.keyboardShortcut(.defaultAction)
    }.padding(24).frame(width: 440)
  }
}
struct FeatureOverview: View {
  let navigate: (String) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Business overview").font(.headline)
      HStack {
        tile("Balance Sheet", "Assets, liabilities and equity")
        tile("Profit & Loss", "Income and expense balances")
      }
      HStack {
        tile("Stock Valuation", "FIFO and moving-average costs")
        tile("Banking", "Statement reconciliation")
      }
      Spacer()
    }.padding(16)
  }
  func tile(_ target: String, _ description: String) -> some View {
    Button {
      navigate(target)
    } label: {
      VStack(alignment: .leading, spacing: 12) {
        Text(target).bold()
        Text(description).foregroundStyle(.secondary)
      }.padding(20).frame(maxWidth: .infinity, minHeight: 110, alignment: .leading).background(
        Prime.pale
      ).overlay(Rectangle().stroke(Prime.line, lineWidth: 1))
    }.buttonStyle(.plain)
  }
}
enum FiscalCalendar {
  static func start(_ date: Date) -> Date {
    let calendar = Calendar.current
    let year =
      calendar.component(.year, from: date) - (calendar.component(.month, from: date) < 4 ? 1 : 0)
    return calendar.date(from: DateComponents(year: year, month: 4, day: 1))!
  }
  static func end(_ date: Date) -> Date {
    Calendar.current.date(
      byAdding: .day, value: -1,
      to: Calendar.current.date(byAdding: .year, value: 1, to: start(date))!)!
  }
}
struct TryNowReport: View {
  let navigate: (String) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Explore available features").font(.headline).padding(12)
      ForEach(TryNowTile.cards) { card in
        Button {
          navigate(card.target)
        } label: {
          VStack(alignment: .leading, spacing: 8) {
            Text(card.title).bold()
            Text(card.text).foregroundStyle(.secondary)
          }.padding(16).frame(maxWidth: .infinity, alignment: .leading).overlay(alignment: .bottom)
          { Prime.line.frame(height: 1) }
        }.buttonStyle(.plain)
      }
      Spacer()
    }.font(Prime.font)
  }
}
