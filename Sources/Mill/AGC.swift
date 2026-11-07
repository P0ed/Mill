import Foundation

public struct AGCParts: Sendable {
	public let bottom: Model
	public let top: Model
	public let controls: Model
	public let knobs: Model
	public let threadSection: Model?
	public var parts: [Model] { [bottom, top, controls, knobs] + [threadSection].compactMap(id) }
	public var enclosure: Model { bottom + top }
	public var populated: Model { sum([bottom, top, controls, knobs]) }
}

public struct AGCDimensions: Sendable {
	public let modules: Int
	public let width: Double
	public let height: Double
	public let depth = 30.0
	public let wall = 3.0
	public let column = 0.5 * inch

	public init(panel: PanelLayout) {
		modules = panel.modules
		width = panel.size.width
		height = panel.size.height
	}
}

/// Build an AGC enclosure using the size and visible controls saved by Panels.
public func agc(
	panel: PanelLayout,
	threads: Bool = false,
	includeControls: Bool = true
) throws -> AGCParts {
	let dimensions = AGCDimensions(panel: panel)
	let modules = dimensions.modules
	let m4xr = 4.2 / 2, m4dr = 3.3 / 2, wt = dimensions.wall
	let cw = 4 * inch, ch = 6 * inch, col = dimensions.column, hol = col / 2
	let w = dimensions.width, h = dimensions.height, t = dimensions.depth
	let t2 = t / 2, t3 = t2 / 2, dt = 5.0, c2 = 0.5, crh = (2 - s2) * hol

	func boxFC(_ width: Double, _ height: Double, _ depth: Double) -> Model {
		mill(width, height, depth, r: 3, c: c2)
	}

	func moduleCopies(_ model: Model) -> Model {
		mov(-cw / 2 * Double(modules - 1)) • sum § (0..<modules).map { i in
			mov(Double(i) * cw)(model)
		}
	}

	func mountingHoles(_ radius: Double) -> Model {
		let corners = holes(w / 2 - hol, h / 2 - hol, t2, radius)
		return modules == 1 ? corners : corners + holes(0, h / 2 - hol, t2, radius)
	}

	func brick(_ direction: Double) -> Model {
		let cavityWidth = (w - col) / Double(modules) - col
		let cavity = moduleCopies(
			boxFC(cavityWidth, h - wt * 2, t2)
				+ box(cavityWidth + crh * 2 + 1, ch + crh * 2 + 1, t2)
					.chamfer(crh + 1, edges: .parallel(.z)).chamfer(c2, edges: .notParallel(.z))
		)

		let pockets = if modules == 1 {
			mirror(.xz)
				• mov(0, ch / 4 - 0.5, (wt - t3 + dt / 2 + pl / 2) * direction)
				§ boxFC(w - col - wt * 2, ch / 2 - wt, 2 + dt + pl)
		} else {
			mirror(.xz, .yz)
				• mov(cw / 2 - 0.5, ch / 4 - 0.5, (wt - t3 + dt / 2 + pl / 2) * direction)
				§ boxFC(cw - wt, ch / 2 - wt, 2 + dt + pl)
		}

		return dif([
			box(w, h, t2).chamfer(crh, edges: .positive(.z)),

			mov(z: (2 + dt) * direction) • sum
				§ [boxFC(w - wt * 2, h - col * 2, t2), cavity],

			pockets,

			mirror(.xz) • mov(0, h / 2, (pl / 2 - t3) * direction)
				§ box(w + t, col * 2, dt * 2 + pl).chamfer(c2),

			mirror(.yz) • mov(w / 2, 0, (pl / 2 - t3) * direction)
				§ box(col, h + t, dt * 2 + pl).chamfer(c2),

			mirror(.yz, .xz)
				• mov((w - col) / 2, ch / 2, (pl / 2 - t3) * direction)
				• rotz(45)
				§ box(crh * s2, t, dt * 2 + pl).chamfer(c2),
		])
		.chamfer(c2, edges: direction > 0 ? .minimum(.z) : .maximum(.z))
	}

	let bottom = brick(1)
		- mountingHoles(m4dr)

	let top = brick(-1)
		- mountingHoles(m4xr)
		- panel.cutouts(t2)

	_ = try bottom.shape
	_ = try top.shape

	let controls = includeControls ? panel.controls() : .empty
	let extra = includeControls ? panel.knobs() : .empty

	var section: Model?
	if threads {
		let cut = (
			bottom
				- holes(w / 2 - hol, h / 2 - hol, t, m4xr)
				+ mov(w / 2 - hol, h / 2 - hol, -dt / 2)(
					thread("M4", length: t2 - dt, location: .internal)
				)
		) * mov(w / 2, h / 2)(
			box(col, col * 2, t)
		)

		section = rotz(180) • mov((col / 2 - w) / 2, (col * 3 / 2 - h) / 2) § cut
	}

	let parts = AGCParts(
		bottom: mov(z: -t3 - pl)(bottom),
		top: mov(z: t3 + pl)(top),
		controls: mov(z: t2 - 0.5)(controls),
		knobs: mov(z: t2 + 5)(extra),
		threadSection: section
	)
	for part in parts.parts {
		_ = try part.result.get()
	}

	return parts
}
