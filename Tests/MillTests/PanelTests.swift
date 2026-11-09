import Foundation
import Testing
@testable import Mill

@Suite(.serialized)
struct PanelTests {
	func document(
		size: String = "fourBySix",
		version: Int = 1,
		cells edits: [Int: [String: Any]] = [:],
		count: Int = 48
	) throws -> Data {
		var cells = Array(
			repeating: ["knobAngle": 45, "togglePosition": "up"] as [String: Any],
			count: count
		)
		for (index, edit) in edits {
			cells[index].merge(edit) { _, new in new }
		}

		return try JSONSerialization.data(withJSONObject: ["version": version, "size": size, "cells": cells])
	}

	func volume(_ model: Model) throws -> Double { try model.result.get()?.volume ?? 0 }

	@Test func exampleDocument() throws {
		let url = try #require(Bundle.module.url(
			forResource: "serge-prototype",
			withExtension: "panel",
			subdirectory: "Fixtures"
		))
		let panel = try PanelLayout(contentsOf: url)

		#expect(panel.modules == 2)
		#expect(panel.size.width == 215.9)
		#expect(panel.size.height == 177.8)
		#expect(panel.cells.count == 48)
		#expect(panel.cells[0].control == .lemo1B303)
		#expect(panel.cells[2].knobAngle == 35)
		#expect(Set(panel.cells.compactMap(\.control)) == Set(PanelLayout.Control.allCases))
	}

	@Test func rejectsInvalidDocuments() throws {
		for data in [
			Data("not JSON".utf8),
			try document(version: 2),
			try document(size: "unknown"),
			try document(count: 47),
			try document(cells: [0: ["control": "unknown"]]),
			try document(cells: [0: ["knobAngle": 151]]),
			try document(cells: [0: ["togglePosition": "left"]]),
		] {
			#expect(throws: (any Error).self) { try PanelLayout.decode(data) }
		}
	}

	@Test func rowOrderStrideAndHiddenColumns() throws {
		let data = try document(cells: [
			0: ["control": "bourns51"],
			7: ["control": "lemo1B304"], // Hidden, retained at stride eight.
			41: ["control": "pomona1581"], // Bottom row, second visible column.
		])
		let panel = try PanelLayout.decode(data)

		let pots = panel.models { $0.control == .bourns51 ? cylinder(2, 1) : nil }
		let center = try bounds(pots).center
		#expect(abs(center.x - -38.1) < 1e-5)
		#expect(abs(center.y - 63.5) < 1e-5)

		let jacks = panel.models { $0.control == .pomona1581 ? cylinder(2, 1) : nil }
		let jackCenter = try bounds(jacks).center
		#expect(abs(jackCenter.x - -12.7) < 1e-5)
		#expect(abs(jackCenter.y - -63.5) < 1e-5)

		let hidden = panel.models { $0.control == .lemo1B304 ? cylinder(2, 1) : nil }
		#expect(try hidden.result.get() == nil)
	}

	@Test func savedHardwareOrientations() throws {
		let panel = try PanelLayout.decode(document(cells: [
			0: ["control": "bourns51", "knobAngle": 90],
			9: ["control": "nkkMN12", "togglePosition": "up"],
			18: ["control": "nkkMN12", "togglePosition": "down"],
		]))
		let parts = try agc(panel: panel)
		let expected = mov(z: 14.5)(
			mov(-38.1, 63.5)(bourns51(-90, nutAngle: 0))
				+ mov(-12.7, 38.1)(toggle(false, nutAngle: 0))
				+ mov(12.7, 12.7)(toggle(true, nutAngle: 0))
		)
		let actual = parts.controls

		#expect(try volume(actual - expected) < 1e-5)
		#expect(try volume(expected - actual) < 1e-5)

		let knob = mov(-38.1, 63.5, 20)(knobV30(-90))
		#expect(try volume(parts.knobs - knob) < 1e-5)
		#expect(try volume(knob - parts.knobs) < 1e-5)
	}

	@Test(arguments: PanelLayout.Control.allCases)
	func cutoutAndHardware(_ control: PanelLayout.Control) throws {
		let shape = try control.cutout(4).shape
		#expect(shape.isValid)

		let expectedDiameter: Double = switch control {
		case .lemo1B302, .lemo1B303, .lemo1B304: 12.2
		case .pomona1581: 9.53
		case .bourns51: 9.55
		case .nkkMBNF15: 6.5
		case .nkkMN12, .vccCLB300: 6.35
		}
		#expect(
			abs(try bounds(control.cutout(4)).size.y - (control == .pomona1581 ? 8.89 : expectedDiameter)) < 1e-5
		)

		let panel = try PanelLayout.decode(document(cells: [0: ["control": control.rawValue]]))
		#expect(try panel.controls().shape.isValid)
	}

	@Test(arguments: ["fourBySix", "eightBySix"])
	func panelSizedCaseAndCutouts(_ size: String) throws {
		let blank = try PanelLayout.decode(document(size: size))
		let panel = try PanelLayout.decode(document(size: size, cells: [9: ["control": "bourns51"]]))
		let blankParts = try agc(panel: blank, includeControls: false)
		let parts = try agc(panel: panel, includeControls: false)
		let b = try bounds(parts.enclosure)

		#expect(abs(b.size.x - panel.size.width) < 1e-4)
		#expect(abs(b.size.y - panel.size.height) < 1e-4)
		#expect(abs(b.size.z - 30.002) < 1e-4)
		#expect(try parts.bottom.shape.isValid)
		#expect(try parts.top.shape.isValid)
		#expect(try parts.controls.result.get() == nil)
		#expect(try parts.knobs.result.get() == nil)
		#expect(try parts.bolts.result.get() == nil)
		#expect(abs(try volume(parts.bottom) - volume(blankParts.bottom)) < 1e-5)
		#expect(try volume(blankParts.top) > volume(parts.top))

		// Probe the top skin: the selected cell is drilled through and its neighbour stays solid.
		let x = (1 - Double(panel.size.columns - 1) / 2) * inch
		#expect(try volume(parts.top * mov(x, 38.1, 14.5)(cylinder(0.5, 1))) < 1e-5)
		#expect(try volume(parts.top * mov(x + inch, 38.1, 14.5)(cylinder(0.5, 1))) > 1)
	}

	@Test(arguments: ["fourBySix", "eightBySix"])
	func populatedMountingBolts(_ size: String) throws {
		let panel = try PanelLayout.decode(document(size: size, cells: [0: ["control": "bourns51"]]))
		let parts = try agc(panel: panel)
		let bolts = try parts.bolts.shape
		let count = panel.modules == 1 ? 4 : 6
		#expect(bolts.isValid)
		#expect(bolts.subShapeCount(ofType: .solid) == count)
		let b = try bounds(parts.bolts)
		#expect(abs(b.min.z + 4) < 1e-5)
		#expect(abs(b.max.z - 14) < 1e-5)

		let x = panel.size.width / 2 - 6.35
		let xs = panel.modules == 1 ? [-x, x] : [-x, 0, x]
		for x in xs {
			for y in [-82.55, 82.55] {
				// The head bears on the recessed flange at Z=10, with its socket facing up.
				let head = mov(x + 2.5, y, 11)(box(0.2, 0.2, 0.2))
				#expect(abs(try volume(parts.bolts * head) - 0.008) < 1e-6)
				let socket = mov(x, y, 13)(box(0.2, 0.2, 0.2))
				#expect(try volume(parts.bolts * socket) < 1e-6)
				let bearing = mov(x + 2.5, y, 9.9)(box(0.1, 0.1, 0.1))
				#expect(abs(try volume(parts.top * bearing) - 0.001) < 1e-6)
			}
		}
		#expect(try volume(parts.bolts * parts.top) < 1e-5)
		#expect(try parts.populated.shape.isValid)
		#expect(abs(try volume(parts.populated) - parts.parts.reduce(0) { try $0 + volume($1) }) < 1e-5)
	}

	@Test func singleModuleConstruction() throws {
		let panel = try PanelLayout.decode(document())
		let parts = try agc(panel: panel, includeControls: false)
		let width = try bounds(parts.enclosure).size.x
		for (model, direction, radius) in [(parts.bottom, -1.0, 1.65), (parts.top, 1.0, 2.1)] {
			#expect(try model.shape.isValid)
			#expect(try model.shape.subShapeCount(ofType: .solid) == 1)

			for y in [-82.55, 82.55] {
				// Only the four corner bolts are drilled; the middle of each flange is solid.
				let center = mov(0, y, direction * 9)(box(1, 1, 1))
				#expect(abs(try volume(model * center) - 1) < 1e-5)
				for x in [-width / 2 + 6.35, width / 2 - 6.35] {
					let hole = mov(x, y, direction * 7.5)(cylinder(20, radius))
					#expect(try volume(model * hole) < 1e-5)
					let ring = mov(x, y, direction * 2.5)(
						cylinder(3, radius + 0.4) - cylinder(3, radius + 0.1)
					)
					#expect(abs(try volume(model * ring) - volume(ring)) < 1e-5)
				}
			}

			// The recessed skin must not open through either long side wall.
			for x in [-width / 2 + 7.1, width / 2 - 7.1] {
				for y in [-55.0, -25.0, 25.0, 55.0] {
					let wall = mov(x, y, direction * 9)(box(1, 1, 1))
					#expect(abs(try volume(model * wall) - 1) < 1e-5)
				}
			}

			// Pockets cross x=0; the horizontal rib and outer skin remain.
			for y in [-38.1, 38.1] {
				#expect(try volume(model * mov(0, y, direction * 9)(box(1, 1, 1))) < 1e-5)
				#expect(abs(try volume(model * mov(0, y, direction * 14)(box(1, 1, 1))) - 1) < 1e-5)
			}
			#expect(abs(try volume(model * mov(0, 0, direction * 9)(box(1, 1, 1))) - 1) < 1e-5)
		}
	}

	@Test(arguments: ["fourBySix", "eightBySix"])
	func cornerProfiles(_ size: String) throws {
		let panel = try PanelLayout.decode(document(size: size))
		let parts = try agc(panel: panel, includeControls: false)
		let stepX = panel.size.width / 2 - 6.35
		let innerX = panel.size.width / 2 - 12.7
		let cornerCut = (2 - s2) * 6.35
		let innerY = 76.2 + cornerCut + 0.5

		for (model, direction) in [(parts.bottom, -1.0), (parts.top, 1.0)] {
			for sx in [-1.0, 1.0] {
				for sy in [-1.0, 1.0] {
					// The raised step has a diagonal corner at every actual case width.
					let clipped = mov(sx * (stepX - cornerCut / 4), sy * (76.2 - cornerCut / 4), direction * 14)(box(0.5, 0.5, 0.5))
					let retained = mov(sx * (stepX - cornerCut), sy * (76.2 - cornerCut), direction * 14)(box(0.5, 0.5, 0.5))
					#expect(try volume(model * clipped) < 1e-5)
					#expect(abs(try volume(model * retained) - 0.125) < 1e-5)

					// The cavity follows a diagonal directly into its end rail, without a square jog.
					let wall = mov(sx * (innerX + 0.8), sy * (innerY - 0.8), direction * 2.5)(box(0.25, 0.25, 0.25))
					let cavity = mov(sx * (innerX + 0.8), sy * (innerY - 2), direction * 2.5)(box(0.25, 0.25, 0.25))
					#expect(abs(try volume(model * wall) - 0.015625) < 1e-5)
					#expect(try volume(model * cavity) < 1e-5)
				}
			}
		}
	}
}
