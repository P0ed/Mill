import Foundation
import OCCTSwift
import simd

public enum ModelError: Error, LocalizedError {
    case operation(String)
    case invalidArgument(String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .operation(let name): "OCCT could not complete \(name)."
        case .invalidArgument(let message): message
        case .empty: "The model contains no geometry."
        }
    }
}

func require<T>(_ value: T?, _ operation: String) throws -> T {
    guard let value else { throw ModelError.operation(operation) }
    return value
}

/// Eager geometry with error propagation, so compositions remain ordinary Swift functions.
/// Read `shape` (or export) to throw any modeling error; failed operations are never skipped.
public struct Model: Sendable {
    let result: Result<Shape?, Error>

    public init(_ shape: Shape?, operation: String = "shape construction") {
        result = Result { try require(shape, operation) }
    }

    init(build: () throws -> Shape?) { result = Result(catching: build) }
    public static var empty: Model { Model(build: { nil }) }

    public var shape: Shape {
        get throws {
            guard let shape = try result.get() else { throw ModelError.empty }
            return shape
        }
    }

    public func transformed(_ operation: String, _ transform: (Shape) -> Shape?) -> Model {
        Model(build: {
            guard let shape = try result.get() else { return nil }
            return try require(transform(shape), operation)
        })
    }

    public func fillet(_ radius: Double, edges: EdgeSelection = .all) -> Model {
        transformed("fillet radius \(radius) on \(edges)") { shape in
            shape.filleted(edges: edges.select(in: shape), radius: radius)
        }
    }

    public func chamfer(_ distance: Double, edges: EdgeSelection = .all) -> Model {
        transformed("chamfer distance \(distance) on \(edges)") { shape in
            shape.chamferedWithFullHistory(distance: distance,
                                          edges: edges.select(in: shape).map(\.index))?.result
        }
    }
}

private func boolean(_ lhs: Model, _ rhs: Model, _ operation: String,
                     empty: (Shape?, Shape?) -> Shape?,
                     combine: (Shape, Shape) -> Shape?) -> Model {
    Model(build: {
        let l = try lhs.result.get(), r = try rhs.result.get()
        guard let l, let r else { return empty(l, r) }
        let combined = try require(combine(l, r), operation)
        // CadQuery cleans same-domain faces after each boolean, before edge selection.
        return try require(combined.unified(), "\(operation) cleanup")
    })
}

public func + (lhs: Model, rhs: Model) -> Model {
    boolean(lhs, rhs, "union", empty: { $0 ?? $1 }, combine: { $0.union($1) })
}
public func - (lhs: Model, rhs: Model) -> Model {
    boolean(lhs, rhs, "subtraction", empty: { l, _ in l }, combine: { $0.subtracting($1) })
}
public func * (lhs: Model, rhs: Model) -> Model {
    boolean(lhs, rhs, "intersection", empty: { _, _ in nil }, combine: { $0.intersection($1) })
}
public func sum(_ models: [Model]) -> Model { models.reduce(.empty, +) }
public func dif(_ models: [Model]) -> Model {
    guard let first = models.first else { return .empty }
    return models.dropFirst().reduce(first, -)
}
public func compound(_ models: [Model]) -> Model {
    Model(build: {
        let shapes = try models.compactMap { try $0.result.get() }
        return shapes.isEmpty ? nil : try require(Shape.compound(shapes), "compound")
    })
}

public enum Axis: Int, Sendable {
    case x, y, z
    var vector: SIMD3<Double> {
        var v = SIMD3<Double>.zero
        v[rawValue] = 1
        return v
    }
}

public enum EdgeSelection: Sendable {
    case all, parallel(Axis), notParallel(Axis), positive(Axis), minimum(Axis), maximum(Axis)

    public func select(in shape: Shape) -> [Edge] {
        let all = shape.edges()
        switch self {
        case .all: return all
        case .parallel(let axis): return shape.edges(parallelTo: axis.vector)
        case .notParallel(let axis):
            let parallel = Set(shape.edges(parallelTo: axis.vector).map(\.index))
            return all.filter { !parallel.contains($0.index) }
        case .positive(let axis):
            return all.filter { edge in
                guard edge.isLine, let range = edge.parameterBounds,
                      let tangent = edge.tangent(at: (range.first + range.last) / 2) else { return false }
                return simd_dot(simd_normalize(tangent), axis.vector) > 1 - 1e-6
            }
        case .minimum(let axis), .maximum(let axis):
            let centers = all.compactMap { edge -> (Edge, Double)? in
                guard let center = edge.curveInertia.centerOfMass else { return nil }
                return (edge, center[axis.rawValue])
            }
            let coordinates = centers.map(\.1)
            let extreme: Double?
            if case .minimum = self { extreme = coordinates.min() } else { extreme = coordinates.max() }
            guard let extreme else { return [] }
            return centers.filter { abs($0.1 - extreme) < 1e-6 }.map(\.0)
        }
    }
}

public struct Bounds: Sendable {
    public let min: SIMD3<Double>
    public let max: SIMD3<Double>
    public var size: SIMD3<Double> { max - min }
    public var center: SIMD3<Double> { (min + max) / 2 }
}

public func bounds(_ model: Model) throws -> Bounds {
    // Like CadQuery's BoundingBox, measure the geometry instead of the
    // looser spline control hull used by Shape.bounds.
    let b = try require(model.shape.boundingBoxOptimal(), "bounding box")
    return Bounds(min: b.min, max: b.max)
}
