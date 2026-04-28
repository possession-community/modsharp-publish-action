# modsharp-publish-action

> Notice: this workflow and its scripts were generated with the help of an AI assistant (Claude). Review carefully before use and open an issue if you spot anything wrong.

Reusable GitHub Actions workflow for ModSharp plugins / shared libraries.
The `build.bat` build logic is re-implemented in bash, so a single Linux runner (`ubuntu-latest`) can produce artifacts for both Linux and Windows.

日本語版は [README_JA.md](README_JA.md) を参照。

## Table of Contents

- [What it does](#what-it-does)
- [Job layout](#job-layout)
- [Caller repo requirements](#caller-repo-requirements)
- [Quick start](#quick-start)
- [Copy-paste build job templates](#copy-paste-build-job-templates)
  - [A. Simple plugin (single platform)](#a-simple-plugin-single-platform)
  - [B. Plugin for both Linux and Windows](#b-plugin-for-both-linux-and-windows)
  - [C. Shared library + NuGet + bundled dependencies (TnmsPluginFoundation style)](#c-shared-library--nuget--bundled-dependencies-tnmspluginfoundation-style)
  - [D. Multiple csproj in one repo](#d-multiple-csproj-in-one-repo)
- [Inputs](#inputs)
- [Secrets](#secrets)
- [Managing the DLL removal list](#managing-the-dll-removal-list)
- [NuGet publishing](#nuget-publishing)
- [Artifact naming rules](#artifact-naming-rules)
- [Creating a GitHub Release](#creating-a-github-release)
- [Inside the publish job (step-by-step)](#inside-the-publish-job-step-by-step)
- [Troubleshooting](#troubleshooting)
- [Repository layout](#repository-layout)
- [Running scripts locally](#running-scripts-locally)
- [Permissions](#permissions)

## What it does

- Linux runner friendly — `dotnet publish -r` cross-compiles, so `win-x64` and `linux-x64` can both be produced from a single Linux host.
- Parallel multi-platform builds — pass `platforms: linux-x64 win-x64` and a matrix strategy runs both concurrently. Platform suffixes are appended to zip names automatically.
- Multi-csproj support — list every module / shared project as a space- or newline-separated value. No per-project configuration files needed.
- Built-in DLL removal list — the list of DLLs already shipped by the ModSharp runtime is centrally managed in this repository. Bump the tag and every caller picks it up.
- Flexible packaging — works for module-style plugins and for shared-library style projects. An optional "extended" zip can bundle downloaded dependencies alongside the main build output.
- NuGet publishing — push one or many projects in the same run, with an explicit `<PackageId>` check.

## Job layout

| job | runs when | what it does |
| --- | --- | --- |
| `setup` | always | converts the `platforms` input into a JSON array for matrix use |
| `build` | non-tag pushes, commit message does not contain `[no ci]` | CI build per platform (matrix). No artifacts are produced. |
| `publish` | tag push | full publish + zip + artifact upload, per platform (matrix) |
| `publish-nuget` | tag push and `nuget-project-dirs` is set | packs and pushes to NuGet.org. Runs once (no matrix). |

> Release creation is intentionally left out. The workflow stops at artifact upload. Add a `gh release create` job in your caller workflow if you want GitHub Releases — see [Creating a GitHub Release](#creating-a-github-release).

## Caller repo requirements

Your plugin repository should look roughly like this:

```
<caller-repo>/
├── <ProjectName>/              # one directory per csproj; directory name == csproj filename
│   ├── <ProjectName>.csproj
│   └── ...
├── gamedata/                   # optional — included in the output if present
├── config.props                # required when publishing to NuGet; must contain <Version>
└── .github/workflows/cicd.yml  # caller workflow that invokes this reusable workflow
```

Constraints:

- Every name passed to `projects` / `shared-projects-*` / `nuget-project-dirs` must have the form `<name>/<name>.csproj` (same convention as `build.bat`).
- Every csproj published to NuGet must define `<PackageId>` explicitly. The workflow fails if it is missing.

## Quick start

1. Create `.github/workflows/cicd.yml` in your plugin repo.
2. Copy the closest template from [below](#copy-paste-build-job-templates).
3. Edit `projects` / `main-artifact-name` / etc. to match your project names.
4. Push to `main` and confirm the `build` (CI) job passes.
5. Push a tag (e.g. `v1.0.0`) and confirm `publish` / `publish-nuget` run.

Triggers are defined by the caller (reusable workflows do not have their own triggers):

```yaml
on:
  push:
    branches: [main]
    tags: ['v*']
```

## Copy-paste build job templates

Each template is a complete workflow file. Replace `@v1` with whichever ref you want to pin to (`@main` is fine while iterating).

### A. Simple plugin (single platform)

```yaml
# .github/workflows/cicd.yml
name: CI/CD

on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  cicd:
    uses: possession-community/modsharp-publish-action/.github/workflows/deploy.yml@v1
    with:
      projects: MyPlugin
      main-artifact-name: MyPlugin
```

Result:

- push to `main` → `build` verifies the project compiles
- push to a `v*` tag → an artifact named `release-artifacts` is uploaded, containing `MyPlugin.zip`

### B. Plugin for both Linux and Windows

```yaml
name: CI/CD
on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  cicd:
    uses: possession-community/modsharp-publish-action/.github/workflows/deploy.yml@v1
    with:
      projects: MyPlugin
      platforms: linux-x64 win-x64
      main-artifact-name: MyPlugin
```

Result:

- `build` / `publish` run twice in parallel (linux / win)
- Artifacts:
  - `release-artifacts-linux-x64` → `MyPlugin-linux-x64.zip`
  - `release-artifacts-win-x64` → `MyPlugin-win-x64.zip`

### C. Shared library + NuGet + bundled dependencies (TnmsPluginFoundation style)

```yaml
name: CI/CD
on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  cicd:
    uses: possession-community/modsharp-publish-action/.github/workflows/deploy.yml@v1
    with:
      projects: TnmsPluginFoundation.Example
      shared-projects-phase1: TnmsPluginFoundation

      platforms: linux-x64 win-x64

      # Core (no deps) — only shared + gamedata, modules excluded
      main-artifact-name: TnmsPluginFoundation-Core
      main-artifact-include: shared gamedata

      # Full (with downloaded dependencies)
      extended-artifact-name: TnmsPluginFoundation-WithDependencies
      extended-artifact-include: shared gamedata
      dependencies: |
        https://github.com/fltuna/TnmsAdministrationPlatform/releases/latest/download/TnmsAdministrationPlatform.zip
        https://github.com/fltuna/TnmsExtendableTargeting/releases/latest/download/TnmsExtendableTargeting.zip
        https://github.com/fltuna/TnmsLocalizationPlatform/releases/latest/download/TnmsLocalizationPlatform.zip

      # NuGet
      nuget-project-dirs: TnmsPluginFoundation
      nuget-config-props: config.props
    secrets:
      NUGET_API_KEY: ${{ secrets.NUGET_API_KEY }}
```

Result (on tag push):

- Four zips:
  - `TnmsPluginFoundation-Core-linux-x64.zip`
  - `TnmsPluginFoundation-Core-win-x64.zip`
  - `TnmsPluginFoundation-WithDependencies-linux-x64.zip`
  - `TnmsPluginFoundation-WithDependencies-win-x64.zip`
- The `TnmsPluginFoundation` package is pushed to NuGet.org.

### D. Multiple csproj in one repo

```yaml
name: CI/CD
on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  cicd:
    uses: possession-community/modsharp-publish-action/.github/workflows/deploy.yml@v1
    with:
      projects: |
        PluginA
        PluginB
        PluginC
      shared-projects-phase1: CoreLib
      shared-projects-phase2: ExtensionLib   # depends on CoreLib

      main-artifact-name: MyPluginSuite
      main-artifact-include: modules shared gamedata

      nuget-project-dirs: CoreLib ExtensionLib
    secrets:
      NUGET_API_KEY: ${{ secrets.NUGET_API_KEY }}
```

## Inputs

### General

| input | type | default | description |
| --- | --- | --- | --- |
| `dotnet-version` | string | `10.0.x` | Version passed to `actions/setup-dotnet` |
| `runs-on` | string | `ubuntu-latest` | Runner label. Linux cross-builds `win-x64`, so this rarely needs changing. |
| `platforms` | string | `linux-x64` | Value(s) for `dotnet publish -r`. Space/newline separated; more than one triggers a matrix build and adds a platform suffix to zip names. |
| `target-framework` | string | `net10.0` | Target framework moniker (`-f`) |
| `no-ci-marker` | string | `[no ci]` | Commits containing this marker skip the CI `build` job |

### Project selection

| input | type | default | description |
| --- | --- | --- | --- |
| `projects` | string | `''` | Main module projects. Output goes to `.build/modules/<name>`. |
| `shared-projects-phase1` | string | `''` | Base shared projects. Output goes to `.build/shared/<name>`. |
| `shared-projects-phase2` | string | `''` | Shared projects that depend on phase 1. Built after phase 1 completes. |
| `build-only-shared-projects` | string | `''` | Shared projects that get built but are not pruned of ModSharp-provided DLLs |

All are space/newline separated. Each name must match a `<name>/<name>.csproj`.

### DLL removal

| input | type | default | description |
| --- | --- | --- | --- |
| `use-builtin-dlls-to-remove` | bool | `true` | Load `defaults/dlls-to-remove.txt` from this repo as the base list |
| `dlls-to-remove` | string | `''` | Additional DLL names (space/newline separated) |
| `dlls-to-remove-file` | string | `''` | Path in the caller repo to a text file listing additional DLLs |
| `shared-dlls-to-remove` | string | `''` | Shared-side DLL names to strip from module outputs |
| `shared-dlls-to-remove-file` | string | `''` | Same as above, via file |

See [Managing the DLL removal list](#managing-the-dll-removal-list) for details.

### Extra files

| input | type | default | description |
| --- | --- | --- | --- |
| `custom-dirs` | string | `''` | Directories at the repo root copied into EVERY module output (e.g. `lang cfg`) — duplicates per module |
| `top-level-dirs` | string | `''` | Directories at the repo root copied ONCE to `.build/<name>/` — same placement as `gamedata/` |

Passing `custom-dirs: lang cfg` copies those directories into `.build/modules/<project>/lang/` and `.../cfg/` (once per module).

Passing `top-level-dirs: locales` copies `locales/` once into `.build/locales/` (shared across all modules in the resulting zip).

### Artifacts

| input | type | default | description |
| --- | --- | --- | --- |
| `main-artifact-name` | string | `''` | Base name (no extension) for the main zip. Leaving this empty skips the main zip. |
| `main-artifact-include` | string | `modules gamedata` | Paths under `.build/` to include in the main zip |
| `extended-artifact-name` | string | `''` | Base name for the extended zip. Leaving this empty skips the extended zip. |
| `extended-artifact-include` | string | `shared modules gamedata` | Paths under `.build/` to include in the extended zip |
| `dependencies` | string | `''` | Dependency zip URLs (one per line). Downloaded and extracted into `.build/` before the extended zip is produced. |

Naming rules: see [Artifact naming rules](#artifact-naming-rules).

### NuGet

| input | type | default | description |
| --- | --- | --- | --- |
| `nuget-project-dirs` | string | `''` | Project directories to pack and push (space/newline separated). Leave empty to skip NuGet publish. |
| `nuget-config-props` | string | `config.props` | Path to a props/xml file containing `<Version>` (relative to repo root) |

Every csproj referenced here must have an explicit `<PackageId>` — see [NuGet publishing](#nuget-publishing).

## Secrets

| name | required | purpose |
| --- | --- | --- |
| `NUGET_API_KEY` | only when `nuget-project-dirs` is set | NuGet.org API key |

The caller must pass it through explicitly:

```yaml
secrets:
  NUGET_API_KEY: ${{ secrets.NUGET_API_KEY }}
```

## Managing the DLL removal list

DLLs already provided by the ModSharp runtime cause version conflicts when shipped alongside plugins. The workflow removes a configurable list of DLL files from the publish output to avoid this.

### Default behaviour (recommended)

With `use-builtin-dlls-to-remove: true` (the default), [`defaults/dlls-to-remove.txt`](defaults/dlls-to-remove.txt) from this repository is loaded automatically.

When the ModSharp-provided DLL set changes:

1. Update `defaults/dlls-to-remove.txt` in this repo.
2. Cut a new tag.
3. Callers just bump `@v1` → `@v2`.

### Adding project-specific entries

Keep the built-in list and append your own:

```yaml
with:
  # inline
  dlls-to-remove: MyProjectSpecific.dll AnotherOne.dll

  # or a file in the caller repo
  dlls-to-remove-file: .modsharp/extra-dlls.txt
```

The file format matches `defaults/dlls-to-remove.txt`:

```
# comments are allowed
MyLib.dll
AnotherLib.dll

# blank lines too
Special.dll
```

### Opting out of the built-in list

```yaml
with:
  use-builtin-dlls-to-remove: false
  dlls-to-remove-file: .modsharp/dlls.txt
```

### Stripping shared DLLs from module outputs

If your main module publish output includes DLLs that should only live in the `shared/` directory, strip them as well:

```yaml
with:
  shared-dlls-to-remove: |
    TnmsAdministrationPlatform.Shared.dll
    TnmsLocalizationPlatform.Shared.dll
  shared-dlls-to-remove-file: .modsharp/shared-dlls.txt
```

## NuGet publishing

### Basics

List the directories you want to publish in `nuget-project-dirs`. The workflow reads `<Version>` from `config.props` (or whatever `nuget-config-props` points to) and pushes only `*.<Version>.nupkg` from `bin/Release/`.

```yaml
with:
  nuget-project-dirs: MyLib1 MyLib2
  nuget-config-props: config.props   # default
secrets:
  NUGET_API_KEY: ${{ secrets.NUGET_API_KEY }}
```

Example `config.props`:

```xml
<Project>
  <PropertyGroup>
    <Version>1.2.3</Version>
  </PropertyGroup>
</Project>
```

### Explicit PackageId

Every csproj listed in `nuget-project-dirs` must define `<PackageId>` explicitly:

```xml
<!-- MyLib1/MyLib1.csproj -->
<PropertyGroup>
  <TargetFramework>net10.0</TargetFramework>
  <PackageId>MyLib1</PackageId>
</PropertyGroup>
```

Rationale: without an explicit `<PackageId>`, the value is derived from the csproj filename. Renaming the csproj then silently changes the NuGet package identity, which is a footgun. This workflow refuses to proceed unless the value is set directly.

Validation points:

- `build` (CI) job — runs when `nuget-project-dirs` is set, so issues surface at PR time.
- `publish-nuget` job — re-validates after the tag is pushed.

### What the push step runs

```bash
dotnet restore
dotnet build -c Release
dotnet pack --configuration Release
# glob and push bin/Release/*.<VERSION>.nupkg with --skip-duplicate
```

`--skip-duplicate` keeps re-runs idempotent. The glob means the workflow works even if your `<PackageId>` differs from the directory name.

## Artifact naming rules

### Single platform (`platforms: linux-x64`, or the default)

| input | resulting zip | artifact name |
| --- | --- | --- |
| `main-artifact-name: MyPlugin` | `MyPlugin.zip` | `release-artifacts` |
| `extended-artifact-name: MyPlugin-Full` | `MyPlugin-Full.zip` | same artifact, uploaded together |

### Multi-platform (`platforms: linux-x64 win-x64`)

The platform is appended automatically.

| input | zip from the linux-x64 job | zip from the win-x64 job |
| --- | --- | --- |
| `main-artifact-name: MyPlugin` | `MyPlugin-linux-x64.zip` | `MyPlugin-win-x64.zip` |
| `extended-artifact-name: MyPlugin-Full` | `MyPlugin-Full-linux-x64.zip` | `MyPlugin-Full-win-x64.zip` |

Artifact names split by platform:

- `release-artifacts-linux-x64` (all linux-x64 zips)
- `release-artifacts-win-x64` (all win-x64 zips)

### Arbitrary naming patterns

`main-artifact-name` / `extended-artifact-name` are used verbatim before the optional suffix, so you can produce e.g. `<artifact>-<Core|Full>-<platform>.zip`:

```yaml
with:
  main-artifact-name: MyPlugin-Core       # → MyPlugin-Core-linux-x64.zip
  extended-artifact-name: MyPlugin-Full   # → MyPlugin-Full-linux-x64.zip
```

## Creating a GitHub Release

This workflow stops at artifact upload. Add a separate release job in your caller workflow.

### Single platform

```yaml
jobs:
  cicd:
    uses: possession-community/modsharp-publish-action/.github/workflows/deploy.yml@v1
    with:
      projects: MyPlugin
      main-artifact-name: MyPlugin

  release:
    needs: cicd
    if: startsWith(github.ref, 'refs/tags/')
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: release-artifacts
          path: artifacts/
      - env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release create "${GITHUB_REF_NAME}" \
            --repo "${GITHUB_REPOSITORY}" \
            --title "Release ${GITHUB_REF_NAME}" \
            --generate-notes \
            artifacts/*.zip
```

### Multiple platforms

Use `pattern:` + `merge-multiple: true` to download every matrix entry:

```yaml
jobs:
  cicd:
    uses: possession-community/modsharp-publish-action/.github/workflows/deploy.yml@v1
    with:
      projects: MyPlugin
      platforms: linux-x64 win-x64
      main-artifact-name: MyPlugin

  release:
    needs: cicd
    if: startsWith(github.ref, 'refs/tags/')
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          pattern: release-artifacts-*
          merge-multiple: true
          path: artifacts/
      - env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release create "${GITHUB_REF_NAME}" \
            --repo "${GITHUB_REPOSITORY}" \
            --title "Release ${GITHUB_REF_NAME}" \
            --generate-notes \
            artifacts/*.zip
```

### Draft / prerelease

Tweak the `gh` flags:

```bash
gh release create "${GITHUB_REF_NAME}" --repo "${GITHUB_REPOSITORY}" --draft ...
gh release create "${GITHUB_REF_NAME}" --repo "${GITHUB_REPOSITORY}" --prerelease ...
```

## Inside the publish job (step-by-step)

```
1. Wipe .build/{modules,shared,gamedata}
2. Publish shared-projects-phase1 → .build/shared/<name>
   └─ Strip DLLs on the removal list
3. Publish shared-projects-phase2 (same)
4. Publish build-only-shared-projects (skip DLL stripping)
5. Publish projects → .build/modules/<name>
   ├─ remove <name>.pdb
   ├─ apply the DLL removal list
   ├─ apply shared-dlls-to-remove
   ├─ rename appsettings.json → appsettings.example.json
   └─ copy custom-dirs
6. Copy gamedata/ → .build/gamedata/ (if present)
6b. Copy each top-level-dirs entry → .build/<name>/ (once, shared across modules)
7. Zip the paths in main-artifact-include → dist/<name>.zip
8. (if configured) Download and extract dependencies into .build/
9. (if configured) Zip the paths in extended-artifact-include → dist/<name>.zip
10. Upload dist/*.zip as an artifact
```

The `build` CI job runs steps 1 through 6 only — no zipping, no upload.

## Troubleshooting

| symptom | cause / fix |
| --- | --- |
| `::error::$csproj: <PackageId> is not explicitly set` | Add `<PackageId>YourPackage</PackageId>` to the offending csproj |
| `::error::<Version> not found in config.props` | Confirm the props file contains `<Project><PropertyGroup><Version>...</Version></PropertyGroup></Project>` |
| `::warning::<name>/<name>.csproj not found, skipping` | The name passed to `projects` must match the directory and csproj filename |
| `::error::no paths to include in <name> zip` | Nothing under `.build/` matched `main-artifact-include`. Check the build succeeded and the include paths are correct. |
| `::error::NUGET_API_KEY secret is required` | Make sure the caller passes `secrets: NUGET_API_KEY: ${{ secrets.NUGET_API_KEY }}` |
| Artifact upload fails with `if-no-files-found: error` | You tagged without setting either `main-artifact-name` or `extended-artifact-name`. Set at least one. |
| Matrix doesn't parallelize | Confirm `platforms` really has multiple entries. Use space or newline separation — no JSON array syntax. |

## Repository layout

```
modsharp-publish-action/
├── .github/workflows/
│   └── deploy.yml                 # reusable workflow (orchestration only)
├── defaults/
│   └── dlls-to-remove.txt         # built-in ModSharp DLL removal list
├── scripts/
│   ├── parse-platforms.sh         # platforms → JSON array (for matrix)
│   ├── build.sh                   # port of build.bat
│   ├── create-zip.sh              # .build/<paths> → dist/<name>.zip
│   ├── download-dependencies.sh   # download + extract dependency zips
│   ├── extract-version.sh         # read <Version> from a props file
│   ├── pack-and-push.sh           # dotnet pack + nuget push
│   └── validate-packageids.sh    # enforce explicit <PackageId>
├── README.md                      # this file (English)
└── README_JA.md                   # Japanese version
```

The workflow checks itself out into `.modsharp-deploy/` via `${{ github.workflow_ref }}` so that the scripts are available at runtime.

## Running scripts locally

Every script reads its inputs from `MSD_*` environment variables, so they can be invoked directly on your machine.

Running `build.sh` locally:

```bash
cd your-plugin-repo/
export MSD_PLATFORM=linux-x64
export MSD_TFM=net10.0
export MSD_PROJECTS=MyPlugin
export MSD_BUILTIN_DLLS_FILE=/path/to/modsharp-publish-action/defaults/dlls-to-remove.txt
bash /path/to/modsharp-publish-action/scripts/build.sh
# → output lands in .build/
```

Running `validate-packageids.sh`:

```bash
export MSD_NUGET_PROJECT_DIRS=MyLib1
bash /path/to/modsharp-publish-action/scripts/validate-packageids.sh
```

## Permissions

The workflow itself requires no special permissions (it only uploads artifacts). If you add a release job on the caller side, grant `contents: write` there.
