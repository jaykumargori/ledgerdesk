import AppKit
import SwiftUI

enum Prime {
  static let blue = Color(red: 0.235, green: 0.392, blue: 0.647)
  static let pale = Color(red: 0.892, green: 0.949, blue: 0.984)
  static let line = Color(red: 0.72, green: 0.81, blue: 0.86)
  static let yellow = Color(red: 1, green: 0.80, blue: 0.31)
  static let ink = Color(red: 0.08, green: 0.10, blue: 0.14)
  static let label = Color(red: 0.44, green: 0.59, blue: 0.67)
  static let font = Font.custom("Arial", size: 13)
}
struct PrimeButton: ButtonStyle {
  var selected = false
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.foregroundStyle(Prime.ink).frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12).padding(.vertical, 2)
      .background(selected || configuration.isPressed ? Prime.yellow : Color.clear)
      .contentShape(Rectangle())
  }
}
struct GatewayRow: Identifiable {
  var id: String { label }
  var label: String
  var target: String
  var key: String
}
struct GatewayView: View {
  @ObservedObject var store: Store
  let date: Date
  let periodStart: Date
  let periodEnd: Date
  let navigate: (String) -> Void
  @Binding var selection: String
  @FocusState private var menuFocus: Bool
  private static let groups: [(String, [GatewayRow])] = [
    (
      "MASTERS",
      [
        GatewayRow(label: "Create", target: "Create", key: "c"),
        GatewayRow(label: "Alter", target: "Alter", key: "a"),
        GatewayRow(label: "Chart of Accounts", target: "Ledgers", key: "h"),
      ]
    ),
    (
      "TRANSACTIONS",
      [
        GatewayRow(label: "Vouchers", target: "New Voucher", key: "v"),
        GatewayRow(label: "Day Book", target: "Vouchers", key: "k"),
      ]
    ),
    (
      "UTILITIES",
      [
        GatewayRow(label: "Banking", target: "Banking", key: "n"),
      ]
    ),
    (
      "REPORTS",
      [
        GatewayRow(label: "Balance Sheet", target: "Balance Sheet", key: "b"),
        GatewayRow(label: "Profit & Loss A/c", target: "Profit & Loss", key: "p"),
        GatewayRow(label: "Stock Summary", target: "Inventory", key: "s"),
        GatewayRow(label: "Ratio Analysis", target: "Ratio Analysis", key: "r"),
      ]
    ),
  ]
  static var commands: [GatewayRow] {
    groups.flatMap { $0.1 } + [
      GatewayRow(label: "Display More Reports", target: "Reports", key: "d"),
      GatewayRow(label: "Dashboard", target: "Business Overview", key: "o"),
      GatewayRow(label: "Quit", target: "Quit", key: "q"),
    ]
  }
  func dateText(_ value: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "d-MMM-yy"
    return f.string(from: value)
  }
  var period: String { "\(dateText(periodStart)) to \(dateText(periodEnd))" }
  var body: some View {
    GeometryReader { geo in
      HStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 0) {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
              Text("CURRENT PERIOD").foregroundStyle(Prime.label).font(.system(size: 11))
              Text(period).bold()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
              Text("CURRENT DATE").foregroundStyle(Prime.label).font(.system(size: 11))
              Text(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year())).bold()
            }
          }.padding(.horizontal, 24).padding(.top, 36).padding(.bottom, 28)
          HStack {
            Text("NAME OF COMPANY")
            Spacer()
            Text("DATE OF LAST ENTRY")
          }.font(.system(size: 11)).foregroundStyle(Prime.label).padding(.horizontal, 24).padding(
            .vertical, 5
          ).overlay(alignment: .top) { Prime.line.frame(height: 1) }.overlay(alignment: .bottom) {
            Prime.line.frame(height: 1)
          }
          HStack(alignment: .top) {
            Text(store.books.company).bold()
            Spacer()
            Text(store.books.vouchers.map(\.date).max().map(dateText) ?? "No Vouchers Entered")
              .bold()
          }.padding(.horizontal, 24).padding(.top, 14)
          Spacer()
          TryNowTile(navigate: navigate).padding(.horizontal, 24).padding(.bottom, 24)
        }.frame(width: geo.size.width * 0.50).overlay(alignment: .trailing) {
          Prime.line.opacity(0.6).frame(width: 1)
        }
        VStack {
          Spacer(minLength: 24)
          VStack(alignment: .leading, spacing: 0) {
            Text("Gateway of LedgerDesk").foregroundStyle(.white).frame(maxWidth: .infinity)
              .padding(.vertical, 5).background(Prime.blue)
            VStack(alignment: .leading, spacing: 0) {
              ForEach(Self.groups.indices, id: \.self) { index in
                Text(Self.groups[index].0).font(.system(size: 11)).foregroundStyle(Prime.label)
                  .padding(
                    .leading, 112
                  ).padding(.top, index == 0 ? 25 : 16).padding(.bottom, 8)
                ForEach(Self.groups[index].1) { row in menuRow(row) }
              }
              menuRow(rows[rows.count - 3]).padding(.top, 16)
              menuRow(rows[rows.count - 2])
              menuRow(rows[rows.count - 1]).padding(.top, 24).padding(.bottom, 26)
            }
          }.frame(width: min(368, geo.size.width * 0.44)).background(Prime.pale).overlay(
            Rectangle().stroke(Prime.line, lineWidth: 1))
          Spacer(minLength: 24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }.background(.white).foregroundStyle(Prime.ink).font(Prime.font)
      .onKeyPress(.upArrow) {
        move(-1)
        return .handled
      }
      .onKeyPress(.downArrow) {
        move(1)
        return .handled
      }
      .onKeyPress(.return) {
        if let row = rows.first(where: { $0.label == selection }) { navigate(row.target) }
        return .handled
      }
      .focusable().focusEffectDisabled().focused($menuFocus).onAppear { menuFocus = true }
      .onKeyPress(characters: CharacterSet.letters) { press in
        if let row = rows.first(where: { $0.key == press.characters.lowercased() }) {
          selection = row.label
          navigate(row.target)
          return .handled
        }
        return .ignored
      }
  }
  var rows: [GatewayRow] { Self.commands }
  func move(_ amount: Int) {
    let index = rows.firstIndex(where: { $0.label == selection }) ?? 0
    selection = rows[(index + amount + rows.count) % rows.count].label
  }
  func menuRow(_ row: GatewayRow) -> some View {
    Button {
      selection = row.label
      navigate(row.target)
    } label: {
      Text(row.label).padding(.leading, 100).frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(PrimeButton(selected: selection == row.label))
    .onHover { if $0 { selection = row.label } }
  }
}
struct PrimeAction: Identifiable {
  var id: String { key + label }
  var key: String
  var label: String
  var action: () -> Void
}
struct PrimeRail: View {
  let actions: [PrimeAction]
  var body: some View {
    VStack(spacing: 2) {
      ForEach(actions) { item in
        Button(action: item.action) {
          HStack(spacing: 3) {
            Text(item.key + ":").foregroundStyle(Prime.label).bold()
            Text(item.label)
            Spacer()
          }.font(Prime.font).padding(.horizontal, 5).frame(height: 25).background(.white)
        }.buttonStyle(.plain).overlay(alignment: .bottom) { Prime.line.frame(height: 1) }
      }
      Spacer()
    }.padding(.top, 2).frame(width: 146).background(Prime.pale).overlay(alignment: .leading) {
      Prime.line.frame(width: 1)
    }
  }
}
struct MasterRoute: Identifiable { var id: String }
struct MasterHub: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  let mode: String
  @State private var choice = ""
  var body: some View {
    Group {
      if choice == "Ledger" {
        LedgerForm(store: store)
      } else if choice == "Stock Item" {
        StockForm(store: store)
      } else if choice == "Employee" {
        EmployeeForm(store: store)
      } else if mode == "Alter" {
        AlterLedgerView(store: store)
      } else {
        VStack(alignment: .leading, spacing: 0) {
          Text("Master Creation").foregroundStyle(.white).padding(8).frame(
            maxWidth: .infinity, alignment: .leading
          ).background(Prime.blue)
          ForEach(["Ledger", "Stock Item", "Employee"], id: \.self) { label in
            Button(label) { choice = label }.buttonStyle(PrimeButton()).padding(.vertical, 6)
          }
          Button("Close") { dismiss() }.padding(12)
        }.frame(width: 360).background(Prime.pale)
      }
    }.environment(\.colorScheme, .light)
  }
}
struct AlterLedgerView: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  @State private var selection: UUID?
  @State private var name = ""
  @State private var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Ledger Alteration").font(.title2)
      Picker("Ledger", selection: $selection) {
        Text("Select ledger").tag(Optional<UUID>.none)
        ForEach(store.books.ledgers) { Text($0.name).tag(Optional($0.id)) }
      }.onChange(of: selection) { _, id in
        name = store.books.ledgers.first { $0.id == id }?.name ?? ""
      }
      TextField("Name", text: $name)
      Text("Account group is retained for existing transactions.").foregroundStyle(.secondary)
      Text(error).foregroundStyle(.red)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
        Button("Accept") {
          do {
            let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = selection, !n.isEmpty,
              !store.books.ledgers.contains(where: {
                $0.id != id && $0.name.localizedCaseInsensitiveCompare(n) == .orderedSame
              })
            else { throw BookError.invalid("Choose a ledger and a unique name.") }
            try store.transaction { books in
              if let index = books.ledgers.firstIndex(where: { $0.id == id }) {
                books.ledgers[index].name = n
              }
            }
            dismiss()
          } catch { self.error = error.localizedDescription }
        }
      }
    }
    .padding(24).frame(width: 440)
  }
}
struct GoToView: View {
  @Environment(\.dismiss) var dismiss
  let sections: [String]
  let navigate: (String) -> Void
  @State private var query = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Go To").foregroundStyle(.white).padding(9).frame(
        maxWidth: .infinity, alignment: .leading
      ).background(Prime.blue)
      TextField("Search reports and screens", text: $query).textFieldStyle(.roundedBorder).padding(
        12)
      ScrollView {
        VStack(spacing: 1) {
          ForEach(
            sections.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) },
            id: \.self
          ) { target in
            Button(target) {
              navigate(target)
              dismiss()
            }.buttonStyle(PrimeButton()).padding(.vertical, 4)
          }
        }
      }
      HStack {
        Spacer()
        Button("Close") { dismiss() }
      }.padding(12)
    }.frame(width: 420, height: 480).background(Prime.pale).environment(\.colorScheme, .light)
  }
}
struct WorkingDateView: View {
  @Environment(\.dismiss) var dismiss
  @Binding var date: Date
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Change Date").font(.headline)
      DatePicker("Current date", selection: $date, displayedComponents: .date)
      HStack {
        Spacer()
        Button("Accept") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }.padding(24).frame(width: 350)
  }
}
struct PrimeKeys: NSViewRepresentable {
  let handle: (UInt16, NSEvent.ModifierFlags) -> Bool
  func makeNSView(context: Context) -> NSView {
    context.coordinator.start(handle)
    return NSView()
  }
  func updateNSView(_ view: NSView, context: Context) { context.coordinator.handle = handle }
  func makeCoordinator() -> Coordinator { Coordinator() }
  static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }
  final class Coordinator {
    var monitor: Any?
    var handle: ((UInt16, NSEvent.ModifierFlags) -> Bool)?
    func start(_ callback: @escaping (UInt16, NSEvent.ModifierFlags) -> Bool) {
      handle = callback
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard event.window?.attachedSheet == nil, event.window === NSApplication.shared.mainWindow
        else { return event }
        return self?.handle?(event.keyCode, event.modifierFlags) == true ? nil : event
      }
    }
    func stop() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}
struct PrimeVoucherEditor: View {
  @ObservedObject var store: Store
  let date: Date
  let kind: String
  let onClose: () -> Void
  @State private var debit: UUID?
  @State private var credit: UUID?
  @State private var amount = ""
  @State private var note = ""
  @State private var error = ""
  @State private var saved = ""
  @FocusState private var amountFocus: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(kind).foregroundStyle(.white).bold().frame(width: 150).padding(.vertical, 5)
          .background(Prime.blue)
        Text("No. \(store.books.vouchers.count+1)").padding(.leading, 12)
        Spacer()
        Text(date.formatted(.dateTime.day().month(.abbreviated).year())).bold()
      }.padding(.trailing, 16).padding(.top, 10)
      Text(date.formatted(.dateTime.weekday(.wide))).frame(
        maxWidth: .infinity, alignment: .trailing
      ).padding(.trailing, 16).padding(.bottom, 24)
      HStack {
        Text("Particulars")
        Spacer()
        Text("Debit").frame(width: 150, alignment: .trailing)
        Text("Credit").frame(width: 150, alignment: .trailing)
      }.padding(.horizontal, 16).padding(.vertical, 6).overlay(alignment: .top) {
        Prime.line.frame(height: 1)
      }.overlay(alignment: .bottom) { Prime.line.frame(height: 1) }
      HStack {
        Text("Dr").frame(width: 25)
        account($debit)
        Spacer()
        TextField("0.00", text: $amount).focused($amountFocus).multilineTextAlignment(.trailing)
          .frame(width: 140)
        Color.clear.frame(width: 150, height: 1)
      }.padding(16)
      HStack {
        Text("Cr").frame(width: 25)
        account($credit)
        Spacer()
        Color.clear.frame(width: 140, height: 1)
        Text((Double(amount) ?? 0).formatted(currency)).frame(width: 150, alignment: .trailing)
      }.padding(.horizontal, 16)
      Text(error).foregroundStyle(.red).padding(16)
      Text(saved).foregroundStyle(.green).padding(.horizontal, 16)
      Spacer()
      HStack(alignment: .top) {
        Text("Narration:").bold()
        TextField("", text: $note, axis: .vertical).lineLimit(2...4).textFieldStyle(.plain)
      }.padding(16)
      HStack {
        Spacer()
        Text((Double(amount) ?? 0).formatted(currency)).frame(width: 150, alignment: .trailing)
        Text((Double(amount) ?? 0).formatted(currency)).frame(width: 150, alignment: .trailing)
      }.padding(16).overlay(alignment: .top) { Prime.line.frame(height: 1) }
      HStack {
        Button("Esc: Cancel", action: onClose)
        Spacer()
        Button("A: Accept") { accept() }.keyboardShortcut("a", modifiers: .control)
      }.buttonStyle(.plain).padding(12).background(Prime.pale)
    }.font(Prime.font).background(.white).textFieldStyle(.plain)
  }
  func account(_ selection: Binding<UUID?>) -> some View {
    PrimeLookup(
      selection: selection,
      options: store.books.ledgers.map { PrimeOption(id: $0.id, name: $0.name) }
    ).frame(width: 310)
  }
  func accept() {
    do {
      guard let d = debit, let c = credit, d != c else {
        throw BookError.invalid("Choose different debit and credit ledgers.")
      }
      let value = try enteredMoney(amount)
      guard value > 0 else { throw BookError.invalid("Enter a positive amount.") }
      try store.transaction {
        $0.vouchers.append(
          Voucher(
            date: date, debit: d, credit: c, amount: Double(value) / 100,
            narration: "\(kind) · \(note)"))
      }
      error = ""
      saved = "Voucher accepted"
      amount = ""
      note = ""
      debit = nil
      credit = nil
    } catch {
      self.error = error.localizedDescription
      saved = ""
    }
  }
}
struct RatioView: View {
  @ObservedObject var store: Store
  func total(_ group: String) -> Double {
    store.books.ledgers.filter { $0.group == group }.reduce(0) { $0 + store.balance($1.id) }
  }
  func ratio(_ a: Double, _ b: Double) -> String {
    abs(b) < 0.000001 ? "—" : (a / b).formatted(.number.precision(.fractionLength(2)))
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("All-time ratios from posted accounting balances").foregroundStyle(.secondary)
      row("Assets / liabilities", ratio(total("Asset"), -total("Liability")))
      row("Liabilities / equity", ratio(-total("Liability"), -total("Equity")))
      row("Net profit / income", ratio(-total("Income") - total("Expense"), -total("Income")))
      Text(
        "Undefined ratios are shown as —. Inventory valuation adjustments are not automatically included."
      ).foregroundStyle(.secondary).font(.caption)
      Spacer()
    }
  }
  func row(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(value).monospacedDigit()
    }.padding(10).overlay(alignment: .bottom) { Prime.line.frame(height: 1) }
  }
}
struct PrimeOption: Identifiable {
  var id: UUID
  var name: String
}
struct PrimeLookup: View {
  @Binding var selection: UUID?
  let options: [PrimeOption]
  var title = "List of Ledger Accounts"
  var prompt = "Select ledger"
  @State private var showing = false
  var body: some View {
    Button {
      showing = true
    } label: {
      Text(options.first { $0.id == selection }?.name ?? prompt).frame(
        maxWidth: .infinity, alignment: .leading
      ).padding(.horizontal, 6).frame(height: 24).background(
        selection == nil ? Prime.yellow.opacity(0.45) : Color.clear)
    }.buttonStyle(.plain)
      .popover(isPresented: $showing, arrowEdge: .top) {
        PrimeLookupList(
          options: options, title: title,
          select: {
            selection = $0
            showing = false
          })
      }
  }
}
struct PrimeLookupList: View {
  let options: [PrimeOption]
  let title: String
  let select: (UUID) -> Void
  @State private var query = ""
  @State private var highlighted: UUID?
  @FocusState private var focused: Bool
  var filtered: [PrimeOption] {
    options.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title).bold().padding(8).frame(maxWidth: .infinity, alignment: .leading).background(
        Prime.blue
      ).foregroundStyle(.white)
      TextField("Search", text: $query).textFieldStyle(.plain).padding(8).background(.white)
        .focused($focused).onChange(of: query) { _, _ in highlighted = filtered.first?.id }
      ScrollView {
        VStack(spacing: 0) {
          ForEach(filtered) { option in
            Button {
              select(option.id)
            } label: {
              Text(option.name)
            }
            .buttonStyle(PrimeButton(selected: highlighted == option.id))
            .onHover { if $0 { highlighted = option.id } }
          }
        }
      }.frame(minHeight: 80, maxHeight: 280)
      Text("↑ ↓ Select    Enter Accept").font(.system(size: 10)).foregroundStyle(.secondary)
        .padding(8)
    }.frame(width: 300).font(Prime.font).background(Prime.pale).foregroundStyle(Prime.ink)
      .environment(\.colorScheme, .light)
      .onAppear {
        focused = true
        highlighted = filtered.first?.id
      }
      .onKeyPress(.downArrow) {
        move(1)
        return .handled
      }
      .onKeyPress(.upArrow) {
        move(-1)
        return .handled
      }
      .onKeyPress(.return) {
        if let id = highlighted ?? filtered.first?.id { select(id) }
        return .handled
      }
  }
  func move(_ direction: Int) {
    guard !filtered.isEmpty else { return }
    let current = filtered.firstIndex { $0.id == highlighted } ?? 0
    highlighted = filtered[(current + direction + filtered.count) % filtered.count].id
  }
}
