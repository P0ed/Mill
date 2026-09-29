import Foundation
import OCCTSwift

public func threeView(_ model: Model) throws -> Model {
    let size = try bounds(model).size
    let offset = size.x / 4
    return (mov(size.x / 2 + size.y / 2, 0, size.y / 2 + size.z / 2) • compound)([
        model,
        (mov(size.x / 2 + size.y / 2 + offset) • rotz(-90))(model),
        (mov(z: size.y / 2 + size.z / 2 + offset) • rotx(90))(model),
    ])
}

/// Three orthographic views, using OCCT hidden-line removal and sampled vector edges.
public func writeSVG(_ model: Model, to url: URL, hidden: Bool = false) throws {
    let originalBounds = try bounds(model)
    let center = originalBounds.center
    let centered = mov(-center.x, -center.y, -center.z)(model)
    let views = try roty(90)(threeView(centered)).shape
    let drawing = try require(Drawing.project(views, direction: SIMD3(0, -1, 0)), "SVG projection")
    func lines(_ shape: Shape?) -> [[SIMD3<Double>]] {
        shape?.allEdgePolylines(deflection: 0.02) ?? []
    }
    let visible = lines(drawing.visibleEdges) + lines(drawing.outlineEdges)
    let hiddenLines = hidden ? lines(drawing.hiddenEdges) : []
    let points = (visible + hiddenLines).flatMap(id)
    guard let first = points.first else { throw ModelError.operation("SVG edges") }
    var lo = SIMD2(first.x, first.y), hi = lo
    for p in points {
        lo.x = min(lo.x, p.x); lo.y = min(lo.y, p.y)
        hi.x = max(hi.x, p.x); hi.y = max(hi.y, p.y)
    }
    let scale = 740 / max(hi.x - lo.x, hi.y - lo.y, 1e-9)
    let lineWidth = originalBounds.size.x > 100 ? 0.3 : 0.075
    func paths(_ polylines: [[SIMD3<Double>]], color: String, dashed: Bool) -> String {
        let paths = polylines.filter { $0.count > 1 }.map { points in
            let coordinates = points.enumerated().map { i, p in
                "\(i == 0 ? "M" : "L")\(30 + (p.x - lo.x) * scale),\(30 + (hi.y - p.y) * scale)"
            }.joined(separator: " ")
            return "<path d=\"\(coordinates)\"/>"
        }.joined(separator: "\n")
        let dash = dashed ? " stroke-dasharray=\"3,3\"" : ""
        return "<g fill=\"none\" stroke=\"\(color)\" stroke-width=\"\(lineWidth)\"\(dash)>\n\(paths)\n</g>"
    }
    let svg = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="800" height="800" viewBox="0 0 800 800">
    \(paths(hiddenLines, color: "#dfdfdf", dashed: true))
    \(paths(visible, color: "#070707", dashed: false))
    </svg>
    """
    try svg.write(to: url, atomically: true, encoding: .utf8)
}

public func export(_ name: String, _ model: Model, to directory: URL = URL(fileURLWithPath: "."),
                   stl: Bool = true, svg: Bool = true, step: Bool = true,
                   hidden: Bool = false, deflection: Double = 0.1) throws {
    guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else {
        throw ModelError.invalidArgument("Export name must be a nonempty filename without directories.")
    }
    guard deflection.isFinite, deflection > 0 else { throw ModelError.invalidArgument("Deflection must be positive.") }
    let shape = try model.shape
    guard shape.isValid else { throw ModelError.operation("validation of \(name)") }
    func destination(_ folder: String, _ ext: String) throws -> URL {
        let dir = directory.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name).appendingPathExtension(ext)
    }
    if stl { try Exporter.writeSTL(shape: shape, to: destination("STL", "stl"), deflection: deflection) }
    if svg { try writeSVG(model, to: destination("SVG", "svg"), hidden: hidden) }
    if step { try Exporter.writeSTEP(shape: shape, to: destination("STEP", "step")) }
}
