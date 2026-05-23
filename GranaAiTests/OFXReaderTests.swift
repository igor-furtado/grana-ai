import Foundation
import Testing
@testable import GranaAi

@Suite("OFXReader")
struct OFXReaderTests {
    private let reader = OFXReader()

    // Mini-OFX 1.x SGML que cobre os caminhos críticos: header SGML, FI,
    // BANKACCTFROM, BANKTRANLIST com 2 STMTTRN, LEDGERBAL. Charset USASCII pra
    // facilitar o teste — o caminho CHARSET:1252 é exercitado pelo
    // `decode(data:charsetHint:)` direto em outro teste.
    private let sampleOFX = """
    OFXHEADER:100
    DATA:OFXSGML
    VERSION:102
    SECURITY:NONE
    ENCODING:USASCII
    CHARSET:1252
    COMPRESSION:NONE
    OLDFILEUID:NONE
    NEWFILEUID:NONE

    <OFX>
    <SIGNONMSGSRSV1>
    <SONRS>
    <STATUS><CODE>0</CODE><SEVERITY>INFO</SEVERITY></STATUS>
    <DTSERVER>20251003</DTSERVER>
    <LANGUAGE>POR</LANGUAGE>
    <FI><ORG>Banco Intermedium S/A</ORG><FID>077</FID></FI>
    </SONRS>
    </SIGNONMSGSRSV1>
    <BANKMSGSRSV1>
    <STMTTRNRS>
    <TRNUID>1001</TRNUID>
    <STATUS><CODE>0</CODE><SEVERITY>INFO</SEVERITY></STATUS>
    <STMTRS>
    <CURDEF>BRL</CURDEF>
    <BANKACCTFROM>
    <BANKID>077</BANKID>
    <BRANCHID>0001-9</BRANCHID>
    <ACCTID>310013887</ACCTID>
    <ACCTTYPE>CHECKING</ACCTTYPE>
    </BANKACCTFROM>
    <BANKTRANLIST>
    <DTSTART>20230101</DTSTART>
    <DTEND>20231231</DTEND>
    <STMTTRN>
    <TRNTYPE>PAYMENT</TRNTYPE>
    <DTPOSTED>20231231</DTPOSTED>
    <TRNAMT>-50.00</TRNAMT>
    <FITID>202312310771</FITID>
    <MEMO>Pix enviado: teste</MEMO>
    <NAME>Tamires Cristina</NAME>
    </STMTTRN>
    <STMTTRN>
    <TRNTYPE>CREDIT</TRNTYPE>
    <DTPOSTED>20231222</DTPOSTED>
    <TRNAMT>8924.10</TRNAMT>
    <FITID>202312220771</FITID>
    <MEMO>Pix recebido</MEMO>
    <NAME>Igor T C Furtado</NAME>
    </STMTTRN>
    </BANKTRANLIST>
    <LEDGERBAL>
    <BALAMT>783.59</BALAMT>
    <DTASOF>20251003</DTASOF>
    </LEDGERBAL>
    </STMTRS>
    </STMTTRNRS>
    </BANKMSGSRSV1>
    </OFX>
    """

    @Test("Header é parseado (versão, encoding, charset)")
    func parsesHeader() throws {
        let doc = try reader.read(data: #require(sampleOFX.data(using: .ascii)))
        #expect(doc.version == "102")
        #expect(doc.encoding == "USASCII")
        #expect(doc.charset == "1252")
    }

    @Test("Lê um STMTRS com identidade bancária correta")
    func parsesStatement() throws {
        let doc = try reader.read(data: #require(sampleOFX.data(using: .ascii)))
        try #require(doc.statements.count == 1)

        let stmt = doc.statements[0]
        #expect(stmt.currency == "BRL")
        #expect(stmt.institutionHeader.fid == "077")
        #expect(stmt.institutionHeader.organization == "Banco Intermedium S/A")

        #expect(stmt.account.bankId == "077")
        #expect(stmt.account.branchId == "0001-9")
        #expect(stmt.account.accountId == "310013887")
        #expect(stmt.account.accountType == "CHECKING")
        #expect(stmt.account.mappedAccountType == .checking)
    }

    @Test("Lê transações com sinal, descrição e FITID")
    func parsesTransactions() throws {
        let doc = try reader.read(data: #require(sampleOFX.data(using: .ascii)))
        let stmt = doc.statements[0]
        try #require(stmt.transactions.count == 2)

        let payment = stmt.transactions[0]
        #expect(payment.trnType == "PAYMENT")
        #expect(payment.amount == Decimal(string: "-50.00"))
        #expect(payment.fitid == "202312310771")
        #expect(payment.name == "Tamires Cristina")
        #expect(payment.memo == "Pix enviado: teste")

        let credit = stmt.transactions[1]
        #expect(credit.trnType == "CREDIT")
        #expect(credit.amount == Decimal(string: "8924.10"))
        #expect(credit.fitid == "202312220771")
    }

    @Test("Saldo final é extraído")
    func parsesBalance() throws {
        let doc = try reader.read(data: #require(sampleOFX.data(using: .ascii)))
        let stmt = doc.statements[0]
        let bal = try #require(stmt.balance)
        #expect(bal.amount == Decimal(string: "783.59"))
    }

    // MARK: - Múltiplas contas

    @Test("Múltiplas STMTRS no mesmo arquivo viram vários statements")
    func multipleStatements() throws {
        let ofx = """
        OFXHEADER:100
        DATA:OFXSGML
        VERSION:102

        <OFX>
        <BANKMSGSRSV1>
        <STMTTRNRS>
        <STMTRS>
        <CURDEF>BRL</CURDEF>
        <BANKACCTFROM><BANKID>077</BANKID><ACCTID>111</ACCTID><ACCTTYPE>CHECKING</ACCTTYPE></BANKACCTFROM>
        <BANKTRANLIST>
        <STMTTRN><TRNTYPE>CREDIT</TRNTYPE><DTPOSTED>20230101</DTPOSTED><TRNAMT>100.00</TRNAMT><FITID>A1</FITID></STMTTRN>
        </BANKTRANLIST>
        </STMTRS>
        </STMTTRNRS>
        <STMTTRNRS>
        <STMTRS>
        <CURDEF>BRL</CURDEF>
        <BANKACCTFROM><BANKID>077</BANKID><ACCTID>222</ACCTID><ACCTTYPE>SAVINGS</ACCTTYPE></BANKACCTFROM>
        <BANKTRANLIST>
        <STMTTRN><TRNTYPE>DEBIT</TRNTYPE><DTPOSTED>20230102</DTPOSTED><TRNAMT>-50.00</TRNAMT><FITID>B1</FITID></STMTTRN>
        </BANKTRANLIST>
        </STMTRS>
        </STMTTRNRS>
        </BANKMSGSRSV1>
        </OFX>
        """
        let doc = try reader.read(data: #require(ofx.data(using: .ascii)))
        #expect(doc.statements.count == 2)
        #expect(doc.statements[0].account.accountId == "111")
        #expect(doc.statements[1].account.accountId == "222")
        #expect(doc.statements[1].account.mappedAccountType == .savings)
    }

    // MARK: - Parsing utilitário

    @Test("parseAmount lida com ponto e vírgula")
    func parseAmounts() {
        #expect(OFXReader.parseAmount("-50.00") == Decimal(string: "-50.00"))
        #expect(OFXReader.parseAmount("8924.10") == Decimal(string: "8924.10"))
        #expect(OFXReader.parseAmount("123,45") == Decimal(string: "123.45"))
        #expect(OFXReader.parseAmount("") == nil)
        #expect(OFXReader.parseAmount(nil) == nil)
    }

    @Test("parseOFXDateTime pega só a porção de data (YYYYMMDD)")
    func parseDates() throws {
        let d = try #require(OFXReader.parseOFXDateTime("20231231"))
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: d)
        #expect(comps.year == 2023)
        #expect(comps.month == 12)
        #expect(comps.day == 31)

        // Com hora: pega só a parte de data, ignora o resto.
        let dWithTime = try #require(OFXReader.parseOFXDateTime("20231231120000.000"))
        let compsT = Calendar.current.dateComponents([.year, .month, .day], from: dWithTime)
        #expect(compsT.year == 2023)
    }

    // MARK: - Decode

    @Test("decode CHARSET:1252 traz acentos corretos")
    func decodeCP1252() throws {
        // "ção" em Windows-1252: 0x63 0xE7 0xE3 0x6F (c, ç, ã, o).
        let bytes: [UInt8] = [0x63, 0xE7, 0xE3, 0x6F]
        let data = Data(bytes)
        let decoded = try #require(OFXReader.decode(data: data, charsetHint: "1252"))
        #expect(decoded == "ção")
    }
}

@Suite("OFXCategoryHeuristic")
struct OFXCategoryHeuristicTests {
    private func makeHeuristic(
        unclassified: UUID = UUID(),
        transfers: UUID? = UUID(),
        income: UUID? = UUID()
    ) -> (OFXCategoryHeuristic, unclassified: UUID, transfers: UUID?, income: UUID?) {
        let h = OFXCategoryHeuristic(roots: .init(
            unclassified: unclassified, transfers: transfers, income: income
        ))
        return (h, unclassified, transfers, income)
    }

    private func makeTransaction(
        trnType: String,
        memo: String? = nil,
        name: String? = nil
    ) -> OFXTransaction {
        OFXTransaction(
            trnType: trnType,
            datePosted: Date(),
            amount: Decimal(10),
            fitid: "X",
            name: name,
            memo: memo,
            checkNumber: nil,
            refNumber: nil
        )
    }

    @Test("CREDIT/DEP/DIRECTDEP vão pra Renda")
    func creditGoesToIncome() {
        let (h, unc, _, inc) = makeHeuristic()
        #expect(h.categoryId(for: makeTransaction(trnType: "CREDIT")) == inc)
        #expect(h.categoryId(for: makeTransaction(trnType: "DEP")) == inc)
        #expect(h.categoryId(for: makeTransaction(trnType: "DIRECTDEP")) == inc)
        // Sanity check que ainda não estamos caindo no fallback.
        #expect(h.categoryId(for: makeTransaction(trnType: "CREDIT")) != unc)
    }

    @Test("XFER vai pra Transferências")
    func xferGoesToTransfer() {
        let (h, _, trn, _) = makeHeuristic()
        #expect(h.categoryId(for: makeTransaction(trnType: "XFER")) == trn)
    }

    @Test("MEMO com PIX força Transferências mesmo em CREDIT")
    func pixMemoOverridesTrnType() {
        let (h, _, trn, _) = makeHeuristic()
        let tx = makeTransaction(trnType: "CREDIT", memo: "Pix recebido")
        #expect(h.categoryId(for: tx) == trn)
    }

    @Test("Sem income root, CREDIT cai pra Não Classificado")
    func incomeFallback() {
        let (h, unc, _, _) = makeHeuristic(income: nil)
        #expect(h.categoryId(for: makeTransaction(trnType: "CREDIT")) == unc)
    }

    @Test("DEBIT/PAYMENT/etc vão pra Não Classificado")
    func debitGoesToUnclassified() {
        let (h, unc, _, _) = makeHeuristic()
        #expect(h.categoryId(for: makeTransaction(trnType: "DEBIT")) == unc)
        #expect(h.categoryId(for: makeTransaction(trnType: "PAYMENT")) == unc)
        #expect(h.categoryId(for: makeTransaction(trnType: "FEE")) == unc)
        #expect(h.categoryId(for: makeTransaction(trnType: "OTHER")) == unc)
    }
}
