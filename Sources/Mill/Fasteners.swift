import Foundation
import OCCTSwift

/// ISO 14579 M4×14 cylinder-head screw: 7×4 mm head, T20 socket and 0.7 mm pitch.
/// The bearing face is at Z=0, the head faces +Z, and the tip is at Z=-14.
public func boltM4x14() -> Model {
	let length = 14.0, headHeight = 4.0, socketDepth = 1.6
	let spec = ThreadSpec.sizes["M4"]!
	let head = mov(z: headHeight / 2)(cylinder(headHeight, 3.5))
		.chamfer(0.3, edges: .maximum(.z))
		.chamfer(0.15, edges: .minimum(.z))
	let socket = Model(build: {
		let profile = try torxT20()
		return try require(
			Shape.extrude(profile: profile, direction: SIMD3(0, 0, 1), length: socketDepth + pl),
			"T20 socket extrusion"
		)
	})
	let core = mov(z: -length / 2)(cylinder(length, spec.minorDiameter / 2))
	let ridge = mov(z: -length)(thread(spec, length: length))
	let envelope = mov(z: -length / 2)(cylinder(length, spec.nominal / 2))
		.chamfer(0.45, edges: .minimum(.z))
	// The short runout joins the fully threaded shank to the bearing face.
	let runout = mov(z: -0.35 / 2)(cylinder(0.35, spec.nominal / 2))
	let shank = ((core + ridge) * envelope) + runout

	return (head - mov(z: headHeight - socketDepth)(socket)) + shank
}

/// Twelve tangent circular arcs, using T20's nominal 3.95/2.85 mm diameters.
/// This is a visual socket profile rather than a manufacturing gauge.
private func torxT20() throws -> Wire {
	let outer = 3.95 / 2, inner = 2.85 / 2, lobeRadius = 0.395
	let lobeCenter = outer - lobeRadius
	let c = cos(Double.pi / 6)
	let valleyRadius = (
		lobeCenter * lobeCenter + inner * inner
			- 2 * lobeCenter * inner * c - lobeRadius * lobeRadius
	) / (2 * (lobeCenter * c + lobeRadius - inner))

	func polar(_ radius: Double, _ angle: Double) -> SIMD3<Double> {
		SIMD3(radius * cos(angle), radius * sin(angle), 0)
	}
	func tangent(_ angle: Double, _ side: Double) -> SIMD3<Double> {
		let lobe = polar(lobeCenter, angle)
		let valley = polar(inner + valleyRadius, angle + side * .pi / 6)
		return lobe + (valley - lobe) * (lobeRadius / (lobeRadius + valleyRadius))
	}

	var edges: [Edge] = []
	for i in 0..<6 {
		let angle = Double(i) * .pi / 3
		let tip = try require(Wire.arc(
			start: tangent(angle, -1),
			midpoint: polar(outer, angle),
			end: tangent(angle, 1)
		), "T20 lobe")
		let valley = try require(Wire.arc(
			start: tangent(angle, 1),
			midpoint: polar(inner, angle + .pi / 6),
			end: tangent(angle + .pi / 3, -1)
		), "T20 valley")
		edges += tip.edges() + valley.edges()
	}
	return try require(Wire.wireFromEdges(edges), "T20 profile")
}
