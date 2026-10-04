# SCADMaxx companion skill

The product skill is [skills/scadmaxx/SKILL.md](../skills/scadmaxx/SKILL.md). It covers modeling, BOSL2
installation and edge treatments, Customizer, capability detection, live HTTP targeting and validation.
Its references and examples travel with it; agents do not need this development workspace.
Installation guidance is inside the bundle's capability reference. No user configuration is changed by packaging.

The native Customizer specification is maintained in `doc/customizer-attributes.md` in the integrated source
checkout. Do not edit the skill's generated copy independently. Freeze controls with `Save-ControlSnapshot`
before invoking the builder in that snapshot. For an explicit attempt, use:

```powershell
& D:/openscad/runs/<run-id>/control/<stage-attempt>/experimental/scripts/Build-ScadmaxxSkill.ps1 `
  -CustomizerSourceRoot D:/openscad/wt-scadmaxx-<date> `
  -SkillRoot D:/openscad/runs/<run-id>/control/<stage-attempt>/skills/scadmaxx `
  -ControlManifestPath D:/openscad/runs/<run-id>/control/<stage-attempt>/snapshot.json `
  -WorkDirectory D:/openscad/runs/<run-id>/companions/<stage-attempt>/work `
  -OutputZip D:/openscad/runs/<run-id>/companions/<stage-attempt>/<version>-<stage-attempt>-scadmaxx-skill.zip
```

The work directory and ZIP must be new paths outside the inputs. The builder validates the frozen skill against
the snapshot manifest, rejects a modified/untracked canonical document, and changes only its staging copy.
It returns one result with `path`, `sha256`, `source_revision`, `document_sha256` and
`control_manifest_sha256`. The generated `references/bundle-source.json` contains the same provenance,
with schema version 1 and the relative canonical-document path. Authored references stay untouched.

Application Stage invokes the frozen builder before finalizing build-info and its inventory. Build-info's
`skillCompanion` records the relative delivery filename and hashes. Package verifies that exact staged ZIP,
its embedded provenance/document, the Stage snapshot and application source, then copies it alongside the
application archive with its SHA-256 file. It never regenerates from live controls or overwrites an artifact.
The source-owned HTTP skill bundle remains inside the application distribution. Missing canonical input or
changed ZIP/snapshot fails explicitly; the next real application composition must verify release correspondence.
Review the capability matrix against the intended executable; building the skill does not prove runtime support.

For verification, extract the ZIP into a fresh directory outside the control/source checkouts. Run the
skill-creator `quick_validate.py` and [Test-ScadmaxxSkill.py](../experimental/scripts/Test-ScadmaxxSkill.py)
using `uv run`. The latter takes `--skill`, `--openscad` (upstream), `--extended` (OEP8/Customizer build),
`--bosl-parent` and a new `--output` directory. Its inline dependencies are isolated Python test dependencies,
not product requirements. Configure the selected executables' Qt/runtime paths where needed.
Inspect generated base/finished PNGs as well as the mesh report. Use the feature-native suites separately
for reactive Customizer and multi-document HTTP behavior; CLI examples do not validate GUI interactions.

Evidence and remaining limits are recorded in the skill feature's post-implementation notes.
