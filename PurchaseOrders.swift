import Foundation

struct PurchaseOrder: Codable, Identifiable {
  var id = UUID()
  var number: String
  var date: Date
  var due: Date
  var supplier: UUID
  var lines: [InvoiceLine]
  var note: String
  var closed = false
  var totalPaise: Int64 { lines.reduce(0) { $0 + $1.totalPaise } }
}
struct DocumentTemplate: Codable, Equatable {
  var style = "Classic"
  var colour = "Blue"
  var font = "Arial"
  var header = ""
  var footer = ""
  var wrap = true
  var autoSave = true
}
extension Books {
  mutating func addOrder(_ order: PurchaseOrder) throws {
    guard
      !purchaseOrders.contains(where: {
        $0.number.localizedCaseInsensitiveCompare(order.number) == .orderedSame
      })
    else { throw BookError.invalid("Purchase order number already exists.") }
    try validateOrder(order)
    purchaseOrders.append(order)
  }
  func validateOrder(_ order: PurchaseOrder) throws {
    guard !order.number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      order.due >= Calendar.current.startOfDay(for: order.date),
      ledgers.contains(where: {
        $0.id == order.supplier && ["Asset", "Liability"].contains($0.group)
      }), !order.lines.isEmpty, order.lines.count <= 1000,
      order.lines.allSatisfy({ line in
        stock.contains { $0.id == line.item } && line.quantity.isFinite && line.quantity > 0
          && line.quantity <= 1_000_000 && line.ratePaise > 0 && line.ratePaise <= 100_000_000_000
      })
    else {
      throw BookError.invalid(
        "An order needs a unique number, supplier, valid delivery date and positive item quantities and rates."
      )
    }
    let total = order.lines.reduce(Decimal(0)) { $0 + Decimal($1.totalPaise) }
    guard total > 0, total <= 900_000_000_000_000 else {
      throw BookError.invalid("Order amount is outside supported limits.")
    }
  }
  func validateDocuments() throws {
    guard Set(purchaseOrders.map(\.id)).count == purchaseOrders.count,
      Set(purchaseOrders.map { $0.number.lowercased() }).count == purchaseOrders.count
    else { throw BookError.invalid("Duplicate purchase orders.") }
    for order in purchaseOrders { try validateOrder(order) }
    for template in [invoiceTemplate, orderTemplate] {
      guard ["Classic", "Clean", "Letterhead"].contains(template.style),
        ["Blue", "Green", "Black"].contains(template.colour),
        ["Arial", "Helvetica", "Times New Roman"].contains(template.font),
        template.header.count <= 3000, template.footer.count <= 3000
      else { throw BookError.invalid("Invalid document template.") }
    }
  }
}
