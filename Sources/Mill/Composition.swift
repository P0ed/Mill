precedencegroup CompositionPrecedence {
    associativity: right
    higherThan: MultiplicationPrecedence
}

infix operator •: CompositionPrecedence

/// Right-to-left function composition: `(f • g § x) == f(g(x))`.
public func • <A, B, C>(f: @escaping (B) -> C, g: @escaping (A) -> B) -> (A) -> C {
    { f(g($0)) }
}

precedencegroup ApplicativePrecedence {
    associativity: right
    higherThan: AssignmentPrecedence
    lowerThan: TernaryPrecedence
}

infix operator §: ApplicativePrecedence

/// Applies a function to an argument, propagating any error it throws.
public func § <A, B>(f: (A) throws -> B, x: A) rethrows -> B {
    try f(x)
}

public func id<A>(_ value: A) -> A { value }
public func const<A, B>(_ value: A) -> (B) -> A { { _ in value } }
public func mapOpt<A, B>(_ transform: @escaping (A) -> B) -> (A?) -> B? {
    { $0.map(transform) }
}
public func mapList<A, B>(_ transform: @escaping (A) -> B) -> ([A]) -> [B] {
    { $0.map(transform) }
}
public func flat<A>(_ values: [[A]]) -> [A] { values.flatMap(id) }
public func compact<A>(_ values: [A?]) -> [A] { values.compactMap(id) }
