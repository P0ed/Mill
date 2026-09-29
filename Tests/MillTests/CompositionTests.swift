import Testing
@testable import Mill

@Test func compositionOrderAndTypes() {
    let length: (String) -> Int = { $0.count }
    let double: (Int) -> Int = { $0 * 2 }
    let describe: (Int) -> String = { "value=\($0)" }
    #expect((describe • double • length § "abc") == "value=6")
}

@Test func applicationPrecedenceAndAssociativity() {
    let double: (Int) -> Int = { $0 * 2 }
    let increment: (Int) -> Int = { $0 + 1 }
    let result = double § increment § 2 + 3
    #expect(result == 12)
    let chooseFirst = true
    #expect((double § chooseFirst ? 3 : 5) == 6)
}

@Test func applicationRethrows() throws {
    enum ParseError: Error { case invalid }
    func parse(_ text: String) throws -> Int {
        guard let value = Int(text) else { throw ParseError.invalid }
        return value
    }
    #expect(try (parse § "42") == 42)
    #expect(throws: ParseError.invalid) { try parse § "invalid" }
}
