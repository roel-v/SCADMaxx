# Model construction and BOSL2

For a new design, establish [interfaces, datums and construction choices](design-reasoning.md) before
choosing library calls. For source edits, retain the original intent and baseline as described in
[task routing](task-routing.md#source-editing). Select comparable views with [visual verification](visual-verification.md).

## Establish the library

Resolve the intended executable explicitly. On Windows use its actual console launcher for CLI exit status
and diagnostics: `scadmaxx.com` for a SCADMaxx delivery, or `openscad.com` for an OpenSCAD delivery.
Inspect `--version` and `--info`; inspect the application's configured library paths as needed. A library
present for another OpenSCAD installation is not proof that this process can load it.

Look for `BOSL2/std.scad` on the effective include path and read that installation's `version.scad` and
relevant `.scad` API documentation. Existing names such as `BOSL2-master` do not resolve an include of
`<BOSL2/std.scad>` automatically. Preserve the existing directory; use an explicitly documented include
name or install a separate canonical `BOSL2` directory.

If missing, install from [official BOSL2](https://github.com/BelfrySCAD/BOSL2). A project-local library is
convenient for reproducibility. In PowerShell, after selecting a new, nonexisting destination:

```powershell
$libraryParent = Join-Path $projectRoot 'libraries'
$boslDestination = Join-Path $libraryParent 'BOSL2'
New-Item -ItemType Directory -Force -Path $libraryParent | Out-Null
if (Test-Path -LiteralPath $boslDestination) { throw 'Inspect the existing library before changing it.' }
git clone --depth 1 https://github.com/BelfrySCAD/BOSL2.git $boslDestination
if ($LASTEXITCODE -ne 0) { throw 'BOSL2 installation failed.' }
git -C $boslDestination rev-parse HEAD
$env:OPENSCADPATH = $libraryParent + [IO.Path]::PathSeparator + $env:OPENSCADPATH
```

Record the commit (or archive version and checksum). Do not replace/update an existing checkout implicitly.
The process-local path affects child CLI launches; an already running GUI needs its own effective path or
a standard user library installation. On Unix the path separator is `:`; Windows uses `;`.

Compile this probe to a fresh STL with the target executable and inspect diagnostics:

```scad
include <BOSL2/std.scad>
cuboid([10, 8, 4], chamfer=0.5);
```

An include warning can coexist with an output file: check for unknown modules, warnings and empty geometry.
If network or filesystem access prevents installation, report that exact failure. Do not silently abandon
BOSL2 or request confirmation merely because it is absent.

## Build an editable model

Use millimeters by convention, state any different units, and separate user dimensions from derived values.
Use modules for functional parts and assemblies, clear anchors for placement and a small Boolean overlap
epsilon for through-cuts. Do not use epsilon to conceal a wrong fit or change nominal dimensions.
Use BOSL2 attachment helpers where they make placement explicit; check child/attachment semantics before
mixing tagged attachments with native `difference()`.

Start with [parametric-plate.scad](../assets/parametric-plate.scad). Set `finish=false` to inspect the base
form, then `finish=true` and choose rounding or chamfering. It uses a BOSL2 cuboid and through-holes, retains
the outer envelope, and rejects edge sizes that would compromise the specified hole clearance.
Keep functional bores, mating surfaces and assembly clearances independent of cosmetic treatment sizes.

Inspect useful orthographic views and one oblique view before refining. Continue through both passes when
the shape is clear. If an actual unresolved design choice needs user input, preserve the current model.
