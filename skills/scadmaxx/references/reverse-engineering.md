# Reverse engineering from evidence

Record the input, intended editable result and evidence available. Keep observed dimensions separate from
inferred dimensions and explain what the representation cannot establish. Reconstruction quality is tied to the
user's functional and visual requirements, not a universal percentage score.

## Mesh reconstruction

Analyze before modeling. Establish units and axes from known interfaces, symmetry and measured geometry. Inspect
orthogonal or oblique sections when a verified tool supports them. Separate outer contours from holes; an overall
bounding box cannot show whether a bore is closed or a recess has the right depth.

Recognize useful primitives, profiles, repetition and filleted transitions. Name dimensions around meaningful
datums and retain their relationships. Begin with a coarse base form, then refine interfaces and supported details.
Use a hybrid reconstruction when keeping an imported region serves the request better than guessing its geometry.

Compare identical cameras and actual meshes where available. Section/feature checks may be more useful than a
global difference score. Replacing triangulated threads or noisy scan detail with semantic geometry can be deliberate;
verify the intended fit and function and identify that change. Do not optimize a surface metric at their expense.

Adaptive slicing, primitive extraction, mesh differences/IoU, thickness and interference require real tools. Verify
their installed availability and meaning before relying on them; planned SCADMaxx analysis features are not tools.
Without those tools, report the narrower evidence and uncertainty instead of inventing a numerical result.

## Image replication

Inspect all supplied references before modeling. Establish scale from a known dimension when available; without
one, choose and label an assumed scale only if the user's instructions permit it. A single photograph usually
leaves depth, occluded geometry and lens perspective uncertain. Preserve those inferred dimensions as assumptions.

For a visual approximation that permits inferred geometry, expose depth as a labeled parameter and compare the
visible form. If depth controls a required fit, wall, clearance or functional interface, resolve it before dependent
modeling. When the request leaves the acceptable approximation unclear and that decision affects the deliverable,
ask a focused question and follow the user's stopping rule. Unknown depth alone does not impose an approval gate.

Identify silhouette, proportions, interfaces, repeated features and symmetry. Build the rough form first. Match
the reference camera/projection as closely as the available evidence permits, then compare proportions and feature
locations. Refine the largest demonstrated mismatch before cosmetic detail. Multiple references can constrain
hidden regions; one matched view cannot prove them.

Keep known dimensions fixed while adjusting inferred ones. Retain a parameterized model and record uncertainty
where it matters for reproduction or fabrication. Use [visual verification](visual-verification.md) and
[inspection](inspection.md) for final evidence of the requested form and interfaces.
