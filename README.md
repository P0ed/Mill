# Mill

A Swift port of [`../DIY`](../DIY)'s CadQuery enclosure project, built on
[OCCTSwift 3.0.0](https://github.com/SecondMouseAU/OCCTSwift/tree/v3.0.0).
Includes the AGC case, connector and control models, V30 and tower knobs,
ISO/UTS thread ridges, and STL, STEP, and three-view SVG export.

Requires Swift 6.1+ and an Apple Silicon Mac running macOS 12+.
SwiftPM downloads OCCTSwift's prebuilt OCCT kernel on the first build.

```sh
swift build
swift run mill --output output
swift run mill --modules 1,2,3 --output output
swift test
```

The default is the 2-module layout from DIY's `main.py`, with the same
potentiometer/toggle patterns and alternating knob styles. Dimensions are in
millimeters; public rotation helpers take degrees. Hardware orientations are
random by default, as in DIY. Use `--angle 0` for repeatable output.

```sh
swift run mill --modules 2 --angle 0 --threads --output output
swift run mill --modules 1 --case-only --no-svg --output output
swift run mill --help
```

Each module count produces:

| File | Contents |
| --- | --- |
| `STL/AGC-2M-01.stl`, `STEP/AGC-2M-01.step`, `SVG/AGC-2M-01.svg` | Bottom |
| `STL/AGC-2M-10.stl`, `STEP/AGC-2M-10.step`, `SVG/AGC-2M-10.svg` | Top |
| `STL/AGC-2M-11.stl` | Assembled case |
| `STL/AGC-2M-11P.stl` | Case with controls and knobs |
| `STL/KNOB-V30.stl`, `STL/KNOB-T.stl` | Knobs in the original export orientation |
| `SVG/AGC-01T.svg` with `--threads` | M4 thread section of the first case |

`2M` changes to the requested module count. `--case-only` omits hardware and
knob exports. `--hidden` includes hidden edges in SVG drawings.
As in DIY, `--threads` adds a section illustration; the case's mounting holes
remain tap-drilled. The port is a library and headless CLI; view the exported
files in a CAD viewer instead of Python's `ocp_vscode.show`.

## Composition

The generic `•` operator replaces `com` and composes right to left:

```swift
import Mill

let transform = rotz(90) • mov(10, 0, 0)
let part = transform(box(2, 4, 6)) // translate first, then rotate
let mountingHoles = (mirror(.xz, .yz) • mov(40, 60))(cylinder(15, 2.1))
let plate = box(100, 140, 3) - mountingHoles
try export("plate", plate)
```

`+` unions, `-` subtracts, and `*` intersects models. `mirror` unions reflected
copies. Boxes and cylinders are centered; cones and extrusions start at Z=0.
Modeling is eager, with failures propagated through `Model`; accessing
`try model.shape` or exporting throws the first failure. Empty patterns produce
an empty model, which can be combined with other models.

```swift
let parts = try agc(
    modules: 2,
    potsPattern: { _ in und(ptnBotM, ptnX) },
    togglesPattern: { _ in und(ptnBotM, ptnD) },
    knobs: { _ in knobTower },
    controlAngle: 0
)
try export("custom-top", parts.top)
let ridge = thread("M4", length: 10, location: .internal)
```

## Source mapping

| DIY | Mill |
| --- | --- |
| `lib/tools.py` | `Composition.swift`, `Patterns.swift` |
| `lib/ddd.py` | `Model.swift`, `Geometry.swift`, `Controls.swift` |
| `lib/thread.py` | `Thread.swift` |
| `lib/export.py` | `Export.swift` |
| `agc.py` | `AGC.swift` |
| `main.py` | `Sources/MillCLI/main.swift` |

Swift APIs use camelCase (`ptnBotM`, `ptnsMap`, `threeView`). `AGCParts` names
the original positional results. `defaultAGC` applies `main.py`'s patterns;
`agc` retains `agc.py`'s defaults. The original `grid` has 3×6 cells and `grid4`
has 4×6 cells. Thread curves retain the original dimensions, clearance and
taper equations, using OCCTSwift spline interpolation and sewn ruled surfaces.
SVGs use OCCT hidden-line removal with vector polylines at 0.02 mm deflection.
The squircle helper uses the exact fifth-power diagonal instead of DIY's
rounded sample boundary, removing tiny self-intersections at its mirrored seams.

Tests cover composition order, centered primitives, edge selection, patterns,
hardware, threads, 1M/2M/3M enclosures, and export round trips. Geometry bounds
and volumes are checked against measured Python reference fixtures. The 2M
STEP parts also matched the originals with zero symmetric-difference volume
when reimported into CadQuery.

OCCTSwift and its bundled OCCT kernel carry their upstream LGPL license terms;
see the dependency's license and OCCT exception when distributing binaries.
