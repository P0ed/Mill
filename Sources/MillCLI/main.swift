import Foundation
import Mill

struct Options {
	let panel: URL
	var output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
	var threads = false
	var controls = true
	var svg = true
	var hidden = false

	static let help = """
	Usage: mill FILE.panel [options]
	  --panel PATH      Specify the required Panels document instead of FILE.panel
	  --output PATH     Output directory (default: current directory)
	  --threads         Export the M4 thread section drawing, AGC-01T.svg
	  --case-only       Skip populated assembly and separate hardware STLs
	  --no-svg          Skip SVG drawings
	  --hidden          Include hidden edges in drawings
	  --help            Show this help

	Writes STL/, STEP/, and SVG/ subdirectories using DIY's filenames.
	A .panel file is required and determines the case size, controls, knob angles, and toggle positions.
	"""

	init(_ arguments: [String]) throws {
		var i = 0
		var panelURL: URL?

		func setPanel(_ path: String) throws {
			guard panelURL == nil else { throw ModelError.invalidArgument("Pass only one .panel file.") }
			let url = URL(fileURLWithPath: path)
			guard url.pathExtension.lowercased() == "panel" else {
				throw ModelError.invalidArgument("Panel input must be a .panel file.")
			}
			panelURL = url
		}

		func value(_ flag: String) throws -> String {
			i += 1
			guard i < arguments.count else { throw ModelError.invalidArgument("Missing value for \(flag).") }
			return arguments[i]
		}

		while i < arguments.count {
			let flag = arguments[i]
			switch flag {
			case "--panel": try setPanel(value(flag))
			case "--output": output = URL(fileURLWithPath: try value(flag), isDirectory: true)
			case "--threads": threads = true
			case "--case-only": controls = false
			case "--no-svg": svg = false
			case "--hidden": hidden = true

			default:
				if !flag.hasPrefix("-") {
					try setPanel(flag)
				} else {
					throw ModelError.invalidArgument("Unknown option: \(flag). Use --help for usage.")
				}
			}
			i += 1
		}

		guard let panelURL else {
			throw ModelError.invalidArgument("A .panel file is required. Use mill FILE.panel [options].")
		}
		panel = panelURL
	}
}

func run(_ options: Options) throws {
	let panel = try PanelLayout(contentsOf: options.panel)
	let name = "AGC-\(panel.modules)M"

	print("Building \(name)…")
	let parts = try agc(panel: panel, threads: options.threads, includeControls: options.controls)

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
		try export("\(name)-11P", parts.populated, to: options.output, svg: false, step: false, deflection: 0.05)
		try export("KNOB-V30", rotx(-90)(knobV30(0)), to: options.output, svg: false, step: false)
		try export("BOLT-M4X14-TORX", boltM4x14(), to: options.output, svg: false, step: false, deflection: 0.025)
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
