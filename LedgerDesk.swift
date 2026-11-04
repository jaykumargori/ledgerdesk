import AppKit
import Foundation
import SwiftUI

struct Ledger: Codable, Identifiable {
  var id = UUID()
  var name: String
  var group: String
}
struct Voucher: Codable, Identifiable {
  var id = UUID()
  var date: Date
  var debit: UUID
  var credit: UUID
  var amount: Double
  var narration: String
}
struct StockItem: Codable, Identifiable {
  var id = UUID()
  var name: String
  var unit: String
  var opening: Double
  var rate: Double
}
struct StockMovement: Codable, Identifiable {
  var id = UUID()
  var item: UUID
  var date: Date
  var quantity: Double
  var note: String
  var costPaise: Int64? = nil
}
struct Books: Codable {
  var company = "My Company"
  var ledgers: [Ledger] = [
    Ledger(name: "Cash", group: "Asset"), Ledger(name: "Bank", group: "Asset"),
    Ledger(name: "Capital", group: "Equity"), Ledger(name: "Sales", group: "Income"),
    Ledger(name: "Purchases", group: "Expense"),
  ]
  var vouchers: [Voucher] = []
  var stock: [StockItem] = []
  var movements: [StockMovement] = []
  var invoices: [Invoice] = []
  var employees: [Employee] = []
  var payruns: [PayRun] = []
  var bankLines: [BankLine] = []
  var bankAccounts: [BankAccount] = []
  var purchaseOrders: [PurchaseOrder] = []
  var invoiceTemplate = DocumentTemplate()
  var orderTemplate = DocumentTemplate()
  enum CodingKeys: String, CodingKey {
    case company, ledgers, vouchers, stock, movements, invoices, employees, payruns, bankLines,
      bankAccounts, purchaseOrders, invoiceTemplate, orderTemplate
  }
  init() {}
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    company = try c.decode(String.self, forKey: .company)
    ledgers = try c.decode([Ledger].self, forKey: .ledgers)
    vouchers = try c.decode([Voucher].self, forKey: .vouchers)
    stock = try c.decodeIfPresent([StockItem].self, forKey: .stock) ?? []
    movements = try c.decodeIfPresent([StockMovement].self, forKey: .movements) ?? []
    invoices = try c.decodeIfPresent([Invoice].self, forKey: .invoices) ?? []
    employees = try c.decodeIfPresent([Employee].self, forKey: .employees) ?? []
    payruns = try c.decodeIfPresent([PayRun].self, forKey: .payruns) ?? []
    bankLines = try c.decodeIfPresent([BankLine].self, forKey: .bankLines) ?? []
    bankAccounts = try c.decodeIfPresent([BankAccount].self, forKey: .bankAccounts) ?? []
    purchaseOrders = try c.decodeIfPresent([PurchaseOrder].self, forKey: .purchaseOrders) ?? []
    invoiceTemplate =
      try c.decodeIfPresent(DocumentTemplate.self, forKey: .invoiceTemplate) ?? DocumentTemplate()
    orderTemplate =
      try c.decodeIfPresent(DocumentTemplate.self, forKey: .orderTemplate) ?? DocumentTemplate()
  }
}
@MainActor final class Store: ObservableObject {
  @Published var books = Books()
  @Published var error: String?
  var writable = true
  let url: URL
  init() {
    #if QA
      let dir = URL(fileURLWithPath: "/private/tmp/ledgerdesk-qa-books", isDirectory: true)
    #else
      let dir =
        ProcessInfo.processInfo.environment["LEDGERDESK_DATA_DIR"].map {
          URL(fileURLWithPath: $0, isDirectory: true)
        }
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LedgerDesk", isDirectory: true)
    #endif
    url = dir.appendingPathComponent("books.json")
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: url.path) {
        books = try JSONDecoder().decode(Books.self, from: Data(contentsOf: url))
        try books.validate()
      }
    } catch {
      self.writable = false
      self.error = "Could not open your books: \(error.localizedDescription)"
    }
  }
  func save() {
    guard writable else {
      self.error = "Books could not be loaded. Restore a valid backup before saving."
      return
    }
    do {
      try books.validate()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(books).write(to: url, options: .atomic)
    } catch { self.error = "Could not save: \(error.localizedDescription)" }
  }
  func transaction(_ change: (inout Books) throws -> Void) throws {
    guard writable else { throw BookError.invalid("Restore valid books before saving.") }
    var next = books
    try change(&next)
    try next.validate()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(next).write(to: url, options: .atomic)
    books = next
  }
  func commitInvoice(_ invoice: Invoice) throws {
    guard writable else {
      throw BookError.invalid("Books could not be loaded. Restore a valid backup first.")
    }
    var next = books
    try next.postInvoice(invoice)
    try next.validate()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(next).write(to: url, options: .atomic)
    books = next
  }
  func exportBackup() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "LedgerDesk-backup.json"
    panel.allowedContentTypes = [.json]
    if panel.runModal() == .OK, let target = panel.url {
      do {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(books).write(to: target, options: .atomic)
      } catch { self.error = "Could not export backup: \(error.localizedDescription)" }
    }
  }
  func importBackup() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let target = panel.url else { return }
    do {
      let candidate = try JSONDecoder().decode(Books.self, from: Data(contentsOf: target))
      try candidate.validate()
      let ids = Set(candidate.ledgers.map(\.id))
      guard !candidate.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        ids.count == candidate.ledgers.count,
        candidate.vouchers.allSatisfy({
          ids.contains($0.debit) && ids.contains($0.credit) && $0.debit != $0.credit
            && $0.amount.isFinite && $0.amount > 0
        })
      else {
        throw NSError(
          domain: "LedgerDesk", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Backup contains invalid accounting records."])
      }
      let confirm = NSAlert()
      confirm.messageText = "Replace current books?"
      confirm.informativeText =
        "Importing this backup replaces the current company and all vouchers."
      confirm.addButton(withTitle: "Replace")
      confirm.addButton(withTitle: "Cancel")
      if confirm.runModal() == .alertFirstButtonReturn {
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(candidate)
        if FileManager.default.fileExists(atPath: url.path) {
          let backup = url.deletingLastPathComponent().appendingPathComponent(
            "before-import-" + UUID().uuidString + ".json")
          try FileManager.default.copyItem(at: url, to: backup)
        }
        try encoded.write(to: url, options: .atomic)
        books = candidate
        writable = true
      }
    } catch { self.error = "Could not import backup: \(error.localizedDescription)" }
  }
  func stockBalance(_ id: UUID) -> Double {
    (books.stock.first { $0.id == id }?.opening ?? 0)
      + books.movements.filter { $0.item == id }.reduce(0) { $0 + $1.quantity }
  }
  func balance(_ id: UUID) -> Double {
    books.vouchers.reduce(0) {
      $0 + ($1.debit == id ? $1.amount : 0) - ($1.credit == id ? $1.amount : 0)
    }
  }
  func name(_ id: UUID) -> String { books.ledgers.first(where: { $0.id == id })?.name ?? "Unknown" }
}
let currency = FloatingPointFormatStyle<Double>.Currency(code: "INR")
struct ContentView: View {
  @StateObject private var store = Store()
  @StateObject private var banking = BankWorkspace()
  @StateObject private var purchaseOrders = PurchaseOrderWorkspace()
  @State private var section = "Dashboard"
  @State private var showLedger = false
  @State private var showVoucher = false
  @State private var showStock = false
  @State private var showMovement = false
  @State private var showInvoice = false
  @State private var workingDate = Date()
  @State private var gatewaySelection = "Create"
  @State private var showDate = false
  @State private var showHelp = false
  @State private var showFind = false
  @State private var findQuery = ""
  @State private var showPeriod = false
  @State private var showCompanies = false
  @State private var showDisplaySettings = false
  @State private var showService = false
  @State private var showNotifications = false
  @State private var periodStart = FiscalCalendar.start(Date())
  @State private var periodEnd = FiscalCalendar.end(Date())
  @State private var showGoTo = false
  @State private var master: MasterRoute?
  @State private var voucherType = "Journal"
  @State private var invoiceKind = "Sale"
  let sections = [
    "Dashboard", "Vouchers", "Invoices", "Ledgers", "Inventory", "Stock Valuation", "Banking",
    "Payroll", "Tax Summary", "Ledger Statement", "Balance Sheet", "Trial Balance", "Profit & Loss",
    "Company", "Ratio Analysis", "Business Overview", "Purchase Orders", "Invoice Templates",
    "Order Templates",
  ]
  var body: some View {
    VStack(spacing: 0) {
      ribbon
      HStack(spacing: 0) {
        VStack(spacing: 0) {
          HStack {
            Text(section == "Banking" ? banking.title : screenTitle).bold()
            Spacer()
            if section != "Dashboard" { Text(store.books.company).font(.system(size: 12)) }
            Button("×") { section = "Dashboard" }.buttonStyle(.plain).font(.system(size: 18))
          }.padding(.horizontal, 8).frame(height: 17).font(.system(size: 11)).background(Prime.pale)
          if section == "Dashboard" {
            GatewayView(
              store: store, date: workingDate, periodStart: periodStart, periodEnd: periodEnd,
              navigate: route, selection: $gatewaySelection)
          } else if section == "Invoice Creation" {
            InvoiceForm(
              store: store, date: workingDate, initialKind: invoiceKind,
              onClose: { section = "Invoices" }
            ).id(invoiceKind)
          } else if section == "Accounting Voucher Creation" {
            PrimeVoucherEditor(
              store: store, date: workingDate, kind: voucherType, onClose: { section = "Dashboard" }
            ).id(voucherType)
          } else if section == "Purchase Orders" {
            PurchaseOrdersView(
              store: store, workspace: purchaseOrders, templates: { section = "Order Templates" })
          } else if section == "Banking" {
            BankWorkspaceView(store: store, workspace: banking)
          } else {
            VStack(alignment: .leading, spacing: 12) {
              reportActions
              content
            }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
              .background(.white)
          }
        }
        PrimeRail(actions: railActions)
      }
      bottomBar
    }.frame(minWidth: 1250, minHeight: 650).font(Prime.font).foregroundStyle(Prime.ink).background(
      .white
    ).environment(\.colorScheme, .light).preferredColorScheme(.light)
      .background(PrimeKeys(handle: handleKey).frame(width: 0, height: 0))
      .sheet(isPresented: $showLedger) { LedgerForm(store: store) }
      .sheet(isPresented: $showVoucher) { VoucherForm(store: store, date: workingDate) }
      .sheet(isPresented: $showStock) { StockForm(store: store) }
      .sheet(isPresented: $showMovement) { MovementForm(store: store) }
      .sheet(isPresented: $showInvoice) {
        InvoiceForm(store: store, date: workingDate, initialKind: invoiceKind)
      }
      .sheet(isPresented: $showFind) {
        SmartFindView(store: store, query: $findQuery, navigate: route)
      }
      .sheet(isPresented: $showPeriod) { PeriodView(start: $periodStart, end: $periodEnd) }
      .sheet(isPresented: $showCompanies) {
        SelectCompanyView(store: store, details: { section = "Company" })
      }
      .sheet(isPresented: $showDisplaySettings) { DisplaySettingsView() }
      .sheet(isPresented: $showService) {
        VStack(alignment: .leading, spacing: 16) {
          Text("TallyCapital").font(.headline)
          Text(
            "TallyCapital is a Tally Solutions service and is not connected to this independent app."
          )
          Link(
            "View official information",
            destination: URL(string: "https://help.tallysolutions.com/tallycapital-add-on/")!)
          Button("Close") { showService = false }
        }.padding(24).frame(width: 440)
      }
      .sheet(isPresented: $showNotifications) {
        VStack(alignment: .leading, spacing: 16) {
          Text("Notifications").font(.headline)
          Text(store.error ?? "No notifications")
          Button("Close") { showNotifications = false }
        }.padding(24).frame(width: 400)
      }
      .sheet(isPresented: $showHelp) {
        VStack(alignment: .leading, spacing: 14) {
          Text("Keyboard Help").font(.headline)
          Text(
            "↑ / ↓ and Enter: Gateway selection\nEscape: Gateway\nF2: Date · F3: Company\nF4: Contra · F5: Payment · F6: Receipt\nF7: Journal · F8: Sales · F9: Purchase\nOption-G: Go To\nCtrl-A: Accept voucher or invoice"
          )
          Button("Close") { showHelp = false }
        }.padding(24).frame(width: 420)
      }
      .sheet(isPresented: $showDate) { WorkingDateView(date: $workingDate) }
      .sheet(isPresented: $showGoTo) { GoToView(sections: sections, navigate: { section = $0 }) }
      .sheet(item: $master) { route in MasterHub(store: store, mode: route.id) }
      .alert(
        "Storage error",
        isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
      ) {
        Button("OK") { store.error = nil }
      } message: {
        Text(store.error ?? "")
      }
  }
  var screenTitle: String {
    switch section {
    case "Dashboard": return "Gateway of LedgerDesk"
    case "Invoice Creation": return "Accounting Voucher Creation"
    case "Vouchers": return "Day Book"
    case "Ledgers": return "Chart of Accounts"
    case "Inventory": return "Stock Summary"
    case "Profit & Loss": return "Profit & Loss A/c"
    default: return section
    }
  }
  var ribbon: some View {
    HStack(alignment: .bottom, spacing: 0) {
      VStack(alignment: .leading, spacing: 1) {
        Text("LedgerDesk").font(.system(size: 16)).italic()
        Text("MAC EDITION").font(.system(size: 10)).tracking(1.1)
      }.frame(width: 140, alignment: .leading).padding(.bottom, 7)
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Spacer().frame(width: 186)
          HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
            TextField("Find details entered in masters and transactions. (Alt+F)", text: $findQuery)
              .textFieldStyle(.plain).onSubmit { showFind = true }
          }.font(.system(size: 12)).padding(5).frame(width: 475).background(Prime.pale)
            .foregroundStyle(Prime.ink)
          Spacer()
          Button {
            showNotifications = true
          } label: {
            Image(systemName: "bell")
          }.padding(.trailing, 12)
        }
        HStack(spacing: 0) {
          Menu("K: Company") {
            Button("Select Company") { showCompanies = true }
            Button("Company details") { section = "Company" }
            Button("Create master") { master = MasterRoute(id: "Create") }
            Button("Alter ledger") { master = MasterRoute(id: "Alter") }
          }.fixedSize().frame(width: 94, alignment: .leading)
          Menu("Y: Data") {
            Button("Backup") { store.exportBackup() }
            Button("Restore") { store.importBackup() }
          }.fixedSize().frame(width: 94, alignment: .leading)
          Menu("Z: Exchange") {
            Button("Import backup") { store.importBackup() }
            Button("Export backup") { store.exportBackup() }
          }.fixedSize().frame(width: 188, alignment: .leading)
          Button("G: Go To") { showGoTo = true }.padding(.horizontal, 10).background(Prime.pale)
            .foregroundStyle(Prime.ink).fixedSize().frame(width: 154, alignment: .leading)
          Button("O: Import") { store.importBackup() }.fixedSize().frame(
            width: 94, alignment: .leading)
          Button("E: Export") { store.exportBackup() }.fixedSize().frame(
            width: 94, alignment: .leading)
          Menu("M: Share") { Button("Export a backup file…") { store.exportBackup() } }.fixedSize()
            .frame(width: 94, alignment: .leading)
          Menu("P: Print") {
            Button("Invoice register") { section = "Invoices" }
            Button("Purchase orders") { section = "Purchase Orders" }
            Button("Invoice templates") { section = "Invoice Templates" }
            Button("Purchase order templates") { section = "Order Templates" }
          }.fixedSize()
            .frame(width: 94, alignment: .leading)
          Button("9: TallyCapital") { showService = true }.fixedSize().frame(
            width: 108, alignment: .leading)
          Menu("F1: Help") {
            Button("Keyboard shortcuts") { showHelp = true }
            Button("Settings > Display") { showDisplaySettings = true }
            Button("Try Now") { section = "Try Now" }
            Link(
              "Get Started with TallyIra",
              destination: URL(string: "https://help.tallysolutions.com/get-started-docs-by-ira/")!)
          }.fixedSize().frame(width: 64, alignment: .leading)
        }.font(.system(size: 12)).menuStyle(.borderlessButton).menuIndicator(.hidden).environment(
          \.colorScheme, .dark
        ).padding(.bottom, 5)
      }
    }.buttonStyle(.plain).foregroundStyle(.white).padding(.horizontal, 9).padding(.top, 4).frame(
      height: 65
    ).background(Color(red: 0.16, green: 0.29, blue: 0.51))
  }
  @ViewBuilder var reportActions: some View {
    if section == "Invoices" { Button("Create Invoice") { openInvoice("Sale") } }
    if section == "Ledgers" {
      HStack {
        Button("Create") { showLedger = true }
        Button("Alter") { master = MasterRoute(id: "Alter") }
      }
    }
    if section == "Inventory" {
      HStack {
        Button("Create Stock Item") { showStock = true }
        Button("Stock Movement") { showMovement = true }
      }
    }
  }
  var railActions: [PrimeAction] {
    if section == "Purchase Orders" {
      return [
        PrimeAction(key: "F3", label: "Select Company", action: { showCompanies = true }),
        PrimeAction(key: "C", label: "Create Order", action: { purchaseOrders.create = true }),
        PrimeAction(key: "T", label: "Templates", action: { section = "Order Templates" }),
      ]
    }
    if section == "Invoice Templates" || section == "Order Templates" {
      return [
        PrimeAction(key: "F3", label: "Select Company", action: { showCompanies = true }),
        PrimeAction(key: "G", label: "Go To", action: { showGoTo = true }),
      ]
    }

    if section == "Banking" {
      return [
        PrimeAction(key: "F2", label: "Period", action: { banking.showPeriod = true }),
        PrimeAction(key: "F3", label: "Select Company", action: { showCompanies = true }),
        PrimeAction(key: "F4", label: "Bank Ledger", action: { banking.showBankPicker = true }),
        PrimeAction(
          key: "F5",
          label: banking.page == "Activities"
            ? (banking.amountView ? "Count View" : "Amount View")
            : (banking.reconciled ? "Unreconciled" : "View Reconciled"),
          action: { banking.toggleView() }),
        PrimeAction(key: "I", label: "Import Statement", action: { banking.importRequest += 1 }),
        PrimeAction(key: "F8", label: "Reconcile", action: { banking.matchRequest += 1 }),
        PrimeAction(key: "S", label: "Potential Matches", action: { banking.page = "Potential" }),
        PrimeAction(
          key: "H", label: "Change View",
          action: { banking.page = banking.page == "Summary" ? "Transactions" : "Summary" }),
        PrimeAction(key: "F12", label: "Configure", action: { banking.showConfiguration = true }),
      ]
    }

    var actions = [
      PrimeAction(
        key: "F2", label: section == "Dashboard" ? "Period" : "Date",
        action: { if section == "Dashboard" { showPeriod = true } else { showDate = true } }),
      PrimeAction(key: "F3", label: "Select Company", action: { showCompanies = true }),
    ]
    if section != "Dashboard" {
      actions += [
        PrimeAction(key: "F4", label: "Contra", action: { openVoucher("Contra") }),
        PrimeAction(key: "F5", label: "Payment", action: { openVoucher("Payment") }),
        PrimeAction(key: "F6", label: "Receipt", action: { openVoucher("Receipt") }),
        PrimeAction(key: "F7", label: "Journal", action: { openVoucher("Journal") }),
        PrimeAction(key: "F8", label: "Sales", action: { openInvoice("Sale") }),
        PrimeAction(key: "F9", label: "Purchase", action: { openInvoice("Purchase") }),
      ]
    }
    return actions
  }
  var bottomBar: some View {
    HStack(spacing: 0) {
      Button("Q: Quit") { NSApplication.shared.terminate(nil) }.padding(.horizontal, 20)
      Divider()
      Button("Esc: Gateway") { section = "Dashboard" }.padding(.horizontal, 16)
      Divider()
      Button("G: Go To") { showGoTo = true }.padding(.horizontal, 16)
      Spacer()
      Text(store.books.company).font(.system(size: 11)).foregroundStyle(.secondary)
      Text("0.6").font(.system(size: 11)).padding(.horizontal, 12)
    }.buttonStyle(.plain).frame(height: 28).background(Prime.pale).overlay(alignment: .top) {
      Prime.line.frame(height: 1)
    }
  }
  func openInvoice(_ kind: String) {
    invoiceKind = kind
    section = "Invoice Creation"
  }
  func openVoucher(_ kind: String) {
    voucherType = kind
    section = "Accounting Voucher Creation"
  }
  func route(_ target: String) {
    switch target {
    case "Create", "Alter": master = MasterRoute(id: target)
    case "New Voucher": openVoucher("Journal")
    case "Reports": showGoTo = true
    case "TallyCapital": showService = true
    case "Quit": NSApplication.shared.terminate(nil)
    default: section = target
    }
  }
  func handleKey(_ code: UInt16, _ flags: NSEvent.ModifierFlags) -> Bool {
    if section == "Purchase Orders", flags.intersection([.command, .control, .option]).isEmpty,
      !(NSApplication.shared.keyWindow?.firstResponder is NSTextView)
    {
      if code == 8 {
        purchaseOrders.create = true
        return true
      }
      if code == 17 {
        section = "Order Templates"
        return true
      }
    }

    if section == "Banking" {
      if code == 36, !(NSApplication.shared.keyWindow?.firstResponder is NSTextView) {
        banking.page = banking.page == "Activities" ? "Summary" : "Transactions"
        return true
      }
      if flags.contains(.option), code == 1 {
        banking.page = "Potential"
        return true
      }
      switch code {
      case 120:
        banking.showPeriod = true
        return true
      case 118:
        banking.showBankPicker = true
        return true
      case 96:
        banking.toggleView()
        return true
      case 100:
        banking.matchRequest += 1
        return true
      case 111:
        banking.showConfiguration = true
        return true
      case 53:
        if banking.page != "Activities" {
          banking.page = "Activities"
        } else {
          section = "Dashboard"
        }
        return true
      default: break
      }
      if flags.contains(.option), code == 31 {
        banking.importRequest += 1
        return true
      }
    }

    if section == "Dashboard", flags.intersection([.command, .control, .option]).isEmpty,
      !(NSApplication.shared.keyWindow?.firstResponder is NSTextView)
    {
      let rows = GatewayView.commands
      let index = rows.firstIndex { $0.label == gatewaySelection } ?? 0
      if code == 125 || code == 126 {
        gatewaySelection = rows[(index + (code == 125 ? 1 : -1) + rows.count) % rows.count].label
        return true
      }
      if code == 36 {
        route(rows[index].target)
        return true
      }
      let letterKeys: [UInt16: String] = [
        8: "c", 0: "a", 4: "h", 9: "v", 40: "k", 45: "n", 11: "b", 35: "p", 1: "s", 15: "r", 2: "d",
        17: "t", 31: "o",
        12: "q",
      ]
      if let letter = letterKeys[code], let row = rows.first(where: { $0.key == letter }) {
        gatewaySelection = row.label
        route(row.target)
        return true
      }

    }

    if code == 53 {
      section = "Dashboard"
      return true
    }
    if flags.contains(.option) && code == 3 {
      showFind = true
      return true
    }
    if flags.contains(.option) && code == 5 {
      showGoTo = true
      return true
    }
    switch code {
    case 122: showHelp = true
    case 120: if section == "Dashboard" { showPeriod = true } else { showDate = true }
    case 99: showCompanies = true
    case 118: openVoucher("Contra")
    case 96: openVoucher("Payment")
    case 97: openVoucher("Receipt")
    case 98: openVoucher("Journal")
    case 100: openInvoice("Sale")
    case 101: openInvoice("Purchase")
    default: return false
    }
    return true
  }
  @ViewBuilder var content: some View {
    switch section {
    case "Dashboard":
      GatewayView(
        store: store, date: workingDate, periodStart: periodStart, periodEnd: periodEnd,
        navigate: route, selection: $gatewaySelection)
    case "Purchase Orders":
      PurchaseOrdersView(
        store: store, workspace: purchaseOrders, templates: { section = "Order Templates" })
    case "Invoice Templates": DocumentTemplateEditor(store: store, order: false)
    case "Order Templates": DocumentTemplateEditor(store: store, order: true)
    case "Business Overview": FeatureOverview(navigate: route)
    case "Try Now": TryNowReport(navigate: route)
    case "Ratio Analysis": RatioView(store: store)
    case "Stock Valuation": ValuationView(store: store)
    case "Banking": BankWorkspaceView(store: store, workspace: banking)
    case "Payroll": PayrollView(store: store)
    case "Tax Summary": TaxSummaryView(store: store)
    case "Ledger Statement": StatementView(store: store)
    case "Balance Sheet": BalanceSheetView(store: store)
    case "Invoices": InvoiceRegister(store: store)
    case "Vouchers": voucherList
    case "Ledgers":
      Table(store.books.ledgers) {
        TableColumn("Ledger", value: \.name)
        TableColumn("Group", value: \.group)
        TableColumn("Balance") { a in Text(store.balance(a.id).formatted(currency)) }
      }
    case "Inventory":
      VStack(alignment: .leading) {
        Text("Stock summary").font(.headline)
        Text("Manual stock movements are not linked to accounting vouchers.").foregroundStyle(
          .secondary)
        Table(store.books.stock) {
          TableColumn("Item", value: \.name)
          TableColumn("Unit", value: \.unit)
          TableColumn("Quantity") { item in Text(store.stockBalance(item.id).formatted()) }
          TableColumn("Opening rate") { item in Text(item.rate.formatted(currency)) }
          TableColumn("Indicative value") { item in
            Text((store.stockBalance(item.id) * item.rate).formatted(currency))
          }
        }
      }
    case "Trial Balance":
      VStack {
        Table(store.books.ledgers) {
          TableColumn("Ledger", value: \.name)
          TableColumn("Debit") { a in Text(max(0, store.balance(a.id)).formatted(currency)) }
          TableColumn("Credit") { a in Text(max(0, -store.balance(a.id)).formatted(currency)) }
        }
        Text(
          "Totals: Debit \(store.books.ledgers.reduce(0){$0+max(0,store.balance($1.id))}.formatted(currency))    Credit \(store.books.ledgers.reduce(0){$0+max(0,-store.balance($1.id))}.formatted(currency))"
        ).bold()
      }
    case "Profit & Loss":
      VStack(alignment: .leading, spacing: 12) {
        Text("All-time net profit: \(profit.formatted(currency))").font(.title2)
        Table(store.books.ledgers.filter { $0.group == "Income" || $0.group == "Expense" }) {
          TableColumn("Ledger", value: \.name)
          TableColumn("Group", value: \.group)
          TableColumn("Balance") { a in
            Text((store.balance(a.id) * (a.group == "Income" ? -1 : 1)).formatted(currency))
          }
        }
      }
    default:
      VStack(alignment: .leading) {
        Text("Company name")
        TextField(
          "Company name",
          text: Binding(
            get: { store.books.company },
            set: {
              store.books.company = $0
              store.save()
            })
        ).textFieldStyle(.roundedBorder).frame(maxWidth: 350)
        Text("Books are stored locally in Application Support/LedgerDesk.").foregroundStyle(
          .secondary)
        HStack {
          Button("Export Backup") { store.exportBackup() }
          Button("Import Backup") { store.importBackup() }
        }
      }
    }
  }
  func gatewayHeading(_ label: String) -> some View {
    Text(label).font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 14).padding(
      .bottom, 4)
  }
  func gatewayButton(_ label: String, _ target: String) -> some View {
    Button(label) { section = target }.buttonStyle(.plain).padding(.vertical, 6)
  }
  var profit: Double {
    store.books.ledgers.reduce(0) { n, a in
      n + (a.group == "Income" || a.group == "Expense" ? -store.balance(a.id) : 0)
    }
  }
  func metric(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading) {
      Text(title).foregroundStyle(.secondary)
      Text(value).font(.title2.bold())
    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(
      .quaternary, in: RoundedRectangle(cornerRadius: 10))
  }
  var voucherList: some View {
    Table(store.books.vouchers.reversed()) {
      TableColumn("Date") { v in Text(v.date, style: .date) }
      TableColumn("Narration", value: \.narration)
      TableColumn("Debit") { v in Text(store.name(v.debit)) }
      TableColumn("Credit") { v in Text(store.name(v.credit)) }
      TableColumn("Amount") { v in Text(v.amount.formatted(currency)) }
    }
  }
}
struct LedgerForm: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  @State var name = ""
  @State var group = "Asset"
  @State var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("New ledger").font(.title2.bold())
      TextField("Ledger name", text: $name)
      Picker("Group", selection: $group) {
        ForEach(["Asset", "Liability", "Equity", "Income", "Expense"], id: \.self) { Text($0) }
      }
      Text(error).foregroundStyle(.red)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Save") {
          let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
          guard
            !n.isEmpty
              && !store.books.ledgers.contains(where: {
                $0.name.localizedCaseInsensitiveCompare(n) == .orderedSame
              })
          else {
            error = "Enter a unique ledger name."
            return
          }
          store.books.ledgers.append(Ledger(name: n, group: group))
          store.save()
          dismiss()
        }.buttonStyle(.borderedProminent)
      }
    }.padding(24).frame(width: 400)
  }
}
struct VoucherForm: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  @State var debit: UUID?
  @State var credit: UUID?
  @State var date = Date()
  @State var amount = ""
  @State var narration = ""
  @State var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("New voucher").font(.title2.bold())
      DatePicker("Date", selection: $date, displayedComponents: .date)
      Picker("Debit", selection: $debit) {
        Text("Select ledger").tag(Optional<UUID>.none)
        ForEach(store.books.ledgers) { Text($0.name).tag(Optional($0.id)) }
      }
      Picker("Credit", selection: $credit) {
        Text("Select ledger").tag(Optional<UUID>.none)
        ForEach(store.books.ledgers) { Text($0.name).tag(Optional($0.id)) }
      }
      TextField("Amount in INR", text: $amount)
      TextField("Narration", text: $narration)
      Text(error).foregroundStyle(.red)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Save") {
          guard let d = debit, let c = credit, d != c, let n = Double(amount), n.isFinite, n > 0
          else {
            error = "Choose different ledgers and enter a positive amount."
            return
          }
          store.books.vouchers.append(
            Voucher(date: date, debit: d, credit: c, amount: n, narration: narration))
          store.save()
          dismiss()
        }.buttonStyle(.borderedProminent)
      }
    }.padding(24).frame(width: 420)
  }
}
struct StockForm: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  @State var name = ""
  @State var unit = "Nos"
  @State var quantity = "0"
  @State var rate = "0"
  @State var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("New stock item").font(.title2.bold())
      TextField("Item name", text: $name)
      TextField("Unit, e.g. Nos or kg", text: $unit)
      TextField("Opening quantity", text: $quantity)
      TextField("Opening rate (INR)", text: $rate)
      Text(error).foregroundStyle(.red)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Save") {
          let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
          let u = unit.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !n.isEmpty, !u.isEmpty,
            !store.books.stock.contains(where: {
              $0.name.localizedCaseInsensitiveCompare(n) == .orderedSame
            }), let q = Double(quantity), let r = Double(rate), q.isFinite, r.isFinite, q >= 0,
            r >= 0
          else {
            error = "Enter a unique name, unit and valid non-negative numbers."
            return
          }
          store.books.stock.append(StockItem(name: n, unit: u, opening: q, rate: r))
          store.save()
          dismiss()
        }.buttonStyle(.borderedProminent)
      }
    }.padding(24).frame(width: 420)
  }
}
struct MovementForm: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  @State var item: UUID?
  @State var date = Date()
  @State var direction = "In"
  @State var quantity = ""
  @State var note = ""
  @State var receiptRate = ""
  @State var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Stock movement").font(.title2.bold())
      DatePicker("Date", selection: $date, displayedComponents: .date)
      Picker("Item", selection: $item) {
        Text("Select item").tag(Optional<UUID>.none)
        ForEach(store.books.stock) { Text($0.name).tag(Optional($0.id)) }
      }
      Picker("Direction", selection: $direction) {
        Text("In").tag("In")
        Text("Out").tag("Out")
      }
      TextField("Quantity", text: $quantity)
      TextField("Note", text: $note)
      if direction == "In" { TextField("Receipt cost per unit (₹, optional)", text: $receiptRate) }
      Text(error).foregroundStyle(.red)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Save") {
          guard let id = item, let q = Double(quantity), q.isFinite, q > 0 else {
            error = "Choose an item and enter a positive quantity."
            return
          }
          guard direction == "In" || store.stockBalance(id) >= q else {
            error = "Quantity exceeds stock on hand."
            return
          }
          do {
            let cost: Int64? =
              direction == "In" && !receiptRate.isEmpty ? try enteredMoney(receiptRate) : nil
            try store.transaction {
              $0.movements.append(
                StockMovement(
                  item: id, date: date, quantity: direction == "In" ? q : -q, note: note,
                  costPaise: cost))
            }
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.buttonStyle(.borderedProminent)
      }
    }.padding(24).frame(width: 420)
  }
}
@main struct LedgerDeskApp: App {
  var body: some Scene {
    WindowGroup { ContentView() }.defaultSize(width: 1280, height: 710).windowStyle(.titleBar)
  }
}
