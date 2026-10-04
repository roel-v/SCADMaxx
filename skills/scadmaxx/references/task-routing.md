# Task routing

Choose the task intent independently of the surface and evidence. A reconstruction can use a verified CLI;
a source edit can use a guarded live application. Refinement is the inspect/change/render/compare loop in
each task. Export completes the requested deliverable.

| Intent | Decision and reference |
| --- | --- |
| Create | Define functional interfaces and parameters with [design reasoning](design-reasoning.md), then [modeling](modeling.md). |
| Source-edit | Preserve existing design intent and text; follow the source-editing guidance below. |
| Mesh-edit | Use local imported-mesh CSG where viable; read [mesh editing](mesh-editing.md). |
| Reconstruct | Build editable parameters from mesh evidence; read [reverse engineering](reverse-engineering.md#mesh-reconstruction). |
| Image-replicate | Establish scale, uncertainty and reference camera; read [reverse engineering](reverse-engineering.md#image-replication). |
| Inspect | Choose questions and measurable evidence with [inspection](inspection.md). |

For live operation, follow [agent workflow](agent-workflow.md) and retain server/document/source/result/viewport
guards. For CLI operation, verify the exact executable and library revision through [capabilities](capabilities.md)
and [validation](validation.md). HTTP access is a control/observation surface, not a task intent.

Select evidence that answers the request: a preview can test proportions, validated geometry supports numerical
claims, and a fabrication output needs its own interface and manufacturing checks. Do not label preview evidence
as a validated mesh or print-ready output. Read [visual verification](visual-verification.md) for comparisons.

Choose interaction policy from the user's instructions. Make reversible assumptions only where permitted and
record them. Requirements-driven work resolves consequential ambiguities before dependent edits. If a question
requires a stop, end the turn; neither a timeout nor silence provides an answer. No workflow creates an extra
approval gate when the user has already authorized the work.

## Source editing

Capture the original source and relevant baseline views/measurements. Identify which parameter, module or
instance owns the change. Preserve expressions, comments, whitespace and untouched source instead of rebuilding
the file from an AST or substituting an evaluated snapshot for a formula.

Use the live buffer for an open document. Follow existing dirty-buffer protections and actual supported editing
capabilities; this bundle does not promise a transaction endpoint. Capture the intended document explicitly and
recheck revisions before mutation. A switched tab or stale result must not redirect the edit.

Change the smallest source region that expresses the user's intent. Render the changed parameters and inspect
the affected interfaces with the original camera. Retain unrelated geometry and compare it where tools permit.
Use ordinary undo/save behavior; a successful edit does not imply a disk save. Explain an expression or ambiguous
instance that cannot be edited safely rather than guessing a replacement.
