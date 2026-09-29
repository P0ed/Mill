import Foundation
import OCCTSwift

public struct ThreadSpec: Sendable {
	public let nominal: Double
	public let passDrill: Double
	public let threadDrill: Double
	public let pitch: Double
	public var veeHeight: Double { pitch / (2 * tan(.pi / 6)) }
	public var majorDiameter: Double { nominal }
	public var minorDiameter: Double { nominal - 2 * veeHeight * 5 / 8 }

	public init(_ nominal: Double, _ passDrill: Double, _ threadDrill: Double, _ pitch: Double) {
		self.nominal = nominal
		self.passDrill = passDrill
		self.threadDrill = threadDrill
		self.pitch = pitch
	}

	public static let sizes: [String: ThreadSpec] = [
		"M2": .init(2, 2.10, 1.60, 0.40),
		"M2.5": .init(2.5, 2.65, 2.05, 0.45),
		"M3": .init(3, 3.15, 2.50, 0.50),
		"M4": .init(4, 4.20, 3.30, 0.70),
		"M5": .init(5, 5.25, 4.20, 0.80),
		"M5 0.5": .init(5, 5.25, 4.50, 0.50),
		"M5.5 0.5": .init(5.5, 5.75, 5, 0.50),
		"M6": .init(6, 6.30, 5, 1),
		"M8": .init(8, 8.40, 6.80, 1.25),
		"M10": .init(10, 10.50, 8.50, 1.50),
		"M12": .init(12, 12.50, 10.2, 1.75),
		"M16": .init(16, 16.9, 14, 2),
		"M16 1.5": .init(16, 16.9, 14.6, 1.50),
		"M20": .init(20, 21, 17.5, 2.5),
		"M20 1.5": .init(20, 21, 18.5, 1.50),
		"M24": .init(24, 25, 21, 3),
		"Size 2 56": .init(0.0860 * inch, 0.0890 * inch, 0.0700 * inch, inch / 56),
		"Size 2 64": .init(0.0860 * inch, 0.0890 * inch, 0.0700 * inch, inch / 64),
		"1/4 20": .init(0.25 * inch, 0.257 * inch, 0.201 * inch, inch / 20),
		"5/8 11": .init(5 * inch / 8, 37 * inch / 64, 17 * inch / 32, inch / 11),
		"1 32": .init(inch, inch + 0.4, 0.9617 * inch, inch / 32),
	]
}

public enum ThreadLocation: Sendable { case `internal`, external }

public func thread(_ size: String, length: Double, location: ThreadLocation = .external,
				   segments: Int = 48) -> Model {
	guard let spec = ThreadSpec.sizes[size] else {
		return Model(build: { throw ModelError.invalidArgument("Unknown thread size: \(size)") })
	}
	return thread(spec, length: length, location: location, segments: segments)
}

/// Builds the original ISO/UTS helical ridge with tapered starts and ends.
/// An internal ridge is added to a bore wall; an external ridge is added to a shaft.
public func thread(_ spec: ThreadSpec, length: Double, location: ThreadLocation = .external,
				   segments: Int = 48) -> Model {
	let model = Model(build: {
		guard length.isFinite, spec.pitch.isFinite, spec.nominal.isFinite,
			  length > 0, spec.pitch > 0, spec.minorDiameter > 0, segments >= 8 else {
			throw ModelError.invalidArgument("Thread requires positive length, pitch, minor diameter and at least 8 segments per turn.")
		}
		let sampleCount = length / spec.pitch * Double(segments)
		guard sampleCount >= 2, sampleCount <= 100_000 else {
			throw ModelError.invalidArgument("Thread sample count must be between 2 and 100000.")
		}
		let pitch = spec.pitch, epsilon = max(pitch / 10, 0.025)
		let ext = location == .external
		let radius = ext ? spec.minorDiameter / 2 - epsilon : spec.majorDiameter / 2 + epsilon
		let h1 = pitch * (ext ? 3 / 4.0 : 7 / 8.0) / 2
		let h2 = pitch * (ext ? 1 / 8.0 : 1 / 4.0) / 2
		let cut = spec.veeHeight * 5 / 8 * (ext ? 1 : -1)
		let count = Int(sampleCount)
		func helix(_ depth: Double, _ offset: Double) throws -> Wire {
			let fraction = 0.685 * pitch / length
			let points = (0...count).map { i -> SIMD3<Double> in
				let t = Double(i) / Double(count)
				let factor: Double
				if t <= fraction { factor = sin(.pi / 2 * t / fraction) }
				else if t >= 1 - fraction { factor = -sin(2 * .pi - .pi / 2 * (1 - t) / fraction) }
				else { factor = 1 }
				let r = radius + depth * factor
				let angle = 2 * .pi * length / pitch * t
				return SIMD3(-r * sin(angle), r * cos(angle), length * t + offset * factor)
			}
			return try require(Wire.interpolate(through: points), "thread helix")
		}
		let e1b = try helix(0, -h1), e1t = try helix(0, h1)
		let e2b = try helix(cut, -h2), e2t = try helix(cut, h2)
		let faces = try [(e1b, e1t), (e2b, e2t), (e1b, e2b), (e1t, e2t)].map {
			try require(Shape.ruled(profile1: $0.0, profile2: $0.1), "thread ruled surface")
		}
		let shell = try require(Shape.sew(shapes: faces), "thread sewing")
		let solid = try require(Shape.solid(from: shell), "thread solid")
		return try require(solid.healed(), "thread healing")
	})
	return location == .external ? rotz(180)(model) : model
}
