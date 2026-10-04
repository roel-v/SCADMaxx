# Render, inspect and deliver

Choose evidence using [inspection](inspection.md): source validity, geometry validity and intent validity
are separate checks. Use [visual verification](visual-verification.md) for camera matching and affected-interface
coverage. Export is a completion step within the selected task workflow, not a separate operating mode.

Use the chosen executable's `--help` for supported flags and formats. On Windows select the delivered console
launcher (`scadmaxx.com` or `openscad.com`) for output and completion; a detached GUI launch is not a completed render check.
Keep outputs in a new task directory and record parameter overrides, backend and library revision.

PowerShell example, with `$openscad`, `$model` and `$outputDir` set to actual selected paths:

```powershell
& $openscad --version
& $openscad -o (Join-Path $outputDir 'base.stl') -D 'finish=false' $model
if ($LASTEXITCODE -ne 0) { throw 'Base render failed' }
& $openscad -o (Join-Path $outputDir 'rounded.stl') -D 'finish=true' -D 'edge_size=2' $model
if ($LASTEXITCODE -ne 0) { throw 'Finished render failed' }
& $openscad -o (Join-Path $outputDir 'chamfered.stl') -D 'treatment="chamfer"' $model
if ($LASTEXITCODE -ne 0) { throw 'Chamfer render failed' }
```

Use a command invocation that preserves quotes in `-D` strings on the installed shell. Inspect diagnostics
even with exit code zero. Fail on parser errors, unknown modules/includes, assertion failures, empty geometry
and warnings that invalidate the result. Do not suppress warnings to obtain a clean-looking run.

For a PNG, use supported camera/projection options with `--render`, `--viewall`, `--autocenter` and a sensible
`--imgsize`. Verify options with help first; headless image export may need working graphics/Qt setup.
Inspect actual images for shape, hole placement and selected edges; a render statistic cannot substitute for
this. For live viewport evidence follow [agent workflow](agent-workflow.md) instead.

For a fabrication deliverable, load the exported mesh with a suitable mesh inspection tool. Check expected
units/envelope, nonzero positive volume, connected components as designed, watertightness and consistently
oriented faces. Inspect openings and critical dimensions separately: a watertight mesh can still contain a
blocked hole or wrong fit. Use known cross-sections/rays or direct measurement where the mating geometry matters.

For the plate example, compare the base, zero treatment, nominal rounding/chamfer and near-limit treatment.
The outer bounds should be `[-length/2,-width/2,0]` to `[length/2,width/2,thickness]`. Finishing removes material
at four outside corners while the four through-holes retain their positions and diameters. Test another
dimension set. A value at/over an asserted limit should fail clearly, never produce a quietly clamped part.
Use manufacturing tolerances, not an arbitrary blanket numerical tolerance, for the requested design.

Preview success, final render success, mesh validity and visual fidelity are separate evidence. For a
Customizer deliverable also exercise controls in the GUI; for HTTP operations verify target/revision guards.
State which checks were actually run and which remain unverified. Deliver source plus requested exports,
with library/build requirements and any dependency revision needed to reproduce them.

CLI reference: [OpenSCAD manual](https://en.wikibooks.org/wiki/OpenSCAD_User_Manual/Using_OpenSCAD_in_a_command_line_environment).
