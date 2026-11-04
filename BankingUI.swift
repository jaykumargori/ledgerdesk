import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class BankWorkspace: ObservableObject {
  @Published var page = "Activities"
  @Published var bank: UUID?
  @Published var amountView = false
  @Published var reconciled = false
  @Published var from = Date.distantPast
  @Published var through = Date()
  @Published var selectedLine: UUID?
  @Published var importRequest = 0
  @Published var matchRequest = 0
  @Published var showBankPicker = false
  @Published var showConfiguration = false
  @Published var showPeriod = false
  @Published var message = ""
  var title: String {
    switch page {
    case "Summary": return "Bank Reconciliation Summary"
    case "Potential": return "Potential Matches – Summary"
    case "Transactions":
      return reconciled ? "Bank Reconciliation – Reconciled" : "Bank Reconciliation"
    default: return "Banking Activities"
    }
  }
  func toggleView() {
    if page == "Activities" {
      amountView.toggle()
    } else {
      reconciled.toggle()
      page = "Transactions"
    }
  }
}
func bankMoney(_ paise: Decimal) -> String {
  NSDecimalNumber(decimal: paise / 100).doubleValue.formatted(currency)
}
struct BankWorkspaceView: View {
  @ObservedObject var store: Store
  @ObservedObject var workspace: BankWorkspace
  @State private var match: BankLine?
  @State private var suggestedVoucher: UUID?
  @State private var voucherFromBank: BankLine?
  var end: Date {
    Calendar.current.date(
      byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: workspace.through))!
      .addingTimeInterval(-0.001)
  }
  var bank: UUID? { workspace.bank ?? store.books.bankLedgers.first?.id }
  var snapshot: BankSnapshot? { bank.map { store.books.snapshot(bank: $0, through: end) } }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        if workspace.page != "Activities" {
          Text("Ledger:")
          Button(bankName) { workspace.showBankPicker = true }.foregroundStyle(Prime.blue)
        } else {
          Text("Banking Activities").bold()
        }
        Spacer()
        Text("As at \(workspace.through.formatted(date:.abbreviated,time:.omitted))")
      }.padding(.horizontal, 12).frame(height: 28)
      if workspace.page == "Activities" {
        activities
      } else if let snapshot {
        if workspace.page == "Summary" { summary(snapshot) } else { transactions(snapshot) }
      } else {
        VStack(alignment: .leading, spacing: 16) {
          Text("No bank ledger configured.")
          Button("Set up bank ledger") { workspace.showConfiguration = true }
        }.padding(20)
        Spacer()
      }
      if !workspace.message.isEmpty {
        Text(workspace.message).foregroundStyle(.secondary).font(.system(size: 11)).padding(10)
      }
      commands
    }.font(Prime.font).buttonStyle(.plain).background(.white)
      .onChange(of: workspace.importRequest) { _, _ in importStatement() }
      .onChange(of: workspace.matchRequest) { _, _ in reconcileSelection() }
      .sheet(isPresented: $workspace.showBankPicker) { bankPicker }
      .sheet(isPresented: $workspace.showConfiguration) {
        BankConfiguration(store: store, bank: bank)
      }
      .sheet(isPresented: $workspace.showPeriod) {
        BankPeriodView(from: $workspace.from, through: $workspace.through)
      }
      .sheet(item: $match) { line in
        BankMatchForm(store: store, line: line, suggested: suggestedVoucher)
      }
      .sheet(item: $voucherFromBank) { line in BankVoucherForm(store: store, line: line) }
      .onAppear { if workspace.bank == nil { workspace.bank = store.books.bankLedgers.first?.id } }
  }
  var bankName: String { store.books.ledgers.first { $0.id == bank }?.name ?? "Select Bank" }
  var bankPicker: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("List of Banks").foregroundStyle(.white).bold().padding(9).frame(
        maxWidth: .infinity, alignment: .leading
      ).background(Prime.blue)
      ForEach(store.books.bankLedgers) { ledger in
        Button(ledger.name) {
          workspace.bank = ledger.id
          workspace.showBankPicker = false
        }.buttonStyle(PrimeButton(selected: bank == ledger.id))
      }
      Button("Close") { workspace.showBankPicker = false }.padding(12)
    }.font(Prime.font).frame(width: 350).background(Prime.pale)
  }
  var activities: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        Text("Particulars").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
        Text("e-Payments").frame(width: 190)
        Text("Bank Reconciliation").frame(width: 310)
      }.bold().frame(height: 28).background(Prime.pale)
      HStack(spacing: 0) {
        Color.clear.frame(height: 1).frame(maxWidth: .infinity)
        Text("Pending / Sent").frame(width: 190)
        Text("Only in Books").frame(width: 155)
        Text("Only in Bank").frame(width: 155)
      }.foregroundStyle(.secondary).frame(height: 26).overlay(alignment: .bottom) {
        Prime.line.frame(height: 1)
      }
      ForEach(store.books.bankLedgers) { ledger in
        let report = store.books.snapshot(bank: ledger.id, through: end)
        Button {
          workspace.bank = ledger.id
          workspace.page = "Summary"
        } label: {
          HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
              Text(ledger.name).bold()
              if let config = store.books.bankAccounts.first(where: { $0.ledger == ledger.id }),
                !config.accountNumber.isEmpty
              {
                Text(config.accountNumber).font(.system(size: 11)).foregroundStyle(.secondary)
              }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
            Text("Not enabled").foregroundStyle(.secondary).frame(width: 190)
            Text(
              workspace.amountView
                ? bankMoney(
                  report.unmatchedBooks.reduce(Decimal(0)) {
                    $0 + Decimal(store.books.bankAmount($1, bank: ledger.id))
                  }) : String(report.unmatchedBooks.count)
            ).frame(width: 155)
            Text(
              workspace.amountView
                ? bankMoney(report.unmatchedBank.reduce(Decimal(0)) { $0 + Decimal($1.amount) })
                : String(report.unmatchedBank.count)
            ).frame(width: 155)
          }.padding(.vertical, 10).contentShape(Rectangle())
        }.background(bank == ledger.id ? Prime.yellow.opacity(0.6) : Color.white)
      }
      if store.books.bankLedgers.isEmpty {
        HStack {
          Text("No bank ledgers")
          Button("Configure bank") { workspace.showConfiguration = true }
          Spacer()
        }.padding(16)
      }
      Spacer()
      Text("Press Enter on a bank to view its reconciliation summary.").foregroundStyle(.secondary)
        .font(.system(size: 11)).padding(10)
    }
  }
  func summary(_ report: BankSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      summaryHeader
      summaryRow("Balance as per Company Books", count: nil, value: report.bookBalance, bold: true)
      Text("Unreconciled Transactions").bold().padding(12).frame(
        maxWidth: .infinity, alignment: .leading
      ).background(Prime.pale)
      Button {
        workspace.page = "Transactions"
        workspace.reconciled = false
      } label: {
        summaryRow(
          "Available Only in Books", count: report.unmatchedBooks.count,
          value: report.unmatchedBooks.reduce(Decimal(0)) {
            $0 + Decimal(store.books.bankAmount($1, bank: report.bank))
          })
      }
      Button {
        workspace.page = "Transactions"
        workspace.reconciled = false
      } label: {
        summaryRow(
          "Available Only in Bank", count: report.unmatchedBank.count,
          value: report.unmatchedBank.reduce(Decimal(0)) { $0 + Decimal($1.amount) })
      }
      summaryRow("Expected Bank Balance", count: nil, value: report.expectedBalance, bold: true)
      if let balance = report.statementBalance {
        summaryRow(
          "Balance as per Imported Statement", count: report.statements.count, value: balance)
        summaryRow("Difference", count: nil, value: report.difference!, bold: true)
      } else {
        HStack {
          Text("Statement opening balance")
          Spacer()
          Button("Set opening balance") { workspace.showConfiguration = true }.foregroundStyle(
            Prime.blue)
        }.padding(12)
        Text(
          "Enter the opening balance for the imported statement before comparing closing balances."
        ).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 12)
      }
      Button {
        workspace.page = "Transactions"
        workspace.reconciled = true
      } label: {
        summaryRow(
          "Reconciled via Linking", count: report.matched.count,
          value: report.matched.reduce(Decimal(0)) { $0 + Decimal($1.amount) })
      }.padding(.top, 18)
      Spacer()
    }
  }
  var summaryHeader: some View {
    HStack {
      Text("Particulars")
      Spacer()
      Text("Count").frame(width: 90, alignment: .trailing)
      Text("Amount").frame(width: 180, alignment: .trailing)
    }.padding(12).background(Prime.pale).overlay(alignment: .bottom) { Prime.line.frame(height: 1) }
  }
  func summaryRow(_ title: String, count: Int?, value: Decimal, bold: Bool = false) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(count.map(String.init) ?? "").frame(width: 90, alignment: .trailing)
      Text(bankMoney(value)).monospacedDigit().frame(width: 180, alignment: .trailing)
    }.font(bold ? Prime.font.bold() : Prime.font).padding(12).contentShape(Rectangle()).overlay(
      alignment: .bottom
    ) { Prime.line.opacity(0.35).frame(height: 1) }
  }
  func transactions(_ report: BankSnapshot) -> some View {
    ScrollView {
      VStack(spacing: 0) {
        transactionHeader
        if workspace.reconciled {
          sectionHeader("Reconciled via Linking (\(report.matched.count))")
          ForEach(report.matched) { line in statementRow(line) }
        } else {
          sectionHeader("Available Only in Books (\(report.unmatchedBooks.count))")
          ForEach(report.unmatchedBooks.filter { $0.date >= workspace.from }) { voucher in
            bookRow(voucher, bank: report.bank)
          }
          sectionHeader("Available Only in Bank (\(report.unmatchedBank.count))")
          ForEach(report.unmatchedBank.filter { $0.date >= workspace.from }) { line in
            statementRow(line)
          }
        }
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
  func potentialMatches(_ report: BankSnapshot) -> some View {
    let suggestions = store.books.bankSuggestions(bank: report.bank, through: end)
    return ScrollView {
      VStack(spacing: 0) {
        Text(
          "Suggestions use matching signed amounts within 30 days. Review each pair before reconciling."
        ).font(.system(size: 11)).foregroundStyle(.secondary).padding(12)
        ForEach([true, false], id: \.self) { sameDay in
          let group = suggestions.filter { $0.sameDay == sameDay }
          sectionHeader(
            "\(sameDay ? "Same Date & Amount" : "Same Amount within 30 Days") (\(group.count))")
          ForEach(group) { candidate in
            Button {
              workspace.selectedLine = candidate.line.id
              suggestedVoucher = candidate.voucher.id
              match = candidate.line
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                HStack {
                  Text(candidate.voucher.date, style: .date)
                  Text(candidate.voucher.narration)
                  Spacer()
                  Text(candidate.voucher.amount.formatted(currency))
                }
                HStack {
                  Text(candidate.line.date, style: .date)
                  Text(candidate.line.description)
                  Spacer()
                  Text(bankMoney(Decimal(candidate.line.amount)))
                }.foregroundStyle(Prime.blue)
              }.padding(10).frame(maxWidth: .infinity, alignment: .leading).contentShape(
                Rectangle())
            }.overlay(alignment: .bottom) { Prime.line.opacity(0.3).frame(height: 1) }
          }
        }
      }
    }
  }
  var transactionHeader: some View {
    HStack(spacing: 8) {
      Text("Date").frame(width: 86, alignment: .leading)
      Text("Particulars").frame(maxWidth: .infinity, alignment: .leading)
      Text("Reference").frame(width: 120, alignment: .leading)
      Text("Deposit").frame(width: 120, alignment: .trailing)
      Text("Withdrawal").frame(width: 120, alignment: .trailing)
    }.padding(.horizontal, 10).frame(height: 26).background(Prime.pale)
  }
  func sectionHeader(_ title: String) -> some View {
    Text(title).bold().padding(.horizontal, 10).padding(.vertical, 4).frame(
      maxWidth: .infinity, alignment: .leading
    ).background(Prime.pale).overlay(alignment: .bottom) { Prime.line.frame(height: 1) }
  }
  func bookRow(_ voucher: Voucher, bank: UUID) -> some View {
    let amount = store.books.bankAmount(voucher, bank: bank)
    return HStack(spacing: 8) {
      Text(voucher.date.formatted(.dateTime.day().month(.abbreviated).year())).frame(
        width: 86, alignment: .leading)
      Text(voucher.narration).frame(maxWidth: .infinity, alignment: .leading)
      Text("").frame(width: 120)
      Text(amount > 0 ? bankMoney(Decimal(amount)) : "").frame(width: 120, alignment: .trailing)
      Text(amount < 0 ? bankMoney(-Decimal(amount)) : "").frame(width: 120, alignment: .trailing)
    }.padding(.horizontal, 10).padding(.vertical, 5)
  }
  func statementRow(_ line: BankLine) -> some View {
    Button {
      workspace.selectedLine = line.id
      suggestedVoucher = nil
      match = line
    } label: {
      HStack(spacing: 8) {
        Text(line.date.formatted(.dateTime.day().month(.abbreviated).year())).frame(
          width: 86, alignment: .leading)
        Text(line.description).frame(maxWidth: .infinity, alignment: .leading)
        Text(line.reference).frame(width: 120, alignment: .leading)
        Text(line.amount > 0 ? bankMoney(Decimal(line.amount)) : "").frame(
          width: 120, alignment: .trailing)
        Text(line.amount < 0 ? bankMoney(-Decimal(line.amount)) : "").frame(
          width: 120, alignment: .trailing)
      }.foregroundStyle(Prime.blue).padding(.horizontal, 10).padding(.vertical, 5).contentShape(
        Rectangle())
    }.background(workspace.selectedLine == line.id ? Prime.yellow.opacity(0.6) : Color.white)
  }
  var commands: some View {
    HStack(spacing: 18) {
      Button("Import Statement") { importStatement() }
      Button("Reconcile Exact Matches") { autoMatch() }.disabled(bank == nil)
      if workspace.page != "Activities" {
        Button("Summary") { workspace.page = "Summary" }
        Button("Transactions") { workspace.page = "Transactions" }
        Button("Potential Matches") { workspace.page = "Potential" }
        Button("Create Voucher") { createFromSelection() }
      }
      Spacer()
      Button("Configure") { workspace.showConfiguration = true }
    }.padding(10).background(Prime.pale).overlay(alignment: .top) { Prime.line.frame(height: 1) }
  }
  func importStatement() {
    guard let bank else {
      workspace.showConfiguration = true
      return
    }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.commaSeparatedText, .plainText]
    panel.message = "Choose a statement with columns: id,date,description,amount"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let text = try String(contentsOf: url, encoding: .utf8)
      try store.transaction { try $0.importStatement(text, bank: bank) }
      workspace.message = "Statement imported"
      workspace.page = "Summary"
    } catch { workspace.message = error.localizedDescription }
  }
  func autoMatch() {
    guard let bank else { return }
    do {
      try store.transaction { try $0.autoMatch(bank: bank) }
      workspace.message = "Unique same-date and amount matches reconciled."
    } catch { workspace.message = error.localizedDescription }
  }
  func reconcileSelection() {
    guard let id = workspace.selectedLine,
      let line = store.books.bankLines.first(where: { $0.id == id })
    else {
      workspace.message = "Choose a bank transaction to reconcile."
      workspace.page = "Transactions"
      return
    }
    match = line
  }
  func createFromSelection() {
    guard let id = workspace.selectedLine,
      let line = store.books.bankLines.first(where: { $0.id == id }), line.voucher == nil
    else {
      workspace.message = "Select an unmatched bank transaction first."
      return
    }
    voucherFromBank = line
  }
}
struct BankPeriodView: View {
  @Environment(\.dismiss) var dismiss
  @Binding var from: Date
  @Binding var through: Date
  @State private var start = Date()
  @State private var end = Date()
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Banking Period").font(.headline)
      DatePicker("Transactions from", selection: $start, displayedComponents: .date)
      DatePicker("As at", selection: $end, displayedComponents: .date)
      Text(
        "Balances include all entries through the as-at date. The from date filters the transaction detail."
      ).font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Button("Accept") {
          from = start
          through = end
          dismiss()
        }.disabled(start > end)
      }
    }.padding(24).frame(width: 430).onAppear {
      start =
        from == .distantPast
        ? Calendar.current.date(byAdding: .year, value: -1, to: through)! : from
      end = through
    }
  }
}
struct BankConfiguration: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  let bank: UUID?
  @State private var ledger: UUID?
  @State private var name = ""
  @State private var number = ""
  @State private var opening = ""
  @State private var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Bank Configuration").font(.headline)
      PrimeLookup(
        selection: $ledger,
        options: store.books.ledgers.filter { $0.group == "Asset" }.map {
          PrimeOption(id: $0.id, name: $0.name)
        })
      TextField("Bank name", text: $name)
      TextField("Account number (optional)", text: $number)
      TextField("Statement opening balance, ₹ (optional; negative allowed)", text: $opening)
      Text(
        "Opening balance is the balance immediately before the first imported statement transaction. Leaving it blank keeps the statement balance unknown."
      ).font(.caption).foregroundStyle(.secondary)
      Text(error).foregroundStyle(.red)
      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Button("Accept") {
          do {
            guard let id = ledger else { throw BookError.invalid("Choose an asset ledger.") }
            let value: Int64?
            if opening.isEmpty {
              value = nil
            } else {
              let negative = opening.hasPrefix("-")
              value =
                try enteredMoney(negative ? String(opening.dropFirst()) : opening)
                * (negative ? -1 : 1)
            }
            try store.transaction {
              try $0.saveBankAccount(
                BankAccount(
                  ledger: id, bankName: name, accountNumber: number, statementOpening: value))
            }
            dismiss()
          } catch { self.error = error.localizedDescription }
        }
      }
    }.padding(24).frame(width: 540).onAppear {
      ledger = bank
      if let profile = store.books.bankAccounts.first(where: { $0.ledger == bank }) {
        name = profile.bankName
        number = profile.accountNumber
        opening =
          profile.statementOpening.map { NSDecimalNumber(decimal: Decimal($0) / 100).stringValue }
          ?? ""
      }
    }
  }
}
struct BankVoucherForm: View {
  @Environment(\.dismiss) var dismiss
  @ObservedObject var store: Store
  let line: BankLine
  @State private var ledger: UUID?
  @State private var note = ""
  @State private var error = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Create Voucher from Bank Entry").font(.headline)
      Text(line.description)
      Text(bankMoney(Decimal(line.amount)))
      PrimeLookup(
        selection: $ledger,
        options: store.books.ledgers.filter { $0.id != line.bank }.map {
          PrimeOption(id: $0.id, name: $0.name)
        })
      TextField("Narration", text: $note)
      Text(error).foregroundStyle(.red)
      HStack {
        Button("Cancel") { dismiss() }
        Spacer()
        Button("Accept") {
          do {
            guard let opposite = ledger else {
              throw BookError.invalid("Choose the corresponding ledger.")
            }
            try store.transaction { books in
              guard let index = books.bankLines.firstIndex(where: { $0.id == line.id }),
                books.bankLines[index].voucher == nil
              else { throw BookError.invalid("Bank entry is already matched.") }
              let voucher = Voucher(
                date: line.date, debit: line.amount > 0 ? line.bank : opposite,
                credit: line.amount > 0 ? opposite : line.bank,
                amount: NSDecimalNumber(decimal: abs(Decimal(line.amount)) / 100).doubleValue,
                narration: note.isEmpty ? line.description : note)
              books.vouchers.append(voucher)
              try books.matchBank(line: line.id, voucher: voucher.id)
            }
            dismiss()
          } catch { self.error = error.localizedDescription }
        }
      }
    }.padding(24).frame(width: 520)
  }
}
