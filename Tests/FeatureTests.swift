import Foundation
@main struct FeatureTests {
 static func main() throws {
  var b=Books();let bank=b.ledgers.first{$0.name=="Bank"}!.id,cash=b.ledgers.first{$0.name=="Cash"}!.id,income=b.ledgers.first{$0.name=="Sales"}!.id,expense=b.ledgers.first{$0.name=="Purchases"}!.id
  precondition(b.bankLedgers.count==1 && b.bankLedgers[0].id==bank)
  let first=Date(timeIntervalSince1970:1_700_000_000),second=first.addingTimeInterval(86400)
  let receipt=Voucher(date:first,debit:bank,credit:income,amount:100,narration:"Receipt")
  b.vouchers=[receipt,Voucher(date:second,debit:expense,credit:bank,amount:30,narration:"Payment")]
  b.bankLines=[BankLine(bank:bank,reference:"M1",date:first,description:"Receipt",amount:10000,voucher:receipt.id),BankLine(bank:bank,reference:"U1",date:second,description:"Bank charge",amount:-2000)]
  let missing=b.snapshot(bank:bank,through:second)
  precondition(missing.statementBalance==nil && missing.bookBalance==7000 && missing.expectedBalance==8000 && missing.unmatchedBooks.count==1 && missing.unmatchedBank.count==1 && missing.matched.count==1)
  try b.saveBankAccount(BankAccount(ledger:bank,bankName:"QA Bank",accountNumber:"QA-123",statementOpening:1000))
  let known=b.snapshot(bank:bank,through:second);precondition(known.statementBalance==9000 && known.difference == -1000)
  let historical=b.snapshot(bank:bank,through:first);precondition(historical.books.count==1 && historical.statements.count==1 && historical.bookBalance==10000)
  try b.saveBankAccount(BankAccount(ledger:bank,bankName:"QA Bank",accountNumber:"QA-123",statementOpening:0));precondition(b.bankAccounts.count==1)
  try b.saveBankAccount(BankAccount(ledger:cash,bankName:"Explicit bank",accountNumber:"",statementOpening:nil));precondition(b.bankLedgers.count==2)
  let item=StockItem(name:"QA Widget",unit:"Nos",opening:10,rate:50);b.stock=[item]
  var suggestions=b
  suggestions.bankLines.append(BankLine(bank:bank,reference:"SUGGEST",date:second.addingTimeInterval(86400),description:"Potential payment",amount:-3000))
  precondition(suggestions.bankSuggestions(bank:bank,through:second.addingTimeInterval(86400)).count==1)
  precondition(suggestions.bankSuggestions(bank:bank,through:second).isEmpty)
  let count=b.vouchers.count,stock=b.movements.count
  let order=PurchaseOrder(number:"PO-001",date:first,due:second,supplier:cash,lines:[InvoiceLine(item:item.id,quantity:2,ratePaise:5000)],note:"Test order")
  try b.addOrder(order);precondition(b.purchaseOrders[0].totalPaise==10000 && b.vouchers.count==count && b.movements.count==stock)
  do{try b.addOrder(order);fatalError("Duplicate order accepted")}catch{precondition(b.purchaseOrders.count==1)}
  var invalid=order;invalid.number="PO-BAD";invalid.due=first.addingTimeInterval(-86400)
  do{try b.addOrder(invalid);fatalError("Invalid order due date accepted")}catch{}
  b.orderTemplate=DocumentTemplate(style:"Letterhead",colour:"Green",font:"Helvetica",header:"Company address",footer:"Terms",wrap:true,autoSave:true)
  try b.validate()
  let decoded=try JSONDecoder().decode(Books.self,from:JSONEncoder().encode(b));try decoded.validate();precondition(decoded.purchaseOrders.count==1 && decoded.bankAccounts.count==2 && decoded.orderTemplate.style=="Letterhead")
  var broken=b;broken.invoiceTemplate.colour="Unknown";do{try broken.validate();fatalError("Invalid template accepted")}catch{}
  if CommandLine.arguments.count>1 {let encoder=JSONEncoder();encoder.outputFormatting = .prettyPrinted;try encoder.encode(b).write(to:URL(fileURLWithPath:CommandLine.arguments[1]),options:.atomic)}
  print("PASS: bank discovery, summary counts and balances, unknown statement balance, historical cutoff, bank configuration update, purchase orders without accounting/stock effects, duplicate/due-date rejection, template settings and schema round-trip")
 }
}
