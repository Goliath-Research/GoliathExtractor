# MethylExtractor CI

All CI is **GitHub Actions** under [`.github/workflows/`](../.github/workflows/).

| Workflow | Trigger |
|----------|---------|
| [`.github/workflows/build.yml`](../.github/workflows/build.yml) | Push/PR — packaging script fixture, `make dynamic` + `--help` smoke, and Pyrefly on Python sources |
| [`.github/workflows/release.yml`](../.github/workflows/release.yml) | Tags `v*` (or manual `releaseVersion`) — amd64 + aarch64 tarballs on the GitHub Release |

Orchestration (assemble/deploy) lives in [GoliathWorkflow](https://github.com/Goliath-Research/GoliathWorkflow) `.github/workflows/`.

Release packaging uses the vendored [`scripts/package_methyl_extractor.sh`](../scripts/package_methyl_extractor.sh) (from GoliathOmics). The release workflow does not check out GoliathWorkflow or GoliathOmics.

## Prerequisites

1. Org **Goliath-Research** with Actions enabled; `GITHUB_TOKEN` `contents: write` on the release workflow.
2. SemVer tags: `v2026.6.1` (not `v2026.06.1`).

## Release flow

1. Tag MethylExtractor `v2026.6.1` → **release** workflow (amd64 + aarch64).
2. Tag MethylPipeline → GoliathWorkflow **release**.
3. Run GoliathWorkflow **release-assemble** with both versions pinned.
4. Approve GoliathWorkflow **release-deploy**.
