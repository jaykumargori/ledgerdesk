import AppKit
import SwiftUI

struct DraftTax: Identifiable {
  var id = UUID()
  var name = "GST"
  var rate = ""
  var ledger: UUID?
}
struct DraftLine: Identifiable {
  var id = UUID()
  var item: UUID?
  var quantity = "1"
  var rate = ""
}
struct InvoiceForm: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var store: Store
  var onClose: (() -> Void)? = nil
  var suppliedDate: Date
  @State private var kind = "Sale"
  @State private var number = ""
  @State private var date = Date()
  @State private var party: UUID?
  @State private var nominal: UUID?
  @State private var lines = [DraftLine()]
  @State private var note = ""
  @State private var error = ""
  @State private var taxes: [DraftTax] = []
  init(
    store: Store, date: Date = Date(), initialKind: String = "Sale", onClose: (() -> Void)? = nil
  ) {
    self.store = store
    self.onClose = onClose
    self.suppliedDate = date
    _date = State(initialValue: date)
    _kind = State(initialValue: initialKind)
  }
  func parsedLines() throws -> [InvoiceLine] {
    try lines.map { line in
      guard let item = line.item, let quantity = Double(line.quantity), quantity.isFinite,
        quantity > 0, quantity <= 1_000_000,
        line.rate.range(of: "^[0-9]+(?:\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
        let rate = Decimal(string: line.rate, locale: Locale(identifier: "en_US_POSIX")), rate > 0,
        rate <= 1_000_000_000
      else {
        throw BookError.invalid(
          "Each line needs an item, a quantity and a rate. Use a dot for decimals.")
      }
      var scaled = rate * 100
      var rounded = Decimal()
      NSDecimalRound(&rounded, &scaled, 0, .plain)
      guard rounded == scaled else {
        throw BookError.invalid("Rates support up to two decimal places.")
      }
      return InvoiceLine(
        item: item, quantity: quantity, ratePaise: NSDecimalNumber(decimal: rounded).int64Value)
    }
  }
  func parsedTaxes() throws -> [TaxCharge] {
    try taxes.map { tax in
      guard let ledger = tax.ledger,
        !tax.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { throw BookError.invalid("Select a tax ledger and enter a charge name.") }
      let basis = try enteredMoney(tax.rate)
      guard basis > 0 && basis <= 10000 else {
        throw BookError.invalid("Tax rates must be above 0 and at most 100%.")
      }
      return TaxCharge(name: tax.name, basisPoints: Int(basis), ledger: ledger)
    }
  }
  var previewTotal: Double {
    guard let items = try? parsedLines(), let charges = try? parsedTaxes() else { return 0 }
    let base = items.reduce(Decimal(0)) { $0 + Decimal($1.totalPaise) }
    guard base <= 900_000_000_000_000 else { return 0 }
    let tax = charges.reduce(Decimal(0)) {
      $0 + Decimal(paise(base * Decimal($1.basisPoints) / 10000))
    }
    return NSDecimalNumber(decimal: (base + tax) / 100).doubleValue
  }
  func close() { if let onClose { onClose() } else { dismiss() } }
  func saveInvoice() {
    do {
      guard let p = party, let n = nominal else {
        throw BookError.invalid("Select both accounting ledgers.")
      }
      try store.commitInvoice(
        Invoice(
          number: number.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, date: date,
          party: p, nominal: n, lines: try parsedLines(), note: note, taxes: try parsedTaxes()))
      close()
    } catch { self.error = error.localizedDescription }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(kind == "Sale" ? "Sales" : "Purchase").bold().foregroundStyle(.white).frame(width: 150)
          .padding(.vertical, 5).background(Prime.blue)
        Text("No.")
        TextField("Invoice number", text: $number).frame(width: 180)
        Spacer()
        DatePicker("", selection: $date, displayedComponents: .date).labelsHidden().frame(
          width: 130)
      }.padding(.trailing, 16).padding(.top, 10)
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text("Party A/c name:").frame(width: 130, alignment: .leading)
          PrimeLookup(
            selection: $party,
            options: store.books.ledgers.filter { ["Asset", "Liability"].contains($0.group) }.map {
              PrimeOption(id: $0.id, name: $0.name)
            }
          ).frame(width: 320)
          Spacer()
        }
        HStack {
          Text(kind == "Sale" ? "Sales ledger:" : "Purchase ledger:").frame(
            width: 130, alignment: .leading)
          PrimeLookup(
            selection: $nominal,
            options: store.books.ledgers.filter {
              $0.group == (kind == "Sale" ? "Income" : "Expense")
            }.map { PrimeOption(id: $0.id, name: $0.name) }
          ).frame(width: 320)
          Spacer()
        }
      }.padding(16).padding(.top, 12)
      HStack {
        Text("Name of Item").frame(maxWidth: .infinity, alignment: .leading)
        Text("Quantity").frame(width: 90)
        Text("Rate").frame(width: 110)
        Text("Amount").frame(width: 130, alignment: .trailing)
        Color.clear.frame(width: 22, height: 1)
      }.padding(.horizontal, 16).padding(.vertical, 6).overlay(alignment: .top) {
        Prime.line.frame(height: 1)
      }.overlay(alignment: .bottom) { Prime.line.frame(height: 1) }
      ScrollView {
        VStack(spacing: 8) {
          ForEach($lines) { $line in
            HStack {
              PrimeLookup(
                selection: $line.item,
                options: store.books.stock.map {
                  PrimeOption(id: $0.id, name: "\($0.name) (\($0.unit))")
                }, title: "List of Stock Items", prompt: "Select item"
              ).frame(maxWidth: .infinity, alignment: .leading)
              TextField("0", text: $line.quantity).multilineTextAlignment(.trailing).frame(
                width: 90)
              TextField("0.00", text: $line.rate).multilineTextAlignment(.trailing).frame(
                width: 110)
              Text(((Double(line.quantity) ?? 0) * (Double(line.rate) ?? 0)).formatted(currency))
                .frame(width: 130, alignment: .trailing)
              Button {
                lines.removeAll { $0.id == line.id }
              } label: {
                Image(systemName: "minus.circle")
              }.disabled(lines.count == 1).frame(width: 22)
            }.padding(.horizontal, 16)
          }
          HStack {
            Button("+ Add item") { lines.append(DraftLine()) }.disabled(lines.count >= 1000)
            Spacer()
          }.padding(.horizontal, 16)
        }.padding(.top, 12)
      }.frame(minHeight: 100, maxHeight: .infinity)
      VStack(spacing: 8) {
        ForEach($taxes) { $tax in
          HStack {
            TextField("Tax name", text: $tax.name).frame(width: 120)
            TextField("Rate %", text: $tax.rate).frame(width: 65)
            Picker("Tax ledger", selection: $tax.ledger) {
              Text("Select ledger").tag(Optional<UUID>.none)
              ForEach(
                store.books.ledgers.filter { $0.group == (kind == "Sale" ? "Liability" : "Asset") }
              ) { Text($0.name).tag(Optional($0.id)) }
            }.frame(maxWidth: 340)
            Spacer()
            Button {
              taxes.removeAll { $0.id == tax.id }
            } label: {
              Image(systemName: "minus.circle")
            }
          }
        }
        HStack {
          Button("+ Add tax charge") { taxes.append(DraftTax()) }.disabled(taxes.count >= 5)
          Spacer()
        }
      }.padding(.horizontal, 16).padding(.vertical, 8)
      if !error.isEmpty { Text(error).foregroundStyle(.red).padding(.horizontal, 16) }
      HStack(alignment: .top) {
        Text("Narration:").bold()
        TextField("", text: $note, axis: .vertical).lineLimit(2...3)
      }.padding(16)
      HStack {
        Text("Total")
        Spacer()
        Text(previewTotal.formatted(currency)).bold().frame(width: 150, alignment: .trailing)
      }.padding(16).overlay(alignment: .top) { Prime.line.frame(height: 1) }
      HStack {
        Button("Esc: Cancel") { close() }
        Spacer()
        Text("Tax rates are configured per invoice").font(.system(size: 11)).foregroundStyle(
          .secondary)
        Spacer()
        Button("A: Accept") { saveInvoice() }.keyboardShortcut("a", modifiers: .control)
      }.padding(12).background(Prime.pale)
    }.font(Prime.font).buttonStyle(.plain).textFieldStyle(.plain).background(.white)
      .foregroundStyle(Prime.ink).environment(\.colorScheme, .light).frame(
        minWidth: 760, minHeight: 540
      ).onChange(of: suppliedDate) { _, value in date = value }
  }
}

struct InvoiceRegister: View {
  @ObservedObject var store: Store
  @State private var selection: Invoice?
  var body: some View {
    VStack(alignment: .leading) {
      if store.books.invoices.isEmpty {
        ContentUnavailableView(
          "No invoices", systemImage: "doc.text",
          description: Text("Create a sale or purchase to post stock and accounting together."))
      } else {
        List(store.books.invoices.reversed()) { invoice in
          Button {
            selection = invoice
          } label: {
            HStack {
              Text(invoice.number).bold().frame(width: 120, alignment: .leading)
              Text(invoice.kind).frame(width: 80)
              Text(invoice.date, style: .date)
              Text(store.name(invoice.party))
              Spacer()
              Text((Double(invoice.totalPaise) / 100).formatted(currency))
            }.padding(.vertical, 6)
          }.buttonStyle(.plain)
        }
      }
    }.sheet(item: $selection) { invoice in InvoiceDetail(store: store, invoice: invoice) }
  }
}
struct InvoiceDetail: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  let invoice: Invoice
  var document: some View {
    PrintableDocument(
      company: store.books.company, title: invoice.kind + " Invoice", number: invoice.number,
      date: invoice.date, party: store.name(invoice.party),
      rows: invoice.lines.map { line in
        PrintRow(
          name: store.books.stock.first { $0.id == line.item }?.name ?? "Item",
          quantity: line.quantity, rate: line.ratePaise, amount: line.totalPaise)
      }, subtotal: invoice.subtotalPaise,
      charges: (invoice.taxes ?? []).map { ($0.name, invoice.taxAmount($0)) },
      total: invoice.totalPaise,
      note: invoice.note
        + "\nConfigured tax charges; statutory particulars and filing are not included.",
      template: store.books.invoiceTemplate)
  }
  var body: some View {
    VStack {
      ScrollView { document }
      HStack {
        Button("Print / Save PDF") {
          let view = NSHostingView(rootView: document)
          view.setFrameSize(view.fittingSize)
          let operation = NSPrintOperation(view: view)
          operation.run()
        }
        Spacer()
        Button("Close") { dismiss() }
      }.padding()
    }.frame(width: 700, height: 600)
  }
}
