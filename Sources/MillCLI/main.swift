import Foundation
import Mill

struct Options {
	var modules = [2]
	var output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
	var threads = false
	var controls = true
	var svg = true
	var hidden = false
	var angle: Double?
	var panel: URL?

	static let help = """
	Usage: mill [FILE.panel] [options]
	  --panel PATH      Build from a Panels document (also accepted as FILE.panel)
	  --modules 1,2,3   Module counts to generate (default: 2)
	  --output PATH     Output directory (default: current directory)
	  --threads         Export the M4 thread section drawing, AGC-01T.svg
	  --case-only       Skip populated assembly and separate knob STLs
	  --no-svg          Skip SVG drawings
	  --hidden          Include hidden edges in drawings
	  --angle DEGREES   Fixed control/nut/knob orientation (default: random)
	  --help            Show this help

	Writes STL/, STEP/, and SVG/ subdirectories using DIY's filenames.
	Panel input determines the case size and control layout; cannot be combined with --modules.
	Saved knob angles and toggle positions are used for panel input; --angle overrides knob/nut angles.
	"""

	init(_ arguments: [String]) throws {
		var i = 0
		var hasModules = false

		func setPanel(_ path: String) throws {
			guard panel == nil else { throw ModelError.invalidArgument("Pass only one .panel file.") }
			let url = URL(fileURLWithPath: path)
			guard url.pathExtension.lowercased() == "panel" else {
				throw ModelError.invalidArgument("Panel input must be a .panel file.")
			}
			panel = url
		}

		func value(_ flag: String) throws -> String {
			i += 1
			guard i < arguments.count else { throw ModelError.invalidArgument("Missing value for \(flag).") }
			return arguments[i]
		}

		while i < arguments.count {
			let flag = arguments[i]
			switch flag {
			case "--modules":
				hasModules = true
				let text = try value(flag)
				let values = text.split(separator: ",", omittingEmptySubsequences: false)
				let parsed = values.compactMap { Int($0) }
				guard !parsed.isEmpty, parsed.count == values.count, parsed.allSatisfy({ $0 > 0 }) else {
					throw ModelError.invalidArgument("--modules requires comma-separated positive integers.")
				}
				var seen = Set<Int>()
				modules = parsed.filter { seen.insert($0).inserted }

			case "--panel": try setPanel(value(flag))
			case "--output": output = URL(fileURLWithPath: try value(flag), isDirectory: true)
			case "--threads": threads = true
			case "--case-only": controls = false
			case "--no-svg": svg = false
			case "--hidden": hidden = true

			case "--angle":
				guard let number = Double(try value(flag)), number.isFinite else {
					throw ModelError.invalidArgument("--angle requires a finite number of degrees.")
				}
				angle = number

			default:
				if !flag.hasPrefix("-") {
					try setPanel(flag)
				} else {
					throw ModelError.invalidArgument("Unknown option: \(flag). Use --help for usage.")
				}
			}
			i += 1
		}

		guard panel == nil || !hasModules else {
			throw ModelError.invalidArgument(
				"Panel input cannot be combined with --modules; the panel determines the case size."
			)
		}
	}
}

func run(_ options: Options) throws {
	let panel = try options.panel.map { try PanelLayout(contentsOf: $0) }
	let moduleCounts = panel.map { [$0.modules] } ?? options.modules

	for (index, modules) in moduleCounts.enumerated() {
		print("Building AGC-\(modules)M…")
		let parts: AGCParts
		if let panel {
			parts = try agc(
				panel: panel,
				threads: options.threads,
				includeControls: options.controls,
				controlAngle: options.angle
			)
		} else {
			parts = try defaultAGC(
				modules: modules,
				threads: options.threads && index == 0,
				includeControls: options.controls,
				controlAngle: options.angle
			)
		}

		let name = "AGC-\(modules)M"
		for (suffix, model) in [("01", parts.bottom), ("10", parts.top)] {
			print("Exporting \(name)-\(suffix)…")
			try export(
				"\(name)-\(suffix)",
				model,
				to: options.output,
				svg: options.svg,
				hidden: options.hidden
			)
		}

		print("Exporting \(name)-11…")
		try export("\(name)-11", parts.enclosure, to: options.output, svg: false, step: false)

		if options.controls {
			print("Exporting \(name)-11P…")
			try export("\(name)-11P", parts.populated, to: options.output, svg: false, step: false)
		}

		if options.svg, let section = parts.threadSection {
			try export(
				"AGC-01T",
				section,
				to: options.output,
				stl: false,
				step: false,
				hidden: options.hidden
			)
		}
	}

	if options.controls {
		try export("KNOB-V30", rotx(-90)(knobV30(0)), to: options.output, svg: false, step: false)
		try export("KNOB-T", rotx(-90)(knobTower(0)), to: options.output, svg: false, step: false)
	}

	print("Exported to \(options.output.path)")
}

do {
	let args = Array(CommandLine.arguments.dropFirst())
	if args.contains("--help") || args.contains("-h") {
		print(Options.help)
	} else {
		try run(Options(args))
	}
} catch {
	FileHandle.standardError.write(Data("mill: \(error.localizedDescription)\n".utf8))
	exit(1)
}
