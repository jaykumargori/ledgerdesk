import AppKit
import SwiftUI

struct PrintRow: Identifiable {
  var id = UUID()
  var name: String
  var quantity: Double
  var rate: Int64
  var amount: Int64
}
struct PrintableDocument: View {
  let company: String
  let title: String
  let number: String
  let date: Date
  let party: String
  let rows: [PrintRow]
  let subtotal: Int64
  let charges: [(String, Int64)]
  let total: Int64
  let note: String
  let template: DocumentTemplate
  var accent: Color {
    template.colour == "Green"
      ? Color(red: 0.13, green: 0.40, blue: 0.31) : template.colour == "Black" ? .black : Prime.blue
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        Text(company).font(.custom(template.font, size: 25).bold())
        if !template.header.isEmpty { Text(template.header).font(.custom(template.font, size: 11)) }
      }
      .padding(template.style == "Letterhead" ? 16 : 0).frame(
        maxWidth: .infinity, alignment: .leading
      ).background(template.style == "Letterhead" ? accent : Color.clear).foregroundStyle(
        template.style == "Letterhead" ? .white : accent)
      HStack {
        Text("\(title) · \(number)").bold()
        Spacer()
        Text(date, style: .date)
      }
      Text("Party: \(party)")
      HStack {
        Text("Item").frame(maxWidth: .infinity, alignment: .leading)
        Text("Quantity").frame(width: 75)
        Text("Rate").frame(width: 105, alignment: .trailing)
        Text("Amount").frame(width: 115, alignment: .trailing)
      }.bold().padding(.vertical, 8).background(
        template.style == "Clean" ? Color.clear : accent.opacity(0.08))
      ForEach(rows) { row in
        HStack(alignment: .top) {
          Text(row.name).lineLimit(template.wrap ? nil : 1).frame(
            maxWidth: .infinity, alignment: .leading)
          Text(row.quantity.formatted()).frame(width: 75)
          Text((Double(row.rate) / 100).formatted(currency)).frame(width: 105, alignment: .trailing)
          Text((Double(row.amount) / 100).formatted(currency)).frame(
            width: 115, alignment: .trailing)
        }
      }
      Divider()
      HStack {
        Text("Subtotal")
        Spacer()
        Text((Double(subtotal) / 100).formatted(currency))
      }
      ForEach(charges.indices, id: \.self) { i in
        HStack {
          Text(charges[i].0)
          Spacer()
          Text((Double(charges[i].1) / 100).formatted(currency))
        }
      }
      HStack {
        Text("Total").bold()
        Spacer()
        Text((Double(total) / 100).formatted(currency)).font(
          .custom(template.font, size: 20).bold())
      }
      if !note.isEmpty { Text(note).lineLimit(template.wrap ? nil : 1).foregroundStyle(.secondary) }
      if !template.footer.isEmpty {
        Divider()
        Text(template.footer).font(.custom(template.font, size: 11)).lineLimit(
          template.wrap ? nil : 1)
      }
    }.font(.custom(template.font, size: 13)).padding(28).frame(width: 680).background(.white)
      .foregroundStyle(.black).environment(\.colorScheme, .light)
  }
}
@MainActor func printDocument<V: View>(_ document: V) {
  let view = NSHostingView(rootView: document)
  view.setFrameSize(view.fittingSize)
  NSPrintOperation(view: view).run()
}
struct DocumentTemplateEditor: View {
  @ObservedObject var store: Store
  let order: Bool
  @State private var settings = DocumentTemplate()
  @State private var ready = false
  @State private var message = ""
  var body: some View {
    HStack(alignment: .top, spacing: 20) {
      VStack(alignment: .leading, spacing: 15) {
        Text(order ? "Purchase Order Template" : "Invoice Template").font(.headline)
        Picker("Style", selection: $settings.style) {
          ForEach(["Classic", "Clean", "Letterhead"], id: \.self) { Text($0) }
        }
        Picker("Colour", selection: $settings.colour) {
          ForEach(["Blue", "Green", "Black"], id: \.self) { Text($0) }
        }
        Picker("Font", selection: $settings.font) {
          ForEach(["Arial", "Helvetica", "Times New Roman"], id: \.self) { Text($0) }
        }
        TextField("Header / address details", text: $settings.header, axis: .vertical).lineLimit(
          2...4)
        TextField("Footer / terms", text: $settings.footer, axis: .vertical).lineLimit(2...4)
        Toggle("Auto wrap text", isOn: $settings.wrap)
        Toggle("Auto-save template changes", isOn: $settings.autoSave)
        Button("Save template") { save() }
        Button("Reset to default") { settings = DocumentTemplate() }
        Text(message).font(.caption).foregroundStyle(.secondary)
        Spacer()
      }.frame(width: 260)
      ScrollView([.horizontal, .vertical]) {
        PrintableDocument(
          company: store.books.company, title: order ? "Purchase Order" : "Invoice",
          number: "PREVIEW", date: Date(), party: "Sample party",
          rows: [
            PrintRow(
              name: "Sample stock item with an extended description", quantity: 2, rate: 5000,
              amount: 10000)
          ], subtotal: 10000, charges: [], total: 10000, note: "Preview only", template: settings)
      }.background(Color.gray.opacity(0.08))
    }.onAppear {
      settings = order ? store.books.orderTemplate : store.books.invoiceTemplate
      ready = true
    }.onChange(of: settings) { old, new in if ready && (new.autoSave || old.autoSave) { save() } }
  }
  func save() {
    do {
      try store.transaction {
        if order { $0.orderTemplate = settings } else { $0.invoiceTemplate = settings }
      }
      message = "Template saved"
    } catch { message = error.localizedDescription }
  }
}
@MainActor final class PurchaseOrderWorkspace: ObservableObject { @Published var create = false }
struct PurchaseOrdersView: View {
  @ObservedObject var store: Store
  @ObservedObject var workspace: PurchaseOrderWorkspace
  let templates: () -> Void
  @State private var selected: PurchaseOrder?
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Date").frame(width: 100, alignment: .leading)
        Text("Order No.").frame(width: 110, alignment: .leading)
        Text("Supplier").frame(maxWidth: .infinity, alignment: .leading)
        Text("Delivery By").frame(width: 110, alignment: .leading)
        Text("Status").frame(width: 75)
        Text("Amount").frame(width: 130, alignment: .trailing)
      }.padding(.horizontal, 12).frame(height: 30).background(Prime.pale)
      ScrollView {
        VStack(spacing: 0) {
          ForEach(store.books.purchaseOrders.reversed()) { order in
            Button {
              selected = order
            } label: {
              HStack {
                Text(order.date, style: .date).frame(width: 100, alignment: .leading)
                Text(order.number).frame(width: 110, alignment: .leading)
                Text(store.name(order.supplier)).frame(maxWidth: .infinity, alignment: .leading)
                Text(order.due, style: .date).frame(width: 110, alignment: .leading)
                Text(order.closed ? "Closed" : "Open").frame(width: 75)
                Text((Double(order.totalPaise) / 100).formatted(currency)).frame(
                  width: 130, alignment: .trailing)
              }.padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
            }.overlay(alignment: .bottom) { Prime.line.opacity(0.4).frame(height: 1) }
          }
          if store.books.purchaseOrders.isEmpty {
            Text("No purchase orders entered").foregroundStyle(.secondary).padding(24)
          }
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      HStack {
        Button("C: Create Order") { workspace.create = true }
        Button("T: Templates", action: templates)
        Spacer()
        Text("Orders do not post accounting or stock movements").font(.system(size: 11))
          .foregroundStyle(.secondary)
      }.padding(12).background(Prime.pale)
    }.font(Prime.font).buttonStyle(.plain).sheet(isPresented: $workspace.create) {
      PurchaseOrderForm(store: store)
    }.sheet(item: $selected) { order in PurchaseOrderDetail(store: store, orderID: order.id) }
  }
}
struct PurchaseOrderForm: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  @State private var number = ""
  @State private var date = Date()
  @State private var due = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
  @State private var supplier: UUID?
  @State private var lines = [DraftLine()]
  @State private var note = ""
  @State private var error = ""
  func orderLines() throws -> [InvoiceLine] {
    try lines.map { line in
      guard let item = line.item, let quantity = Double(line.quantity), quantity.isFinite,
        quantity > 0, quantity <= 1_000_000
      else { throw BookError.invalid("Select an item and enter a positive quantity.") }
      let rate = try enteredMoney(line.rate)
      guard rate > 0 else { throw BookError.invalid("Rate must be positive.") }
      return InvoiceLine(item: item, quantity: quantity, ratePaise: rate)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Purchase Order Creation").font(.headline)
      HStack {
        TextField("Order number", text: $number)
        DatePicker("Date", selection: $date, displayedComponents: .date)
        DatePicker("Delivery by", selection: $due, displayedComponents: .date)
      }
      PrimeLookup(
        selection: $supplier,
        options: store.books.ledgers.filter { ["Asset", "Liability"].contains($0.group) }.map {
          PrimeOption(id: $0.id, name: $0.name)
        }, title: "List of Suppliers", prompt: "Select supplier")
      HStack {
        Text("Name of Item").frame(maxWidth: .infinity, alignment: .leading)
        Text("Quantity").frame(width: 90)
        Text("Rate").frame(width: 100)
      }.padding(.vertical, 6).background(Prime.pale)
      ScrollView {
        ForEach($lines) { $line in
          HStack {
            PrimeLookup(
              selection: $line.item,
              options: store.books.stock.map { PrimeOption(id: $0.id, name: $0.name) },
              title: "List of Stock Items", prompt: "Select item")
            TextField("Quantity", text: $line.quantity).frame(width: 90)
            TextField("Rate", text: $line.rate).frame(width: 100)
            Button {
              lines.removeAll { $0.id == line.id }
            } label: {
              Image(systemName: "minus.circle")
            }.disabled(lines.count == 1)
          }
        }
      }.frame(height: 170)
      Button("Add item") { lines.append(DraftLine()) }.disabled(lines.count >= 1000)
      TextField("Narration / terms", text: $note)
      Text(error).foregroundStyle(.red)
      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Button("Accept") {
          do {
            guard let supplier else { throw BookError.invalid("Choose a supplier.") }
            let order = PurchaseOrder(
              number: number.trimmingCharacters(in: .whitespacesAndNewlines), date: date, due: due,
              supplier: supplier, lines: try orderLines(), note: note)
            try store.transaction { try $0.addOrder(order) }
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.keyboardShortcut("a", modifiers: .control)
      }
    }.padding(24).frame(width: 800).font(Prime.font)
  }
}
struct PurchaseOrderDetail: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  let orderID: UUID
  @State private var error = ""
  var order: PurchaseOrder? { store.books.purchaseOrders.first { $0.id == orderID } }
  var body: some View {
    if let order {
      VStack {
        ScrollView { document(order) }
        Text(error).foregroundStyle(.red)
        HStack {
          Button("Print / Save PDF") { printDocument(document(order)) }
          Button(order.closed ? "Reopen order" : "Mark closed") {
            do {
              try store.transaction {
                if let i = $0.purchaseOrders.firstIndex(where: { $0.id == orderID }) {
                  $0.purchaseOrders[i].closed.toggle()
                }
              }
            } catch { self.error = error.localizedDescription }
          }
          Spacer()
          Button("Close") { dismiss() }
        }.padding()
      }.frame(width: 720, height: 600)
    }
  }
  func document(_ order: PurchaseOrder) -> some View {
    PrintableDocument(
      company: store.books.company, title: "Purchase Order", number: order.number, date: order.date,
      party: store.name(order.supplier),
      rows: order.lines.map { line in
        PrintRow(
          name: store.books.stock.first { $0.id == line.item }?.name ?? "Item",
          quantity: line.quantity, rate: line.ratePaise, amount: line.totalPaise)
      }, subtotal: order.totalPaise, charges: [], total: order.totalPaise,
      note: "Delivery by: \(order.due.formatted(date:.abbreviated,time:.omitted))\n\(order.note)",
      template: store.books.orderTemplate)
  }
}
