# Inspection and evidence

Choose checks from the user's question. Keep three meanings distinct:

| Validity | Useful evidence |
| --- | --- |
| Source | Parse/dependency diagnostics, assertions and evaluated parameter values. |
| Geometry | Nonempty evaluated result, bounds, dimensions, components and available topology checks. |
| Intent | Requested shape, feature positions, interfaces, fit and parameter behavior. |

A valid source can produce an empty model. A watertight mesh can have a blocked hole. Matching bounds do not
establish matching shape. Measure geometry when a supported tool can answer the question directly; distinguish
evaluated/tessellated measurements from analytic source dimensions.

Possible questions include dimensions and volume, components, watertightness/winding, holes and cavities, wall
thickness, sections, clearances/interference, feature locations, symmetry and sensitivity to parameter changes.
Use only checks the actual installed tools expose. Numerical thickness, interference, adaptive sections and
reconstruction analyses are capability-gated; neither this reference nor a future feature plan makes them available.
Record method, units, tolerance and target geometry for a numerical claim. Do not repair a mesh implicitly to
turn invalid geometry into a measurement.

For a live application, retain read-only target/revision safeguards through [agent workflow](agent-workflow.md).
For exported meshes, follow [validation](validation.md) with a verified inspection tool. Use explicit variants to
check parameter invariants and mating geometry. Printability is one possible purpose; don't assume every model
is destined for printing or treat a topology pass as proof of fabrication readiness.

Report evidence and its limits together: executable/library revision, source/result identity where applicable,
parameters, actual views/measurements and unexecuted checks. Use [visual verification](visual-verification.md)
when a geometric question also requires visual confirmation.
