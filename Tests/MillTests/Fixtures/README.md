# DIY reference geometry

`diy-metrics.json` was measured from the unmodified Python source in `../DIY`,
commit `37716f394d270c0f642d5222ae4ba18ec40c7f61`, using CadQuery 2.5.2 and
cadquery-ocp 7.7.2 on macOS arm64. Bounds are `[xmin, ymin, zmin, xmax, ymax, zmax]`
in mm and volumes are in mm³.

The reference calls use `lib.ddd.random = lambda: 0.0` for a zero-degree nut,
`toggle(True)`, `bourns51(0)`, `knobV30(0)`, `knobTower(0)`, and the default
constructors for other hardware. Threads are `thread('M4', 3, location)` with
48 segments per turn. Enclosures use `main.py`'s patterns for module counts 1–3.
Only bottom and top geometry is measured for enclosures, so display hardware
randomness does not affect these references.

The Swift tests compare volume and each bound within 0.001 mm³ / 0.001 mm.
The Python thread implementation approximates splines while the Swift port
interpolates them, so thread tolerances allow for that numerical difference.

As an additional one-time check, both generated 2M STEP parts were reimported
into CadQuery and compared against the Python parts by subtracting in both
directions. The resulting symmetric-difference volumes were 0.0 mm³.
