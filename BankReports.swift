import Foundation

struct BankAccount: Codable, Identifiable {
  var id = UUID()
  var ledger: UUID
  var bankName: String
  var accountNumber: String
  var statementOpening: Int64?
}
struct BankSnapshot {
  var bank: UUID
  var books: [Voucher]
  var statements: [BankLine]
  var unmatchedBooks: [Voucher]
  var unmatchedBank: [BankLine]
  var matched: [BankLine]
  var bookBalance: Decimal
  var expectedBalance: Decimal
  var statementBalance: Decimal?
  var difference: Decimal? { statementBalance.map { expectedBalance - $0 } }
}
extension Books {
  var bankLedgers: [Ledger] {
    let explicit = Set(bankAccounts.map(\.ledger) + bankLines.map(\.bank))
    return ledgers.filter {
      $0.group == "Asset"
        && (explicit.contains($0.id) || $0.name.localizedCaseInsensitiveContains("bank"))
    }
  }
  func snapshot(bank: UUID, through: Date) -> BankSnapshot {
    let books = vouchers.filter { ($0.debit == bank || $0.credit == bank) && $0.date <= through }
    let statements = bankLines.filter { $0.bank == bank && $0.date <= through }
    let presentBookIDs = Set(books.map(\.id))
    let matched = statements.filter { line in
      line.voucher.map { presentBookIDs.contains($0) } ?? false
    }
    let used = Set(matched.compactMap(\.voucher))
    let unmatchedBooks = books.filter { !used.contains($0.id) }
    let unmatchedBank = statements.filter { line in
      line.voucher.map { !presentBookIDs.contains($0) } ?? true
    }
    let balance = books.reduce(Decimal(0)) { $0 + Decimal(bankAmount($1, bank: bank)) }
    let expected =
      balance - unmatchedBooks.reduce(Decimal(0)) { $0 + Decimal(bankAmount($1, bank: bank)) }
      + unmatchedBank.reduce(Decimal(0)) { $0 + Decimal($1.amount) }
    let opening = bankAccounts.first { $0.ledger == bank }?.statementOpening
    let statement = opening.map { start in
      statements.reduce(Decimal(start)) { $0 + Decimal($1.amount) }
    }
    return BankSnapshot(
      bank: bank, books: books, statements: statements, unmatchedBooks: unmatchedBooks,
      unmatchedBank: unmatchedBank, matched: matched, bookBalance: balance,
      expectedBalance: expected, statementBalance: statement)
  }
  mutating func saveBankAccount(_ account: BankAccount) throws {
    guard ledgers.contains(where: { $0.id == account.ledger && $0.group == "Asset" }),
      account.statementOpening.map({ abs(Decimal($0)) <= 100_000_000_000 }) ?? true
    else { throw BookError.invalid("Select an asset ledger and a valid opening balance.") }
    if let index = bankAccounts.firstIndex(where: { $0.ledger == account.ledger }) {
      bankAccounts[index] = account
    } else {
      bankAccounts.append(account)
    }
  }
}
struct BankSuggestion: Identifiable {
  var id: String { line.id.uuidString + voucher.id.uuidString }
  var line: BankLine
  var voucher: Voucher
  var sameDay: Bool
}
extension Books {
  func bankSuggestions(bank: UUID, through: Date) -> [BankSuggestion] {
    let report = snapshot(bank: bank, through: through)
    var result: [BankSuggestion] = []
    for line in report.unmatchedBank {
      for voucher in report.unmatchedBooks where bankAmount(voucher, bank: bank) == line.amount {
        let days = abs(
          Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: voucher.date),
            to: Calendar.current.startOfDay(for: line.date)
          ).day ?? Int.max)
        if days <= 30 {
          result.append(BankSuggestion(line: line, voucher: voucher, sameDay: days == 0))
        }
      }
    }
    return result
  }
}
