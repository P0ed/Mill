import Foundation
import Testing
@testable import Mill

@Suite(.serialized)
struct PanelTests {
	func document(size: String = "fourBySix", version: Int = 1,
				  cells edits: [Int: [String: Any]] = [:], count: Int = 48) throws -> Data {
		var cells = Array(repeating: ["knobAngle": 45, "togglePosition": "up"] as [String: Any], count: count)
		for (index, edit) in edits { cells[index].merge(edit) { _, new in new } }
		return try JSONSerialization.data(withJSONObject: ["version": version, "size": size, "cells": cells])
	}

	func volume(_ model: Model) throws -> Double { try model.result.get()?.volume ?? 0 }

	@Test func exampleDocument() throws {
		let url = try #require(Bundle.module.url(forResource: "serge-prototype", withExtension: "panel", subdirectory: "Fixtures"))
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
			try document(version: 2), try document(size: "unknown"), try document(count: 47),
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
		let expected = mov(-38.1, 63.5)(bourns51(-90, nutAngle: 0))
		+ mov(-12.7, 38.1)(toggle(false, nutAngle: 0))
		+ mov(12.7, 12.7)(toggle(true, nutAngle: 0))
		let actual = panel.controls(angle: nil)
		#expect(try volume(actual - expected) < 1e-5)
		#expect(try volume(expected - actual) < 1e-5)
		let knob = mov(-38.1, 63.5)(knobV30(-90))
		#expect(try volume(panel.knobs(angle: nil) - knob) < 1e-5)
		let override = mov(-38.1, 63.5)(knobV30(0))
		#expect(try volume(panel.knobs(angle: 0) - override) < 1e-5)
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
		#expect(abs(try bounds(control.cutout(4)).size.y - (control == .pomona1581 ? 8.89 : expectedDiameter)) < 1e-5)
		let panel = try PanelLayout.decode(document(cells: [0: ["control": control.rawValue]]))
		#expect(try panel.controls(angle: nil).shape.isValid)
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
		#expect(abs(try volume(parts.bottom) - volume(blankParts.bottom)) < 1e-5)
		#expect(try volume(blankParts.top) > volume(parts.top))
		// Probe the top skin: the selected cell is drilled through and its neighbour stays solid.
		let x = (1 - Double(panel.size.columns - 1) / 2) * inch
		#expect(try volume(parts.top * mov(x, 38.1, 14.5)(cylinder(0.5, 1))) < 1e-5)
		#expect(try volume(parts.top * mov(x + inch, 38.1, 14.5)(cylinder(0.5, 1))) > 1)
	}
}
