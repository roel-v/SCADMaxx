# Design reasoning before syntax

Start from function: what must fit, move, carry load, align or remain accessible? Identify mating surfaces,
clearance volumes and the dimensions that govern those interfaces. Pick meaningful datums and coordinate frames
so placement refers to the interface rather than arbitrary world coordinates.

Decompose the shape into envelopes and voids. Distinguish outer silhouette, functional bores/pockets, repeated
features and separate components. Use symmetry and repetition when they express the design, with explicit
exceptions where the reference or interface differs. Do not force every object into subtraction from one solid.

Choose construction from the geometry: primitives for basic envelopes, profile extrusion for constant sections,
rotational profiles for axial parts, verified sweeps/lofts for varying sections, shells for hollow bodies and
imports for geometry worth retaining. A hybrid imported and parametric model is valid. Then select supported
OpenSCAD/BOSL2 calls from the installed revision; a conceptual operation is not proof that an API exists.

Name independent dimensions and derive dependent ones. Keep nominal sizes, fit allowances and cosmetic treatment
parameters distinct. Express invariants that protect walls, clearances and feature placement as assertions where
appropriate. Parameter sensitivity should reveal an intended relationship, not break it through fixed coordinates.

Follow [modeling](modeling.md) for base geometry first, then detail and supported [edge treatments](edge-treatments.md).
Inspect the untreated form before finishing and keep that form accessible when useful. Finish with evidence of
the requested interfaces as well as the silhouette; see [inspection](inspection.md).
