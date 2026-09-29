import Foundation
import OCCTSwift

public func lemo1BCutout(_ wt: Double) -> Model {
    cylinder(wt, 12.2 / 2) * box(10.7, 12.2, wt)
}
public func pomona1581Cutout(_ wt: Double) -> Model {
    cylinder(wt, 9.53 / 2) * mov(y: (9.53 - 8.89) / 2)(box(9.53, 8.89, wt))
}
public func hexNut(_ diameter: Double, _ length: Double, angle: Double? = nil) -> Model {
    let points = (0..<6).map { i -> SIMD2<Double> in
        let a = Double(i) * .pi / 3
        return SIMD2(cos(a), sin(a)) * diameter / 2
    }
    let blank = mov(z: length / 2)(cylinder(length, diameter / 2)).chamfer(length / 3)
    return rotz(angle ?? Double.random(in: 0..<60))(extrude(Wire.polygon(points), length) * blank)
}
public func lemoM12RoundNut() -> Model {
    mov(z: 2.5 / 2)(cylinder(2.5, 16 / 2).chamfer(1, edges: .maximum(.z)))
        - (rotz(45) • mirror(.xz, .yz) • rotz(-45) • mov(7))(box(1.4, 1.5, 5))
}
public func lemoECG1B303() -> Model {
    let pins = (0..<3).map { i in
        (mov(z: 1.5) • rotz(120 * Double(i)) • mov(2))(cylinder(3, 0.5))
    }
    let face = dif([cylinder(3.5, 12 / 2)] + pins).chamfer(0.25, edges: .maximum(.z))
    let groove = mov(z: 1.5)(cylinder(3, 7.75 / 2) - cylinder(3, 6.25 / 2))
    let body = (face - groove - mov(7.75 / 2, 0, 1.5)(box(0.5, 1, 3))) * box(12, 10.5, 3.5)
    return rotz(90)(mov(z: 3.5 / 2)(body) + lemoM12RoundNut())
}
public func pomona1581() -> Model {
    rotz(90)((cone(6.35, 6.15, 6.35) - mov(z: 6.35)(cylinder(12.5, 2.1)))
        .chamfer(0.5, edges: .maximum(.z)))
}
public func toggle(_ position: Bool? = nil, nutAngle: Double? = nil) -> Model {
    let pos = position ?? Bool.random()
    return (mov(z: 4.2 / 2) • rotz(90))(cylinder(4.2, 3.175).chamfer(0.5, edges: .maximum(.z)))
        + (mov(0, pos ? -1.7 : 1.7, 9) • rotx(pos ? 13 : -13))(
            rotz(90)(cylinder(14, 1.3).fillet(1.299)))
        + hexNut(8.5, 1.5, angle: nutAngle)
}
public func bourns51(_ angle: Double? = nil, nutAngle: Double? = nil) -> Model {
    let angle = angle ?? Double.random(in: -60...60)
    let base = (mov(z: 2.5) • rotz(90))(cylinder(5, 9.5 / 2).chamfer(0.5, edges: .maximum(.z)))
    let shaft = cylinder(10, 6.35 / 2).chamfer(0.5, edges: .maximum(.z)) - mov(z: 5)(box(7, 1.5, 3))
    return base + (mov(z: 9) • rotz(90 + angle))(shaft) + hexNut(14, 2.36, angle: nutAngle)
}
public func led5() -> Model {
    rotz(90)(mov(z: 4.5 / 2)(cylinder(4.5, 2.5)).fillet(2.499, edges: .maximum(.z)))
}
public func clb300() -> Model {
    let lens = mov(z: 7.2)(sphere(8)) * mov(z: -7.2)(sphere(8))
    return rotz(90)(mov(z: 0.9)(lens) + cylinder(1.8, 7.11 / 2))
}

public typealias Knob = (Double?) -> Model
public func mkKnob(_ angle: Double?, _ c: Double, _ transform: @escaping Transform) -> Model {
    let body = rotz(90)(cylinder(in2, in4).chamfer(c, edges: .maximum(.z)))
        - mov(z: 3 - 9.499 / 2)(cylinder(9.5, in8))
    return (rotz(angle ?? Double.random(in: -60...60)) • mov(z: in4) • transform)(body)
}
public func knobV30(_ angle: Double? = nil) -> Model {
    mkKnob(angle, 0.15) { body in
        body - (mirror(.yz) • mov(13.5, 0, 8) • roty(75))(box(20, 20, 20))
            - mov(0, 4 - 0.75, in4)(box(1.5, 8, 1.5).chamfer(0.749))
    }
}
public func knobTower(_ angle: Double? = nil) -> Model {
    let h = inX, h2 = h / 2, w = in4 - inX, w2 = w * 0.6, c = sqrt(h) / 8
    func plus(_ width: Double) -> Model {
        let b = box(width, 16, h).chamfer(c)
        return b + rotz(90)(b)
    }
    return mkKnob(angle, c) { body in
        body - mov(z: in4)(plus(w) + mov(z: h2 - c)(plus(w + c * 2))
            + mov(z: -h2)(plus(w2)) + mov(z: -c)(plus(w2 + c * 2)))
    }
}
