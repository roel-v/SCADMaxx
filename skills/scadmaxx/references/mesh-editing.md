# Local imported-mesh edits

Inspect the mesh before choosing an edit: units, orientation, bounds, relevant cavities, components and available
topology checks. Keep the original asset and baseline evidence. An STL surface is not an editable parametric model.

For a local change such as enlarging a through-hole, use an OpenSCAD wrapper importing the original mesh and
subtracting a correctly placed cutter when the input and supported backend permit it. Keep the cutter dimensions
and frame explicit. Ensure it opens the full intended passage without removing a nearby wall or mating surface.
Adding material likewise needs a deliberate union and verified connection; an overlapping preview is insufficient.

Retain imported regions that need no change. Do not reconstruct the whole object simply to change one hole.
Choose [parametric reconstruction](reverse-engineering.md#mesh-reconstruction) when the request requires editable
construction, broad dimensional changes or repeated variants that a wrapper cannot express well. Hybrid models
may reconstruct only a functional region and keep the rest imported.

Render with the actual target executable and inspect the exported mesh. Compare the affected hole, wall and
envelope against the baseline with matched views and measurable checks. Do not silently repair the input to make
an operation succeed. If invalid topology prevents a trustworthy result, report the concrete limitation and retain
the input for an explicitly scoped repair decision. See [validation](validation.md) for output checks.
