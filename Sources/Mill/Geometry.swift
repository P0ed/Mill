import Foundation
import OCCTSwift

public typealias Transform = (Model) -> Model
public enum Plane: Sendable {
	case xy, xz, yz
	var normal: SIMD3<Double> {
		switch self {
		case .xy: SIMD3(0, 0, 1)
		case .xz: SIMD3(0, 1, 0)
		case .yz: SIMD3(1, 0, 0)
		}
	}
}

public func mov(_ x: Double = 0, _ y: Double = 0, _ z: Double = 0) -> Transform {
	{ $0.transformed("translation") { $0.translated(by: SIMD3(x, y, z)) } }
}
public func mov(x: Double = 0, y: Double = 0, z: Double) -> Transform { mov(x, y, z) }
public func mov(y: Double) -> Transform { mov(0, y, 0) }

/// Mirror and union at each plane, as in CadQuery's `mirror(union: true)`.
public func mirror(_ planes: Plane...) -> Transform {
	{ model in planes.reduce(model) { result, plane in
		result + result.transformed("mirror") { $0.mirrored(planeNormal: plane.normal) }
	} }
}
private func rotate(_ degrees: Double, around axis: Axis) -> Transform {
	{ $0.transformed("rotation") { $0.rotated(axis: axis.vector, angle: degrees * .pi / 180) } }
}
public func rotx(_ degrees: Double) -> Transform { rotate(degrees, around: .x) }
public func roty(_ degrees: Double) -> Transform { rotate(degrees, around: .y) }
public func rotz(_ degrees: Double) -> Transform { rotate(degrees, around: .z) }

public func box(_ w: Double, _ h: Double, _ t: Double) -> Model {
	guard [w, h, t].allSatisfy({ $0.isFinite && $0 > 0 }) else {
		return Model(build: { throw ModelError.invalidArgument("Box dimensions must be finite and positive.") })
	}
	return Model(Shape.box(width: w, height: h, depth: t), operation: "box")
}
public func cylinder(_ length: Double, _ radius: Double) -> Model {
	guard [length, radius].allSatisfy({ $0.isFinite && $0 > 0 }) else {
		return Model(build: { throw ModelError.invalidArgument("Cylinder length and radius must be finite and positive.") })
	}
	return Model(Shape.cylinder(at: .zero, bottomZ: -length / 2, radius: radius, height: length),
				 operation: "cylinder")
}
/// Cones, unlike centered boxes and cylinders, start at Z=0 in DIY.
public func cone(_ r1: Double, _ r2: Double, _ height: Double) -> Model {
	Model(Shape.cone(bottomRadius: r1, topRadius: r2, height: height), operation: "cone")
}
public func sphere(_ radius: Double) -> Model { Model(Shape.sphere(radius: radius), operation: "sphere") }

public func extrude(_ profile: Wire?, _ length: Double) -> Model {
	Model(build: {
		let wire = try require(profile, "profile")
		return try require(Shape.extrude(profile: wire, direction: SIMD3(0, 0, 1), length: length), "extrusion")
	})
}

public func squircle(_ w: Double, _ h: Double, _ r: Double) -> Wire? {
	guard [w, h, r].allSatisfy({ $0.isFinite && $0 > 0 }), 2 * r <= min(w, h) else { return nil }
	// Exact diagonal of x^5 + y^5 = 1. DIY's rounded 0.8707 crosses the
	// reflected arc, producing tiny self-intersections at the four seams.
	let x0 = -pow(0.5, 1 / 5.0)
	var points = (0..<64).map { i -> SIMD2<Double> in
		let x = x0 - x0 * Double(i) / 63.9
		return SIMD2(x, pow(1 + pow(x, 5), 1 / 5.0))
	}
	points = points.reversed().map { SIMD2(-$0.y, -$0.x) } + points
	points += points.reversed().map { SIMD2(-$0.x, $0.y) }
	points += points.reversed().map { SIMD2($0.x, -$0.y) }
	let scaled = points.map {
		SIMD2($0.x * r + (w / 2 - r) * ($0.x > 0 ? 1 : -1),
			  $0.y * r + (h / 2 - r) * ($0.y > 0 ? 1 : -1))
	}
	var unique: [SIMD2<Double>] = []
	for point in scaled {
		if let last = unique.last, abs(last.x - point.x) + abs(last.y - point.y) < 1e-9 { continue }
		unique.append(point)
	}
	if let first = unique.first, let last = unique.last,
	   abs(first.x - last.x) + abs(first.y - last.y) < 1e-9 { unique.removeLast() }
	return Wire.polygon(unique)
}

private func grid(columns: Int, _ transform: (Int, Int) -> Model?) -> Model {
	sum((0..<columns).flatMap { x in (0..<6).compactMap { y in
		transform(x, y).map(mov((Double(x) - Double(columns - 1) / 2) * inch,
								(Double(y) - 2.5) * inch))
	} })
}
public func grid(_ transform: (Int, Int) -> Model?) -> Model {
	sum((0..<4).flatMap { x in
		(0..<6).compactMap { y in
			transform(x, y).map(mov(
				(Double(x) - 1.5) * inch,
				(Double(y) - 2.5) * inch)
			)
		}
	})
}

public func holes(_ w: Double, _ h: Double, _ length: Double, _ radius: Double) -> Model {
	mirror(.xz, .yz) • mov(w, h) § cylinder(length, radius)
}

public func mill(_ w: Double, _ h: Double, _ t: Double,
				 axis: Axis = .z, r: Double = 2, c: Double = 0.5) -> Model {
	box(w, h, t).fillet(r, edges: .parallel(axis)).chamfer(c)
}
public func frame(_ w: Double, _ h: Double, _ t: Double, _ wt: Double,
				  c: Double = 0.5, ir: Double = 2) -> Model {
	sum([
		mirror(.xz) • mov(y: h / 2 - wt / 2) § box(w, wt, t),
		mirror(.yz) • mov(w / 2 - wt / 2) § box(wt, h, t),
	]) * mill(w, h, t, r: ir, c: c)
}
public func xxx(_ w: Double, _ h: Double, _ t: Double, _ wt: Double, _ ws: Double,
				c: Double = 0.5, ir: Double = 2) -> Model {
	guard ws > 0, w > 2 * wt else { return Model(build: { throw ModelError.invalidArgument("Invalid lattice spacing or width.") }) }
	let count = Int(((w - wt * 2) / ws).rounded(.toNearestOrEven))
	guard count > 1 else { return .empty }
	return sum((1..<count).map { i in
		let d = ws * Double(i)
		return mirror(.yz) • mov(d - w / 2, d - h / 2) • rotz(-45) §
		box(d * 2 * s2, wt, t).chamfer(c)
	}) * box(w, h, t).chamfer(c)
}
