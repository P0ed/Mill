import Foundation
import OCCTSwift
import Testing
@testable import Mill

@Suite(.serialized)
struct GeometryTests {
    struct Reference: Decodable {
        let volume: Double
        let bounds: [Double]
    }

    func compareWithDIY(_ shape: Shape, name: String, tolerance: Double = 0.001) throws {
        let url = try #require(Bundle.module.url(forResource: "diy-metrics", withExtension: "json", subdirectory: "Fixtures"))
        let references = try JSONDecoder().decode([String: Reference].self, from: Data(contentsOf: url))
        let reference = try #require(references[name])
        #expect(abs(try #require(shape.volume) - reference.volume) < tolerance)
        let b = try #require(shape.boundingBoxOptimal())
        let actual = [b.min.x, b.min.y, b.min.z, b.max.x, b.max.y, b.max.z]
        for (actual, expected) in zip(actual, reference.bounds) {
            #expect(abs(actual - expected) < tolerance)
        }
    }

    @Test func primitiveCoordinatesAndComposition() throws {
        let b = try bounds(box(10, 20, 30))
        #expect(abs(b.min.z + 15) < 1e-5)
        #expect(abs(b.max.y - 10) < 1e-5)
        let c = try bounds(cylinder(8, 2))
        #expect(abs(c.min.z + 4) < 1e-5)
        #expect(abs(c.max.z - 4) < 1e-5)
        let transformed = try bounds((rotz(90) • mov(10))(box(2, 4, 6)))
        #expect(abs(transformed.center.x) < 1e-5)
        #expect(abs(transformed.center.y - 10) < 1e-5)
        #expect(abs(transformed.size.x - 4) < 1e-5)
        #expect(abs(try bounds(cone(2, 1, 5)).min.z) < 1e-5)
    }

    @Test func selectionsAndMirrors() throws {
        let cube = try box(10, 20, 30).shape
        #expect(EdgeSelection.parallel(.z).select(in: cube).count == 4)
        #expect(EdgeSelection.positive(.z).select(in: cube).count == 4)
        #expect(EdgeSelection.maximum(.z).select(in: cube).count == 4)
        #expect(EdgeSelection.notParallel(.z).select(in: cube).count == 8)
        let pattern = try holes(10, 20, 6, 1).shape
        #expect(abs(try #require(pattern.volume) - 4 * .pi * 6) < 1e-5)
        // Coincident mirrors on x=0 must not double the physical volume.
        let middle = try holes(0, 20, 6, 1).shape
        #expect(abs(try #require(middle.volume) - 2 * .pi * 6) < 1e-5)
    }

    @Test func patternsAndGrids() throws {
        let cells = (0..<4).flatMap { x in (0..<6).map { (x, $0) } }
        #expect(cells.filter { ptnM($0.0, $0.1) }.count == 20)
        #expect(cells.filter { ptnBotM($0.0, $0.1) }.count == 10)
        #expect(cells.allSatisfy { ptnX($0.0, $0.1) != ptnD($0.0, $0.1) })
        let rules = ptnsMap((ptnTopL, { 1 }), (ptnAll, { 2 }))
        #expect(rules(0, 5) == 1)
        #expect(rules(1, 5) == 2)
        let g = grid4 { x, y in ptnTopL(x, y) ? box(2, 2, 2) : nil }
        let center = try bounds(g).center
        #expect(abs(center.x + 1.5 * inch) < 1e-5)
        #expect(abs(center.y - 2.5 * inch) < 1e-5)
        #expect(try grid4 { _, _ in nil }.result.get() == nil)
        #expect(abs(try #require((box(2, 3, 4) + .empty).shape.volume) - 24) < 1e-5)
    }

    @Test func failuresArePropagated() {
        #expect(throws: (any Error).self) { try mov(5)(box(-1, 2, 3)).shape }
        #expect(throws: (any Error).self) { try thread("unknown", length: 5).shape }
        #expect(throws: (any Error).self) { try thread("M4", length: -1).shape }
        #expect(throws: (any Error).self) { try AGCDimensions(modules: 0) }
    }

    @Test(arguments: ["lemo", "pomona", "toggle", "bourns", "led", "clb", "v30", "tower", "frame", "lattice", "squircle"])
    func hardware(_ name: String) throws {
        let model: Model
        switch name {
        case "lemo": model = lemoECG1B303()
        case "pomona": model = pomona1581()
        case "toggle": model = toggle(true, nutAngle: 0)
        case "bourns": model = bourns51(0, nutAngle: 0)
        case "led": model = led5()
        case "clb": model = clb300()
        case "v30": model = knobV30(0)
        case "tower": model = knobTower(0)
        case "frame": model = frame(40, 50, 5, 3)
        case "lattice": model = xxx(40, 50, 5, 3, 10)
        default: model = extrude(squircle(20, 30, 4), 3)
        }
        let shape = try model.shape
        #expect(shape.isValid)
        #expect(try #require(shape.volume) > 0)
        if !["frame", "lattice", "squircle"].contains(name) {
            try compareWithDIY(shape, name: name)
        }
    }

    @Test(arguments: [ThreadLocation.internal, .external])
    func threads(_ location: ThreadLocation) throws {
        let shape = try thread("M4", length: 3, location: location).shape
        #expect(shape.isValidSolid)
        #expect(try #require(shape.volume) > 0)
        try compareWithDIY(shape, name: location == .internal ? "thread-internal" : "thread-external")
        let b = try bounds(Model(shape))
        #expect(abs(b.min.z) < 0.01)
        #expect(abs(b.max.z - 3) < 0.01)
    }

    @Test(arguments: [1, 2, 3])
    func enclosure(_ modules: Int) throws {
        let parts = try defaultAGC(modules: modules, includeControls: false)
        for (name, model) in [("bottom", parts.bottom), ("top", parts.top)] {
            let shape = try model.shape
            #expect(shape.isValid)
            #expect(try #require(shape.volume) > 0)
            try compareWithDIY(shape, name: "\(modules)-\(name)")
        }
        let b = try bounds(parts.enclosure)
        #expect(abs(b.size.x - (Double(modules) * 4 * inch + 0.5 * inch)) < 1e-4)
        #expect(abs(b.size.y - 7 * inch) < 1e-4)
        #expect(abs(b.size.z - 30.002) < 1e-4)
    }

    @Test func exportsAndSTEPRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = box(20, 30, 5) - cylinder(5, 2)
        try export("test", model, to: directory)
        let loaded = try Shape.loadSTEP(from: directory.appendingPathComponent("STEP/test.step"))
        #expect(loaded.isValid)
        #expect(abs(try #require(loaded.volume) - (3000 - 20 * .pi)) < 1e-4)
        let stl = try Data(contentsOf: directory.appendingPathComponent("STL/test.stl"))
        #expect(stl.count > 84)
        let svgURL = directory.appendingPathComponent("SVG/test.svg")
        let svg = try String(contentsOf: svgURL, encoding: .utf8)
        #expect(svg.contains("<svg"))
        #expect(svg.contains("<path"))
        #expect(!svg.contains("nan"))
        try writeSVG(model, to: svgURL, hidden: true)
        let withHidden = try String(contentsOf: svgURL, encoding: .utf8)
        #expect(withHidden.count > svg.count)
    }
}
