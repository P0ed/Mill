import Testing
@testable import Mill

@Test func compositionOrderAndTypes() {
    let length: (String) -> Int = { $0.count }
    let double: (Int) -> Int = { $0 * 2 }
    let describe: (Int) -> String = { "value=\($0)" }
    #expect((describe • double • length)("abc") == "value=6")
}
