import Testing
@testable import Mill

@Test func patternBooleanOperators() {
	let x: Pattern = { x, _ in x > 0 }
	let y: Pattern = { _, y in y > 0 }
	let cells = [(0, 0), (0, 1), (1, 0), (1, 1)]
	let intersection = x && y
	let union = x || y
	let complement = !x

	#expect(cells.map { intersection($0.0, $0.1) } == [false, false, false, true])
	#expect(cells.map { union($0.0, $0.1) } == [false, true, true, true])
	#expect(cells.map { complement($0.0, $0.1) } == [true, true, false, false])
}

@Test func patternOperatorPrecedence() {
	let pattern = ptnTopL || ptnTop && !ptnTopL

	#expect(pattern(0, 5))
	#expect(pattern(1, 4))
	#expect(!pattern(1, 0))
	#expect((!(!ptnTopL))(0, 5))
}

@Test func patternOperatorsShortCircuit() {
	let never: Pattern = { _, _ in false }
	let unexpected: Pattern = { _, _ in
		Issue.record("The right-hand pattern should not have been evaluated.")
		return true
	}

	#expect(!(never && unexpected)(0, 0))
	#expect((ptnAll || unexpected)(0, 0))
}
