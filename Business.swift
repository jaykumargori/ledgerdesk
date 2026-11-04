import Foundation

func paise(_ value: Decimal) -> Int64 {
  var value = value
  var rounded = Decimal()
  NSDecimalRound(&rounded, &value, 0, .plain)
  return NSDecimalNumber(decimal: rounded).int64Value
}
struct TaxCharge: Codable, Identifiable {
  var id = UUID()
  var name: String
  var basisPoints: Int
  var ledger: UUID
}
struct Employee: Codable, Identifiable {
  var id = UUID()
  var name: String
  var basic: Int64
  var allowance: Int64
  var deduction: Int64
}
struct PayRun: Codable, Identifiable {
  var id = UUID()
  var employee: UUID
  var name: String
  var period: String
  var date: Date
  var gross: Int64
  var deduction: Int64
  var net: Int64
}
struct BankLine: Codable, Identifiable {
  var id = UUID()
  var bank: UUID
  var reference: String
  var date: Date
  var description: String
  var amount: Int64
  var voucher: UUID?
}
struct Valuation {
  var quantity: Double
  var value: Decimal
  var assumedCosts: Int
}
extension Invoice {
  var taxPaise: Int64 { (taxes ?? []).reduce(0) { $0 + taxAmount($1) } }
  func taxAmount(_ charge: TaxCharge) -> Int64 {
    paise(Decimal(subtotalPaise) * Decimal(charge.basisPoints) / 10_000)
  }
}
extension Books {
  mutating func postPayroll(
    period: String, date: Date, expense: UUID, payable: UUID, deductions: UUID
  ) throws {
    let parts = period.split(separator: "-")
    guard parts.count == 2, parts[0].count == 4, let year = Int(parts[0]),
      (1900...9999).contains(year), parts[1].count == 2, let month = Int(parts[1]),
      (1...12).contains(month), !employees.isEmpty,
      ledgers.contains(where: { $0.id == expense && $0.group == "Expense" }),
      ledgers.contains(where: { $0.id == payable && $0.group == "Liability" }),
      ledgers.contains(where: { $0.id == deductions && $0.group == "Liability" }),
      payable != deductions
    else {
      throw BookError.invalid(
        "Enter a YYYY-MM period and separate expense, salary-payable and deductions-payable ledgers."
      )
    }
    guard !payruns.contains(where: { $0.period == period }) else {
      throw BookError.invalid("Payroll for this period has already been posted.")
    }
    guard
      employees.allSatisfy({
        $0.basic >= 0 && $0.allowance >= 0 && $0.basic <= 100_000_000_000
          && $0.allowance <= 100_000_000_000 && $0.basic + $0.allowance > 0 && $0.deduction >= 0
          && $0.deduction <= $0.basic + $0.allowance
      })
    else { throw BookError.invalid("Invalid employee earnings or deductions.") }
    for employee in employees {
      let gross = employee.basic + employee.allowance
      let net = gross - employee.deduction
      let memo = "Payroll \(period) · \(employee.name)"
      if net > 0 {
        vouchers.append(
          Voucher(
            date: date, debit: expense, credit: payable, amount: Double(net) / 100, narration: memo)
        )
      }
      if employee.deduction > 0 {
        vouchers.append(
          Voucher(
            date: date, debit: expense, credit: deductions,
            amount: Double(employee.deduction) / 100, narration: memo + " · deductions"))
      }
      payruns.append(
        PayRun(
          employee: employee.id, name: employee.name, period: period, date: date, gross: gross,
          deduction: employee.deduction, net: net))
    }
  }
  func bankAmount(_ voucher: Voucher, bank: UUID) -> Int64 {
    paise(Decimal(voucher.amount) * 100)
      * (voucher.debit == bank ? 1 : voucher.credit == bank ? -1 : 0)
  }
  mutating func matchBank(line: UUID, voucher: UUID?) throws {
    guard let index = bankLines.firstIndex(where: { $0.id == line }) else {
      throw BookError.invalid("Statement row missing.")
    }
    if let id = voucher {
      guard let v = vouchers.first(where: { $0.id == id }),
        bankAmount(v, bank: bankLines[index].bank) == bankLines[index].amount,
        !bankLines.contains(where: {
          $0.bank == bankLines[index].bank && $0.voucher == id && $0.id != line
        })
      else {
        throw BookError.invalid(
          "Match requires the same signed amount and a voucher not already matched to this bank.")
      }
    }
    bankLines[index].voucher = voucher
  }
  mutating func autoMatch(bank: UUID) throws {
    let pending = bankLines.filter { $0.bank == bank && $0.voucher == nil }
    let used = Set(bankLines.filter { $0.bank == bank }.compactMap(\.voucher))
    let candidates = vouchers.filter {
      !used.contains($0.id) && ($0.debit == bank || $0.credit == bank)
    }
    for line in pending {
      let matches = candidates.filter {
        bankAmount($0, bank: bank) == line.amount
          && Calendar.current.isDate($0.date, inSameDayAs: line.date)
      }
      if matches.count == 1, let match = matches.first {
        let competing = pending.filter {
          $0.amount == line.amount && Calendar.current.isDate($0.date, inSameDayAs: line.date)
        }
        if competing.count == 1 { try matchBank(line: line.id, voucher: match.id) }
      }
    }
  }
  mutating func importStatement(_ text: String, bank: UUID) throws {
    guard ledgers.contains(where: { $0.id == bank && $0.group == "Asset" }) else {
      throw BookError.invalid("Select a bank asset ledger.")
    }
    let rows = try CSV.read(text)
    guard rows.first?.map({ $0.lowercased() }) == ["id", "date", "description", "amount"] else {
      throw BookError.invalid(
        "CSV header must be id,date,description,amount. Amounts use positive receipts and negative payments."
      )
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    var next: [BankLine] = []
    var seen = Set(bankLines.filter { $0.bank == bank }.map(\.reference))
    for (offset, row) in rows.dropFirst().enumerated() {
      guard row.count == 4, !row[0].isEmpty, !seen.contains(row[0]),
        let date = formatter.date(from: row[1]), formatter.string(from: date) == row[1],
        row[3].range(of: "^-?[0-9]+(?:\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
        let amount = Decimal(string: row[3], locale: Locale(identifier: "en_US_POSIX")),
        amount != 0, abs(amount) <= 1_000_000_000
      else {
        throw BookError.invalid("Invalid or duplicate CSV row \(offset+2). Import was cancelled.")
      }
      let scaled = amount * 100
      guard Decimal(paise(scaled)) == scaled else {
        throw BookError.invalid("CSV amounts support two decimal places.")
      }
      next.append(
        BankLine(
          bank: bank, reference: row[0], date: date, description: row[2], amount: paise(scaled)))
      seen.insert(row[0])
    }
    guard !next.isEmpty else { throw BookError.invalid("No statement transactions found.") }
    bankLines.append(contentsOf: next)
  }
  func valuation(item: StockItem, method: String, through: Date) throws -> Valuation {
    var quantity = item.opening
    var value = Decimal(item.opening) * Decimal(item.rate) * 100
    var lots: [(Double, Decimal)] =
      item.opening > 0 ? [(item.opening, Decimal(item.rate) * 100)] : []
    var assumed = 0
    let ordered = movements.enumerated().filter {
      $0.element.item == item.id && $0.element.date <= through
    }.sorted { a, b in
      a.element.date == b.element.date ? a.offset < b.offset : a.element.date < b.element.date
    }
    for record in ordered {
      let m = record.element
      if m.quantity > 0 {
        let cost: Decimal
        if let c = m.costPaise {
          cost = Decimal(c)
        } else {
          cost = Decimal(item.rate) * 100
          assumed += 1
        }
        quantity += m.quantity
        value += Decimal(m.quantity) * cost
        lots.append((m.quantity, cost))
      } else if m.quantity < 0 {
        guard quantity + m.quantity >= -0.0000001 else {
          throw BookError.invalid(
            "\(item.name) has negative historical stock. Review movement dates.")
        }
        if method == "FIFO" {
          var remaining = -m.quantity
          while remaining > 0.0000001 && !lots.isEmpty {
            let used = min(remaining, lots[0].0)
            value -= Decimal(used) * lots[0].1
            remaining -= used
            lots[0].0 -= used
            if lots[0].0 < 0.0000001 { lots.removeFirst() }
          }
        } else if quantity > 0 {
          value -= Decimal(-m.quantity) * value / Decimal(quantity)
        }
        quantity += m.quantity
        if abs(quantity) < 0.0000001 {
          quantity = 0
          value = 0
          lots = []
        }
      }
    }
    return Valuation(quantity: quantity, value: value / 100, assumedCosts: assumed)
  }
  func validateBusiness() throws {
    guard Set(bankAccounts.map(\.ledger)).count == bankAccounts.count,
      bankAccounts.allSatisfy({ account in
        ledgers.contains { $0.id == account.ledger && $0.group == "Asset" }
          && (account.statementOpening.map { abs(Decimal($0)) <= 100_000_000_000 } ?? true)
      }),
      Set(employees.map(\.id)).count == employees.count,
      Set(payruns.map { "\($0.employee):\($0.period)" }).count == payruns.count,
      Set(bankLines.map(\.id)).count == bankLines.count,
      employees.allSatisfy({
        !$0.name.isEmpty && $0.basic >= 0 && $0.basic <= 100_000_000_000 && $0.allowance >= 0
          && $0.allowance <= 100_000_000_000 && $0.deduction >= 0
          && $0.deduction <= $0.basic + $0.allowance
      }),
      bankLines.allSatisfy({ line in
        ledgers.contains { $0.id == line.bank && $0.group == "Asset" } && line.amount != 0
          && abs(Decimal(line.amount)) <= 100_000_000_000
          && (line.voucher == nil
            || vouchers.contains {
              $0.id == line.voucher && bankAmount($0, bank: line.bank) == line.amount
            })
      }),
      Set(bankLines.map { "\($0.bank):\($0.reference)" }).count == bankLines.count,
      Set(bankLines.filter { $0.voucher != nil }.map { "\($0.bank):\($0.voucher!)" }).count
        == bankLines.filter({ $0.voucher != nil }).count,
      movements.allSatisfy({
        $0.costPaise == nil || ($0.costPaise! >= 0 && $0.costPaise! <= 100_000_000_000)
      }),
      payruns.allSatisfy({ run in
        employees.contains { $0.id == run.employee } && run.gross > 0
          && run.gross <= 200_000_000_000 && run.deduction >= 0 && run.deduction <= run.gross
          && run.net == run.gross - run.deduction
      })
    else {
      throw BookError.invalid("Invalid payroll, bank reconciliation or movement cost records.")
    }
  }
}
enum CSV {
  static func read(_ text: String) throws -> [[String]] {
    let text = text.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(
      of: "\r\n", with: "\n"
    ).replacingOccurrences(of: "\r", with: "\n")
    let chars = Array(text)
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    var closed = false
    var i = 0
    while i < chars.count {
      let c = chars[i]
      if quoted {
        if c == "\"" {
          if i + 1 < chars.count && chars[i + 1] == "\"" {
            field.append("\"")
            i += 1
          } else {
            quoted = false
            closed = true
          }
        } else {
          field.append(c)
        }
      } else if c == "," {
        row.append(field)
        field = ""
        closed = false
      } else if c == "\n" {
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        row = []
        field = ""
        closed = false
      } else if c == "\"" && field.isEmpty && !closed {
        quoted = true
      } else {
        guard !closed && c != "\"" else { throw BookError.invalid("Malformed quoted CSV field.") }
        field.append(c)
      }
      i += 1
    }
    guard !quoted else { throw BookError.invalid("Unclosed quoted CSV field.") }
    row.append(field)
    if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
    return rows
  }
}
