# Windows experimental build tools

For repeatable documentation images, see [the native README capture harness](../../docs/readme-capture-tool.md)
and `Capture-Readme.ps1`. It uses a separate test-enabled checkout and preserves published build artifacts.

Run with PowerShell 7.2 or newer. These scripts never push, publish, tag a release, or modify the enabled selection.
The first real Windows run passed automated build, staging and extracted-ZIP checks; see the profile and run report
for the remaining Windows desktop and clean-machine verification limits.

## Prepare a fresh run

First inventory all local source/control branches, report unpushed work, reconcile controls and check promoted
inputs in [the update/build runbook](../../workflows/update-and-build-scadmaxx.md).
The preparation script reads the declared repositories; it does not push newer feature-worktree commits to their
bare origins, pull/rebase development checkouts, or switch a local source to GitHub automatically.
The agent must perform and save this inventory; `-ValidateOnly` validates selection metadata, not push status.
After preparation, show the user the exact `inputs.json` composition and excluded local commits/dirty work before
running integration or build commands. The preparation script does not replace this user-facing report.

New integration branches/worktrees must follow the
[SCADMaxx naming rule](../../docs/git-layout.md#integration-branch-and-worktree-names):
`scadmaxx-YYYYMMDD` / `wt-scadmaxx-YYYYMMDD`, using their creation date.
The script selects the creation date in Europe/Amsterdam and adds `-2`, `-3`, etc. for same-day collisions.
Run commands below from `D:/openscad/scadmaxx`. `-ControlRoot` defaults to this control repository;
`-Workspace` defaults to its parent container holding `openscad-master`, worktrees, runs and artifacts.
For migrated runs, follow [the migration notes](../../docs/layout-migration.md); their frozen inputs keep old paths.

```powershell
pwsh -NoProfile -File experimental/scripts/New-ExperimentalRun.ps1
```

This reads the enabled table, locks master/source/base commits, retains refs and patches, and creates an isolated
worktree. It does not apply patches blindly. Resume an existing run from its `inputs.json`; do not prepare it again.
Preparation failures retain their inputs and logs. Check the actual refs/worktree before manually resuming.
Use `-ValidateOnly` to inspect the selection and source definitions without fetching or creating a run/worktree.

Selected unfinished features use `ready: false` plus `pendingReason` in `SOURCES.json`. Validation reports them;
actual preparation stops before fetching or creating a run. Only mark a new source ready after an explicitly
user-requested promotion has made its validated revision available in the declared repository and its change
boundaries/dependencies are reviewed. A commit or build request does not authorize a push.

For a `feature` or `pr-variant`, the Source column names a definition in `experimental/SOURCES.json`.
An explicitly requested alternate file can be passed with `-SourceDefinitions <json-file>`.
For example (not selected by this example):

```json
{
  "local-annotations": {
    "repository": "E:/Dropbox/bare_repos/openscad.git",
    "ref": "refs/heads/feature/annotations"
  }
}
```

Variants also require `prUrl`. The named definition must agree with the source declared in the selection list.
Dependency and partially-upstream changes still require the agent review described in the input contract.

## Configure, build, test, stage, package

SCADMaxx enables `ENABLE_NAVIGATION_CUBE_TUNING` when the frozen selection includes
`navigation-cube`. Open **Window > Navigation tuning** for its session-only controls.
The window starts hidden. This flag is recorded in the build fingerprint; when enabling it
for an existing run, use a fresh application build directory and reuse the shared vcpkg tree.
SCADMaxx also explicitly enables `EXPERIMENTAL=ON` and `USE_MANIFOLD_MINKOWSKI=ON`.
These are recorded in the same fingerprint and package metadata. Individual experimental
features remain runtime opt-ins. Other optional feature flags retain their existing defaults.

When reconfiguring an existing **validation** tree from tuning OFF to ON, Qt AUTOMOC may
retain an old `mocs_compilation.cpp`, causing unresolved `NavigationTuning::staticMetaObject`
and related linker symbols. Verify that `AutogenInfo.json` lists `NavigationTuning.h` but
`OpenSCADLibInternal_autogen/mocs_compilation.cpp` lacks `moc_NavigationTuning.cpp`.
Run `cmake -E cmake_autogen <build>/CMakeFiles/OpenSCADLibInternal_autogen.dir/AutogenInfo.json Release`,
then rebuild. This repaired the 2026-10-02 validation tree on its first focused attempt;
the fresh delivery tree generated the file correctly without intervention. No source patch
or dependency rebuild is needed for this stale generated-file case.

Apply the [Windows executable naming support](../repairs/windows-executable-name.md) before using
this profile. It configures `OPENSCAD_WINDOWS_OUTPUT_NAME=scadmaxx`, producing `scadmaxx.exe`
and `scadmaxx.com` directly at the build root. CTest uses that console launcher; no copying or
post-build renaming is required. The name participates in the fingerprint. Staging and extracted-ZIP
smoke checks reject old executable names and verify both new launchers.

Compile-time feature audit for the 2026-10-01 integration source (`bcf48145d`), with current
SCADMaxx recipe settings. Attempt-5 includes experimental features and Manifold Minkowski;
the older attempt-4 ZIP predates those two settings.

| Switch | Windows recipe setting | Effect |
| --- | --- | --- |
| `ENABLE_NAVIGATION_CUBE_TUNING` | ON when navigation cube is selected | Session-only tuning dock under Window. |
| `EXPERIMENTAL` | ON | Gates runtime experimental preferences: roof, lazy unions, renderer indexing, text/font metrics, data import function, object function, predictable output, vector swizzling, `$fe` error-based segmentation, unfinished AI interface, Unicode identifiers, DBus input. Enabling the build flag makes these available; individual features still need enabling. |
| `ENABLE_PYTHON` | OFF | Embedded experimental Python interpreter; independent of the external HTTP/annotations Python clients. |
| `USE_MANIFOLD_MINKOWSKI` | ON | Enables the Manifold Minkowski implementation. |
| `ENABLE_CGAL`, `ENABLE_MANIFOLD` | ON | Both geometry backends are available. |
| `USE_MANIFOLD_TRIANGULATOR` | ON | Uses Manifold triangulation. |
| `USE_POLYSET_FOR_CGAL` | OFF | Alternative rendering path for CGAL results. |
| `ENABLE_HIDAPI`, `ENABLE_SPNAV` | AUTO, dependencies not found | Optional 3D input-device drivers are absent. Qt5 gamepad is unavailable with Qt6; Linux joystick code is platform-specific. |
| `OFFLINE_DOCS` | OFF | Bundled offline documentation. |
| `ENABLE_GUI_TESTS` | OFF in delivery | Automated GUI harness; ON only in the separate validation build. |

`ENABLE_TESTS` builds the separate unit-test executable. Other switches cover headless/OpenGL
platforms, snapshot branding, memory allocation, profiling and dependency/build tooling.
Annotations, the HTTP agent server, keyboard shortcuts and dark-mode integration have no
additional opt-in compile switch in this GUI build. Re-audit when changing the frozen sources.

Create a machine profile from `../profiles/windows-x64.example.json`. Save local tool paths in a `*.local.json`
file, which control Git ignores. Set exact installed MSVC/SDK versions, the vcpkg toolchain commit and
`vcpkgInstalled` to the existing shared package tree. On this machine that is
`D:/openscad/openscad-6991/build/vcpkg_installed`, using the toolchain in `D:/vcpkg`.
Manifest mode and automatic installation are disabled; missing dependencies are reported without installing or
rebuilding them. Catch2 and Boost.Nowide were added to the shared tree at the user's request on 2026-10-01;
the full-test profile checks that both are present.
The script adds the shared `tools/gettext/bin` and `bin` directories to PATH for the
translation post-build step. A `msgfmt: command not found` failure after linking requires
this existing tool path, not a dependency rebuild; rerun Build after correcting PATH.
Each build attempt
copies this profile and the consumed controls into its evidence, so local configuration is not lost.

```powershell
$buildArgs = @{
    Source = 'D:/openscad/wt-scadmaxx-YYYYMMDD' # Actual recorded path, including any same-day numeric suffix
    Build = 'D:/openscad/runs/<run-id>/baseline-build'
    Run = 'D:/openscad/runs/<run-id>'
    BuildProfile = 'D:/openscad/scadmaxx/experimental/profiles/this-machine.local.json'
    Jobs = 4
}
./experimental/scripts/Build-Windows.ps1 @buildArgs -Step Configure
./experimental/scripts/Build-Windows.ps1 @buildArgs -Step Build
./experimental/scripts/Build-Windows.ps1 @buildArgs -Step Test
```

Keep the baseline result. Review/apply the first locked patch, commit its integration, and repeat Configure/Build/
Test using a separate `integration-build` directory. Continue one entry at a time, recording repair commits and
focused behavior checks. Reconfigure for every new source commit. Incompatible profile/dependency changes require
a new application build directory; both directories still use the same shared dependencies. No script removes or
cleans an old one. Old private-dependency runs and artifacts remain historical evidence.

Before staging, write `integrations.json` as an array of records with `id`, `sourceHead`, `outcome` (`integrated` or
`already-present`), `commit` (passing checkpoint), and `verificationLog` (a passing `logs/*-test.json` record for that
exact commit, relative to the run). Record conflicts,
repairs, attribution, and behavior evidence in the run report. Every selected entry needs evidence, even if already
upstream. Record verification and limitations in the run report. Do not create or bundle release notes. Then:

```powershell
$buildArgs.Build = 'D:/openscad/runs/<run-id>/integration-build'
$staging = 'D:/openscad/artifacts/<run-id>/attempt-1/staging'
./experimental/scripts/Build-Windows.ps1 @buildArgs -Step Stage -Staging $staging
./experimental/scripts/Build-Windows.ps1 @buildArgs -Step Package -Staging $staging
```

Stage installs upstream resources, copies the locked Release DLL set and Qt plugins with an app-local `qt.conf`,
checks runtime dependencies, and copies license notices. It does not require Qt's optional `windeployqt` tool.
The runtime bundle deliberately includes the installed Release libraries, including indirect plugin dependencies.
Package verifies staging has not changed, archives its contents directly at the ZIP root, checks the ZIP,
and exports matching source including submodules. After extraction, run `scadmaxx.exe` directly in the
extraction directory; `staging` is only an internal build directory. See the [packaging contract](../../workflows/experimental-builds.md#package-and-verify).
Both perform CLI geometry/PNG checks with a controlled PATH and reject error diagnostics even with exit code zero.
The Test step requires the Catch2 unit test binary, supplies the locked Qt plugins, and installs a separate test
bundle so rendering exercises the actual shaders and resources.
These automated checks do not claim GUI interactions, selected feature behavior, or clean-machine portability.
Complete those checks in the run report before marking the profile/release verified or creating its success tag.

For a failed staging attempt, use a new staging path; for a failed Package attempt, preserve its outputs and use a
new attempt directory. Final verification evidence and profile/dependency metadata must accompany source delivery.

## Tool checks

```powershell
pwsh -NoProfile -File experimental/scripts/Test-BuildTools.ps1
pwsh -NoProfile -File experimental/scripts/Test-SharedVcpkg.ps1 -BuildProfile experimental/profiles/this-machine.local.json
pwsh -NoProfile -File experimental/scripts/Test-RuntimeDeployment.ps1 -BuildProfile experimental/profiles/this-machine.local.json
pwsh -NoProfile -File experimental/scripts/Test-QtDeployment.ps1 -BuildProfile experimental/profiles/this-machine.local.json -DependencyPrefix <shared-installed-tree>/x64-windows
pwsh -NoProfile -File experimental/scripts/Test-ShortcutFeature.ps1 -BuildProfile experimental/profiles/this-machine.local.json -Source <checkout> -DependencyPrefix <shared-installed-tree>/x64-windows
```

Checks path containment, output capture, nonzero native exit codes, hashes, changed staging content, invalid run IDs,
preservation of existing runs, and refusal to stage real changes while refreshing Clipper's generated-header metadata.
The shared-vcpkg check configures a small fixture with the real toolchain, confirms shared library discovery even
with an unresolvable source manifest, checks stable dependency fingerprints across fresh PowerShell processes,
and checks missing-tree rejection without installing or compiling packages.
The runtime check compiles a small fixture, verifies DLL copying and execution,
and requires a missing DLL to be reported as an error. This is separate from OpenSCAD distribution verification.
The Qt fixture checks the same runtime-copy helper used by Stage: it must load the Windows platform plugin from
its staged folder and render an image with a controlled PATH. It does not display or interact with a user window.
The shortcut probe compiles the selected checkout's widget, redirects only its configuration path into a temporary
directory, and tests key assignment/invocation, existing-window consistency, persisted settings reload, collision
rejection, and defaults. It uses Qt's offscreen platform; Windows desktop interaction still needs separate evidence.
