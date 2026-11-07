import Foundation

/// The manufacturing fields of a version 1 document saved by ../Panels.
/// Artwork and finish fields are intentionally ignored.
public struct PanelLayout: Decodable, Sendable {
	public enum Size: String, Decodable, Sendable {
		case fourBySix, eightBySix

		public var columns: Int { self == .fourBySix ? 4 : 8 }
		public var width: Double { self == .fourBySix ? 107.95 : 215.9 }
		public var height: Double { 177.8 }
	}

	public enum Control: String, Decodable, CaseIterable, Sendable {
		case lemo1B302, lemo1B303, lemo1B304, pomona1581
		case nkkMN12, nkkMBNF15, vccCLB300, bourns51

		func cutout(_ depth: Double) -> Model {
			switch self {
			case .lemo1B302, .lemo1B303, .lemo1B304: lemo1BCutout(depth)
			case .pomona1581: pomona1581Cutout(depth)
			case .bourns51: cylinder(depth, 9.55 / 2)
			case .nkkMBNF15: cylinder(depth, 6.5 / 2)
			case .nkkMN12, .vccCLB300: cylinder(depth, 6.35 / 2)
			}
		}
	}

	public struct Cell: Decodable, Sendable {
		public enum TogglePosition: String, Decodable, Sendable { case up, down }

		public let control: Control?
		public let knobAngle: Double
		public let togglePosition: TogglePosition

		private enum CodingKeys: String, CodingKey { case control, knobAngle, togglePosition }

		public init(from decoder: Decoder) throws {
			let values = try decoder.container(keyedBy: CodingKeys.self)
			control = try values.decodeIfPresent(Control.self, forKey: .control)
			knobAngle = try values.decode(Double.self, forKey: .knobAngle)
			togglePosition = try values.decode(TogglePosition.self, forKey: .togglePosition)

			guard knobAngle.isFinite, (-150...150).contains(knobAngle) else {
				throw ModelError.invalidArgument("A panel knob angle must be between -150 and 150 degrees.")
			}
		}
	}

	public let size: Size

	/// Row-major slots with a stride of eight, even for a four-column panel.
	public let cells: [Cell]
	public var modules: Int { size.columns / 4 }

	private enum CodingKeys: String, CodingKey { case version, size, cells }

	public init(from decoder: Decoder) throws {
		let values = try decoder.container(keyedBy: CodingKeys.self)
		let version = try values.decode(Int.self, forKey: .version)
		guard version == 1 else {
			throw ModelError.invalidArgument("Unsupported Panels file version \(version); expected version 1.")
		}

		size = try values.decode(Size.self, forKey: .size)
		cells = try values.decode([Cell].self, forKey: .cells)
		guard cells.count == 48 else {
			throw ModelError.invalidArgument(
				"A Panels file must contain 48 stored cell slots; found \(cells.count)."
			)
		}
	}

	public static func decode(_ data: Data) throws -> PanelLayout {
		do {
			return try JSONDecoder().decode(Self.self, from: data)
		} catch let error as DecodingError {
			throw ModelError.invalidArgument("Invalid Panels document: \(error)")
		}
	}

	public init(contentsOf url: URL) throws {
		self = try Self.decode(Data(contentsOf: url))
	}

	/// Convert Panels' top-to-bottom rows to Mill's centered, Y-up coordinates.
	func models(_ make: (Cell) -> Model?) -> Model {
		sum((0..<6).flatMap { row in
			(0..<size.columns).compactMap { column in
				make(cells[row * 8 + column]).map(mov(
					(Double(column) - Double(size.columns - 1) / 2) * inch,
					(2.5 - Double(row)) * inch
				))
			}
		})
	}

	func cutouts(_ depth: Double) -> Model { models { $0.control?.cutout(depth) } }

	func controls() -> Model {
		models { cell in
			guard let control = cell.control else { return nil }

			switch control {
			case .lemo1B302: return lemoECG1B302()
			case .lemo1B303: return lemoECG1B303()
			case .lemo1B304: return lemoECG1B304()
			case .pomona1581: return pomona1581()
			// Mill's true toggle position points toward negative Y.
			case .nkkMN12: return toggle(cell.togglePosition == .down, nutAngle: 0)
			case .nkkMBNF15: return pushbutton(nutAngle: 0)
			case .vccCLB300: return clb300()
			// Panels measures knob angles clockwise from twelve o'clock.
			case .bourns51: return bourns51(-cell.knobAngle, nutAngle: 0)
			}
		}
	}

	func knobs() -> Model {
		models { cell in
			cell.control == .bourns51 ? knobV30(-cell.knobAngle) : nil
		}
	}
}
