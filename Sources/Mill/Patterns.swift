import Foundation

public let pl = 0.001
public let s2 = sqrt(2.0)
public let s22 = s2 / 2
public let inch = 25.4
public let in2 = inch / 2
public let in4 = inch / 4
public let in8 = inch / 8
public let inX = inch / 16

public typealias Pattern = @Sendable (Int, Int) -> Bool
public func und(_ l: @escaping Pattern, _ r: @escaping Pattern) -> Pattern {
    { l($0, $1) && r($0, $1) }
}
public func oder(_ l: @escaping Pattern, _ r: @escaping Pattern) -> Pattern {
    { l($0, $1) || r($0, $1) }
}
public func nicht(_ pattern: @escaping Pattern) -> Pattern { { !pattern($0, $1) } }

public let ptnAll: Pattern = { _, _ in true }
public let ptnTop: Pattern = { _, y in y > 2 }
public let ptnBot: Pattern = { _, y in y < 3 }
public let ptnMdx: Pattern = { x, _ in x > 0 && x < 3 }
public let ptnX: Pattern = { x, y in (x + y % 2 + x / 2) % 2 == 0 }
public let ptnD: Pattern = { x, y in (x + y % 2 + x / 2) % 2 == 1 }
public let ptnW: Pattern = und(ptnD, { _, y in y < 2 })
public let ptnTopM: Pattern = { x, y in y > 2 && !(y % 3 == 2 && (x == 0 || x == 3)) }
public let ptnBotM: Pattern = { x, y in y < 3 && !(y % 3 == 2 && (x == 0 || x == 3)) }
public let ptnM: Pattern = { x, y in !(y % 3 == 2 && (x == 0 || x == 3)) }
public let ptnTopL: Pattern = { x, y in x == 0 && y == 5 }
public let ptnTopR: Pattern = { x, y in x == 3 && y == 5 }

public func ptnMap<A>(_ yes: @escaping () -> A, _ pattern: @escaping Pattern,
                      _ no: @escaping () -> A) -> (Int, Int) -> A {
    { pattern($0, $1) ? yes() : no() }
}

/// Rules are evaluated in order; the first matching rule wins.
public func ptnsMap<A>(_ rules: (Pattern, () -> A)...) -> (Int, Int) -> A? {
    { x, y in rules.first(where: { $0.0(x, y) }).map { $0.1() } }
}
