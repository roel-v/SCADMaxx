# Choose a supported edge treatment

Read the installed BOSL2 function/module documentation before writing the call. Parameter names, edge
selection and limits vary by helper; there is no assumed operation that fillets arbitrary edges of any CSG solid.

| Geometry and intended treatment | First helper to investigate |
| --- | --- |
| Rectangular solid, selected outside edges | `cuboid()` with `rounding` or `chamfer`, `edges` and `except` |
| Circular solid's end rims | `cyl()` rounding/chamfer parameters, including per-end variants |
| Local supported cut/rounding at a known edge | BOSL2 masks such as `chamfer_edge_mask()` or `rounding_edge_mask()` |

Sources: [shapes3d](https://github.com/BelfrySCAD/BOSL2/wiki/shapes3d.scad),
[rounding](https://github.com/BelfrySCAD/BOSL2/wiki/rounding.scad),
[masks](https://github.com/BelfrySCAD/BOSL2/wiki/masks.scad). These are selection pointers, not promises that
every revision implements every combination. Primitive edge selectors describe that primitive's edges,
not newly created Boolean intersections. Rounding a 2D outline rounds its extruded side corners, not its end rims.

Use the solid primitive's own edge-treatment parameters or a suitable documented mask. A specialized mask
requires correct orientation, attachment and Boolean subtraction; inspect both ends and junctions.

Do not use either of these workarounds to manufacture chamfers or fillets:

- Manually constructed rings, profiles or vertex meshes lofted with `skin()`.
- A rounded/chamfered 2D outline followed by further rounded/chamfered extrusion ends: for example,
  `round_corners()` followed by `offset_sweep()` with bottom/top end treatments. Equivalent offset/profile
  stacks or custom extrusion sequences are covered too; changing helper names does not avoid the restriction.

These are user-imposed modeling constraints, not claims that the BOSL2 functions are defective. They apply
even when the workaround calls official BOSL2 helpers or starts with a naturally profile-based part.
Ordinary 2D outline design and legitimate lofted bodies are not prohibited, but must not be used to disguise
these 3D edge-treatment workarounds. State which edge/helper combination is unsupported and choose a simpler
supported construction only if it still satisfies the request; otherwise report the remaining limitation.

## Preserve design intent

A chamfer is flat; a fillet/roundover is curved. State whether a dimension is a radius, perpendicular setback,
face width or helper-specific cut/joint measure. They are not interchangeable. For a 45-degree chamfer,
face width differs from its perpendicular setback by a factor of square root of two.

Select convex and concave edges deliberately. Check short segments, neighboring holes, intersecting blends
and local wall thickness before increasing radii. Do not clamp an invalid user value silently. Use assertions
for known geometric limits and explain failures. Boolean order matters: rounding a blank before drilling
leaves bore rims sharp, whereas a treatment after cutting may affect different surfaces.

Local treatments usually cost less than whole-solid Minkowski sums. Use native offsets, hulls or Minkowski
only for a demonstrated construction advantage or verified library limitation, with explicit envelope and
performance checks. Whole-solid rounding can grow the envelope and alter holes. Increasing `$fn` cannot fix
invalid geometry; use modest preview tessellation and sufficient final tessellation for the intended scale.
For printing, assess supported overhangs in the intended orientation, minimum walls and fit tolerances.

## Exercise zero and limiting cases

The [plate example](../assets/parametric-plate.scad) treats only vertical edges (`edges="Z"`). Its exact design
domain is `0 <= edge_size < min(length,width)/2` and `edge_size < hole_inset-hole_diameter/2`; these are
conservative constraints for this model, not universal BOSL2 limits. Zero explicitly uses the untreated
primitive. Test just below a permitted limit and at a rejected value, as well as nominal dimensions.
Compare untreated, chamfered and rounded exports: envelope, positive volume, watertightness, holes and
clearances. See [validation](validation.md). Smooth-looking preview alone is insufficient.
