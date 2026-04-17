# modsharp-publish-action

> 注意: このワークフローおよび付属スクリプトは AI アシスタント (Claude) によって生成されています。利用前に内容をよく確認し、問題を見つけた場合は issue を立ててください。

ModSharpプラグイン / 共有ライブラリ向けの再利用可能GitHub Actionsワークフロー。
`build.bat` 相当のビルドロジックをbashで実装し、Linuxランナー (`ubuntu-latest`) から Linux/Windows 両方向けの成果物を生成できます。

## 目次

- [できること](#できること)
- [ジョブ構成](#ジョブ構成)
- [Caller側リポジトリの前提](#caller側リポジトリの前提)
- [クイックスタート](#クイックスタート)
- [コピペできる build job テンプレ](#コピペできるbuild-jobテンプレ)
  - [A. シンプルなプラグイン (単一platform)](#a-シンプルなプラグイン-単一platform)
  - [B. プラグイン (linux + win 両対応)](#b-プラグイン-linux--win-両対応)
  - [C. 共有ライブラリ + NuGet + 依存同梱 (TnmsPluginFoundation相当)](#c-共有ライブラリ--nuget--依存同梱-tnmspluginfoundation相当)
  - [D. 複数csprojを一気にビルド](#d-複数csprojを一気にビルド)
- [入力一覧](#入力一覧)
- [Secrets](#secrets)
- [DLL除外リストの管理](#dll除外リストの管理)
- [NuGet公開](#nuget公開)
- [アーティファクトの命名規則](#アーティファクトの命名規則)
- [Releaseを作成したい場合](#releaseを作成したい場合)
- [動作の内訳 (publishジョブの処理順)](#動作の内訳-publishジョブの処理順)
- [トラブルシュート](#トラブルシュート)
- [リポジトリ構成](#リポジトリ構成)
- [ローカルでの確認](#ローカルでの確認)

## できること

- Linuxランナー対応 — `dotnet publish -r` によるクロスコンパイルで `win-x64` / `linux-x64` いずれも生成可能。
- 複数プラットフォーム同時ビルド — `platforms: linux-x64 win-x64` で matrix 並行ビルド。zip にプラットフォームサフィックス自動付与。
- 複数csproj対応 — 1リポジトリに複数のモジュール/共有プロジェクトがあっても、入力にスペース/改行区切りで並べるだけ。
- ビルトインDLL除外リスト — ModSharpランタイムが提供するDLLの除外リストをこのリポジトリで一元管理。ModSharp側更新に追随してタグを切れば全利用プロジェクトに反映。
- 成果物の柔軟なパッケージング — モジュール型プラグインと共有ライブラリ型プロジェクトどちらも対応。依存ライブラリをダウンロードして同梱した "フル版" zip も作れる。
- NuGet公開 — 複数プロジェクトの同時push。`<PackageId>` 明示チェック付き。

## ジョブ構成

| job | 実行条件 | 内容 |
| --- | --- | --- |
| `setup` | 常時 | `platforms` 入力を JSON 配列に変換 (matrix 用) |
| `build` | tag以外のpush、かつ `[no ci]` を含まない | CIビルド (platformごとに matrix、成果物は作らない) |
| `publish` | tag push | フル publish + zip化 + Artifactアップロード (platformごとに matrix) |
| `publish-nuget` | tag push & `nuget-project-dirs` 指定時 | NuGet.org へ push (matrix なし、1回のみ) |

> リリース作成は行いません。Artifactアップロードまで。caller側で `gh release create` などのジョブを追加してください ([Releaseを作成したい場合](#releaseを作成したい場合)参照)。

## Caller側リポジトリの前提

このワークフローを使うリポジトリは以下の構成を満たしている必要があります。

```
<caller-repo>/
├── <ProjectName>/              # csproj 毎にディレクトリ (ディレクトリ名 == csproj名)
│   ├── <ProjectName>.csproj
│   └── ...
├── gamedata/                   # 任意、あれば成果物に含まれる
├── config.props                # NuGet公開する場合に <Version> を持つ
└── .github/workflows/cicd.yml  # このワークフローを呼び出す
```

重要な制約:

- `projects` / `shared-projects-*` / `nuget-project-dirs` に指定する名前は、 `<name>/<name>.csproj` の形のディレクトリ・csproj の組であること (`build.bat` と同じ前提)
- NuGet公開するcsprojは `<PackageId>` を明示すること (無いとCIで失敗する)

## クイックスタート

1. Caller リポジトリの `.github/workflows/cicd.yml` を作成
2. 下記 [テンプレ](#コピペできるbuild-jobテンプレ) から近いものを選んでコピペ
3. `projects` / `main-artifact-name` などを自分のプロジェクトに合わせて書き換え
4. main へpushして `build` (CI) が通るか確認
5. `v1.0.0` などのタグをpushして `publish` / `publish-nuget` が走るか確認

ワークフローのトリガーは caller 側で定義します (reusable workflow はトリガーを持たないため):

```yaml
on:
  push:
    branches: [main]
    tags: ['v*']
```

## コピペできるbuild jobテンプレ

各テンプレートは `on:` トリガーも含めた完全形。`uses:` の `@v1` はタグ運用に応じて変えてください (`@main` でもOK)。

### A. シンプルなプラグイン (単一platform)

```yaml
# .github/workflows/cicd.yml
name: CI/CD

on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  cicd:
    uses: fltuna/modsharp-publish-action/.github/workflows/deploy.yml@v1
    with:
      projects: MyPlugin
      main-artifact-name: MyPlugin
```

結果:

- `main` push → `build` ジョブでビルド確認のみ
- `v*` タグpush → Artifact `release-artifacts` に `MyPlugin.zip` がアップロードされる

### B. プラグイン (linux + win 両対応)

```yaml
name: CI/CD
on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  cicd:
    uses: fltuna/modsharp-publish-action/.github/workflows/deploy.yml@v1
    with:
      projects: MyPlugin
      platforms: linux-x64 win-x64
      main-artifact-name: MyPlugin
```

結果:

- `build` / `publish` が 2並列で走る (linux / win)
- Artifact:
  - `release-artifacts-linux-x64` → `MyPlugin-linux-x64.zip`
  - `release-artifacts-win-x64` → `MyPlugin-win-x64.zip`

### C. 共有ライブラリ + NuGet + 依存同梱 (TnmsPluginFoundation相当)

```yaml
name: CI/CD
on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  cicd:
    uses: fltuna/modsharp-publish-action/.github/workflows/deploy.yml@v1
    with:
      projects: TnmsPluginFoundation.Example
      shared-projects-phase1: TnmsPluginFoundation

      platforms: linux-x64 win-x64

      # Core (依存なし) — shared + gamedata のみ、modules は除外
      main-artifact-name: TnmsPluginFoundation-Core
      main-artifact-include: shared gamedata

      # Full (依存同梱)
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

結果 (tag push時):

- 4つのzip:
  - `TnmsPluginFoundation-Core-linux-x64.zip`
  - `TnmsPluginFoundation-Core-win-x64.zip`
  - `TnmsPluginFoundation-WithDependencies-linux-x64.zip`
  - `TnmsPluginFoundation-WithDependencies-win-x64.zip`
- `TnmsPluginFoundation` パッケージが NuGet.org に push される

### D. 複数csprojを一気にビルド

```yaml
name: CI/CD
on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  cicd:
    uses: fltuna/modsharp-publish-action/.github/workflows/deploy.yml@v1
    with:
      projects: |
        PluginA
        PluginB
        PluginC
      shared-projects-phase1: CoreLib
      shared-projects-phase2: ExtensionLib   # CoreLib に依存

      main-artifact-name: MyPluginSuite
      main-artifact-include: modules shared gamedata

      nuget-project-dirs: CoreLib ExtensionLib
    secrets:
      NUGET_API_KEY: ${{ secrets.NUGET_API_KEY }}
```

## 入力一覧

### 基本

| 入力 | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `dotnet-version` | string | `10.0.x` | `actions/setup-dotnet` に渡すSDKバージョン |
| `runs-on` | string | `ubuntu-latest` | ランナーラベル。Linuxから win-x64 もビルドできるので基本変更不要 |
| `platforms` | string | `linux-x64` | `dotnet publish -r` に渡す値。スペース/改行区切りで複数指定するとmatrixビルド + zip名にサフィックス付与 |
| `target-framework` | string | `net10.0` | TFM (`-f`) |
| `no-ci-marker` | string | `[no ci]` | この文字列がコミットメッセージに含まれるとCIをスキップ |

### プロジェクト指定

| 入力 | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `projects` | string | `''` | メインモジュールのプロジェクト名。`.build/modules/<name>` に出力される |
| `shared-projects-phase1` | string | `''` | ベース共有プロジェクト。`.build/shared/<name>` に出力される |
| `shared-projects-phase2` | string | `''` | phase1 に依存する共有プロジェクト。phase1 のビルド後に処理される |
| `build-only-shared-projects` | string | `''` | ビルドのみ実行し、DLL除外処理を行わない |

すべてスペース/改行区切り。`<name>/<name>.csproj` が存在すること。

### DLL除外

| 入力 | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `use-builtin-dlls-to-remove` | bool | `true` | このリポジトリの `defaults/dlls-to-remove.txt` をベースとして読み込む |
| `dlls-to-remove` | string | `''` | 追加の除外DLL (スペース/改行区切り) |
| `dlls-to-remove-file` | string | `''` | 追加の除外DLLをファイルで指定 (caller repo内のパス) |
| `shared-dlls-to-remove` | string | `''` | モジュール出力から除外するshared提供のDLL |
| `shared-dlls-to-remove-file` | string | `''` | 同上ファイル指定 |

詳細は [DLL除外リストの管理](#dll除外リストの管理)。

### 追加コピー

| 入力 | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `custom-dirs` | string | `''` | プロジェクトルートに置いたディレクトリを各モジュール出力にコピー (例: `lang cfg`) |

`custom-dirs: lang cfg` を指定すると、各 `.build/modules/<project>/lang/` / `.../cfg/` に中身がコピーされます。

### 成果物

| 入力 | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `main-artifact-name` | string | `''` | 主zip名 (拡張子なし)。未指定なら主zipは作られない |
| `main-artifact-include` | string | `modules gamedata` | 主zipに含める `.build/` 配下のパス |
| `extended-artifact-name` | string | `''` | フル版zip名。未指定ならフル版zipは作られない |
| `extended-artifact-include` | string | `shared modules gamedata` | フル版zipに含めるパス |
| `dependencies` | string | `''` | フル版zip作成前に取得する依存zipのURL (改行区切り) |

命名ルールは [アーティファクトの命名規則](#アーティファクトの命名規則) を参照。

### NuGet

| 入力 | 型 | デフォルト | 説明 |
| --- | --- | --- | --- |
| `nuget-project-dirs` | string | `''` | pack & push するプロジェクトディレクトリ (スペース/改行区切り)。空ならNuGet公開スキップ |
| `nuget-config-props` | string | `config.props` | `<Version>` を持つprops/xmlファイルへのパス (repo root基準) |

csproj には明示的な `<PackageId>` が必須 ([NuGet公開](#nuget公開)参照)。

## Secrets

| 名前 | 必須 | 用途 |
| --- | --- | --- |
| `NUGET_API_KEY` | `nuget-project-dirs` 指定時のみ | NuGet.org認証用 APIキー |

呼び出し側で明示的に渡す必要があります:

```yaml
secrets:
  NUGET_API_KEY: ${{ secrets.NUGET_API_KEY }}
```

## DLL除外リストの管理

ModSharp本体が提供済みのDLLを成果物に含めるとバージョン競合の原因になります。このワークフローは publish 後に指定DLLを削除することで回避します。

### デフォルト動作 (推奨)

`use-builtin-dlls-to-remove: true` (デフォルト) のとき、このリポジトリの [`defaults/dlls-to-remove.txt`](defaults/dlls-to-remove.txt) が自動で読み込まれます。

ModSharp 側の更新で提供DLLが変わった場合:

1. このリポジトリの `defaults/dlls-to-remove.txt` を更新
2. 新しいタグを切る
3. caller 側は `@v1` → `@v2` に変更するだけで追従

### 追加だけしたい

builtin はそのまま使いつつ、プロジェクト固有のDLLを追加:

```yaml
with:
  # 文字列で追加
  dlls-to-remove: MyProjectSpecific.dll AnotherOne.dll

  # または caller repo 内のファイルで管理
  dlls-to-remove-file: .modsharp/extra-dlls.txt
```

ファイル形式は `defaults/dlls-to-remove.txt` と同じ:

```
# コメントOK
MyLib.dll
AnotherLib.dll

# セクション分けも自由
Special.dll
```

### builtin を使わず完全に独自管理

```yaml
with:
  use-builtin-dlls-to-remove: false
  dlls-to-remove-file: .modsharp/dlls.txt
```

### shared DLLの除外 (モジュール型プラグイン向け)

メインモジュールの publish 出力に shared 側で提供されるべきDLLが含まれてしまう場合、それらも除外できます:

```yaml
with:
  shared-dlls-to-remove: |
    TnmsAdministrationPlatform.Shared.dll
    TnmsLocalizationPlatform.Shared.dll
  # ファイル指定も可
  shared-dlls-to-remove-file: .modsharp/shared-dlls.txt
```

## NuGet公開

### 基本

`nuget-project-dirs` に公開したいプロジェクトディレクトリを列挙。`config.props` (または `nuget-config-props` で指定したファイル) から `<Version>` を読み取り、そのバージョンの nupkg のみを push します。

```yaml
with:
  nuget-project-dirs: MyLib1 MyLib2
  nuget-config-props: config.props   # デフォルト
secrets:
  NUGET_API_KEY: ${{ secrets.NUGET_API_KEY }}
```

`config.props` 例:

```xml
<Project>
  <PropertyGroup>
    <Version>1.2.3</Version>
  </PropertyGroup>
</Project>
```

### PackageId の明示

各csproj には `<PackageId>` を明示的にセットする必要があります:

```xml
<!-- MyLib1/MyLib1.csproj -->
<PropertyGroup>
  <TargetFramework>net10.0</TargetFramework>
  <PackageId>MyLib1</PackageId>
</PropertyGroup>
```

理由: csproj 未設定の場合、PackageId は csproj ファイル名から自動導出されます。これだと csproj をリネームしたときに NuGet 上の識別子がサイレントに変わってしまうため、明示を必須にしています。

検証タイミング:

- `build` (CI) ジョブ: `nuget-project-dirs` 指定時に検証 — PRの段階で検出
- `publish-nuget` ジョブ: タグpush後も再検証

### push の動き

```bash
dotnet restore
dotnet build -c Release
dotnet pack --configuration Release
# bin/Release/*.<VERSION>.nupkg を glob で拾って push (--skip-duplicate 付き)
```

`--skip-duplicate` のおかげで同バージョンを複数回 push しても無害。PackageId がディレクトリ名と違っていても `*.<VERSION>.nupkg` でマッチするので動きます。

## アーティファクトの命名規則

### 単一platform (`platforms: linux-x64`、またはデフォルト)

| 指定 | 出力 zip | Artifact 名 |
| --- | --- | --- |
| `main-artifact-name: MyPlugin` | `MyPlugin.zip` | `release-artifacts` |
| `extended-artifact-name: MyPlugin-Full` | `MyPlugin-Full.zip` | 同上 (まとめてupload) |

### 複数platform (`platforms: linux-x64 win-x64`)

自動で `-<platform>` サフィックスが付きます。

| 指定 | 出力 zip (linux-x64ジョブ) | 出力 zip (win-x64ジョブ) |
| --- | --- | --- |
| `main-artifact-name: MyPlugin` | `MyPlugin-linux-x64.zip` | `MyPlugin-win-x64.zip` |
| `extended-artifact-name: MyPlugin-Full` | `MyPlugin-Full-linux-x64.zip` | `MyPlugin-Full-win-x64.zip` |

Artifact 名も分離:

- `release-artifacts-linux-x64` (linux のzip全部)
- `release-artifacts-win-x64` (win のzip全部)

### 任意の命名パターン

`main-artifact-name` / `extended-artifact-name` には何でも入れられるので、例えば:

```yaml
with:
  main-artifact-name: MyPlugin-Core       # → MyPlugin-Core-linux-x64.zip
  extended-artifact-name: MyPlugin-Full   # → MyPlugin-Full-linux-x64.zip
```

`<artifact>-<Core|Full>-<platform>.zip` のような構成にできます。

## Releaseを作成したい場合

このワークフローは Artifact upload までで止まります。caller側でRelease作成ジョブを追加してください。

### 単一platform の場合

```yaml
jobs:
  cicd:
    uses: fltuna/modsharp-publish-action/.github/workflows/deploy.yml@v1
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

### 複数platform の場合

`pattern:` + `merge-multiple: true` で全matrix entryをまとめて取得:

```yaml
jobs:
  cicd:
    uses: fltuna/modsharp-publish-action/.github/workflows/deploy.yml@v1
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

### draft や prerelease にしたい

`gh release create` のフラグを調整:

```bash
gh release create "${GITHUB_REF_NAME}" --repo "${GITHUB_REPOSITORY}" --draft ...
gh release create "${GITHUB_REF_NAME}" --repo "${GITHUB_REPOSITORY}" --prerelease ...
```

## 動作の内訳 (publishジョブの処理順)

```
1. .build/{modules,shared,gamedata} をクリア
2. shared-projects-phase1 を publish → .build/shared/<name>
   └─ DLL除外リストで絞り込み
3. shared-projects-phase2 を publish (同上)
4. build-only-shared-projects を publish (DLL除外スキップ)
5. projects を publish → .build/modules/<name>
   ├─ <name>.pdb を削除
   ├─ DLL除外リスト適用
   ├─ shared-dlls-to-remove 適用
   ├─ appsettings.json → appsettings.example.json にリネーム
   └─ custom-dirs をコピー
6. gamedata/ → .build/gamedata/ にコピー (存在時)
7. main-artifact-include のパスを zip 化 → dist/<name>.zip
8. (指定時) dependencies を .build/ に展開
9. (指定時) extended-artifact-include のパスを zip 化 → dist/<name>.zip
10. dist/*.zip を Artifact としてアップロード
```

`build` ジョブは 1〜6 まで (zip化・uploadなし)。

## トラブルシュート

| 症状 | 原因 / 対処 |
| --- | --- |
| `::error::$csproj: <PackageId> is not explicitly set` | 該当csproj に `<PackageId>YourPackage</PackageId>` を追加 |
| `::error::<Version> not found in config.props` | `config.props` に `<Project><PropertyGroup><Version>...</Version></PropertyGroup></Project>` があるか確認 |
| `::warning::<name>/<name>.csproj not found, skipping` | `projects` 入力の名前とディレクトリ名・csproj名が一致するか確認 |
| `::error::no paths to include in <name> zip` | `main-artifact-include` が参照するパスが `.build/` 配下に存在しない。ビルドが成功しているか、`include` の指定が正しいか確認 |
| `::error::NUGET_API_KEY secret is required` | `secrets: NUGET_API_KEY: ${{ secrets.NUGET_API_KEY }}` を caller 側で渡しているか確認 |
| Artifact upload が `if-no-files-found: error` で失敗 | `main-artifact-name` も `extended-artifact-name` も空のまま tag を打っている。どちらか設定する |
| matrix が起動しない / matrix が常に1つしか回らない | `platforms` に複数指定できているか確認 (スペース/改行区切り、`["linux-x64","win-x64"]` のようなJSON形式は不要) |

## リポジトリ構成

```
modsharp-publish-action/
├── .github/workflows/
│   └── deploy.yml                 # 再利用可能ワークフロー (orchestration only)
├── defaults/
│   └── dlls-to-remove.txt         # ModSharp組み込みDLLのデフォルト除外リスト
├── scripts/
│   ├── parse-platforms.sh         # platforms → JSON配列 (matrix用)
│   ├── build.sh                   # build.bat 相当のビルドロジック
│   ├── create-zip.sh              # .build/<paths> → dist/<name>.zip
│   ├── download-dependencies.sh   # 依存zipのDL + 展開
│   ├── extract-version.sh         # props から <Version> 抽出
│   ├── pack-and-push.sh           # dotnet pack + nuget push
│   └── validate-packageids.sh     # csproj の <PackageId> 明示チェック
└── README.md
```

ワークフローは `${{ github.workflow_ref }}` から自リポジトリを `.modsharp-deploy/` にcheckoutし、そのスクリプト群を呼び出します。

## ローカルでの確認

各スクリプトは `MSD_*` 環境変数を受け取るだけなので、ローカルでも単体実行できます。

build.sh をローカルで試す:

```bash
cd your-plugin-repo/
export MSD_PLATFORM=linux-x64
export MSD_TFM=net10.0
export MSD_PROJECTS=MyPlugin
export MSD_BUILTIN_DLLS_FILE=/path/to/modsharp-publish-action/defaults/dlls-to-remove.txt
bash /path/to/modsharp-publish-action/scripts/build.sh
# → .build/ に出力される
```

validate-packageids.sh:

```bash
export MSD_NUGET_PROJECT_DIRS=MyLib1
bash /path/to/modsharp-publish-action/scripts/validate-packageids.sh
```

## Permissions

このワークフロー自体は特別なpermissionsを要求しません (Artifactアップロードのみ)。Release作成を行う場合は caller 側のジョブで `contents: write` を付与してください。
