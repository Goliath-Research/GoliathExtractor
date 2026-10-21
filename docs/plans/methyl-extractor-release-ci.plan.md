---
name: MethylExtractor release CI
overview: GitHub Actions workflows that build the dynamic binary on pull requests and publish per-arch tarballs to GitHub Releases on v* tags.
todos:
  - id: pr-pipeline
    content: .github/workflows/build.yml builds, smokes --help, runs packaging fixtures and Pyrefly
    status: completed
  - id: release-tarballs
    content: .github/workflows/release.yml builds amd64 and aarch64 on Ubuntu 22.04 and uploads GitHub Release assets
    status: completed
  - id: bundle-libs
    content: scripts/package_methyl_extractor.sh --bundle-libs plus scripts/bundle_libs.sh
    status: completed
isProject: false
---

# MethylExtractor release CI

Current workflows (release 2026.10.1):

| Workflow | Runner | Trigger | Result |
|----------|--------|---------|--------|
| `.github/workflows/build.yml` | `ubuntu-latest` | Push to `main` and pull requests | Packaging fixtures, `make dynamic`, `--help`, Pyrefly, product JSON, MkDocs build |
| `.github/workflows/release.yml` | `ubuntu-22.04`, `ubuntu-22.04-arm` | Tags `v*`, or a manual `releaseVersion` | `methyl-extractor-linux-{amd64,aarch64}.tar.gz` plus `.sha256` |

The release job's smoke matrix unpacks those tarballs in `ubuntu:22.04`, `ubuntu:24.04`, `ubuntu:latest`, and `debian:stable-slim` before `publish` creates or updates the GitHub Release. Publish does not run on pull requests.

Tag form: `v2026.10.1` (no leading zero on the month or patch). A manual dispatch that is not a tag must set `releaseVersion`.

Packaging details: [Release packages](../release_packaging.md).
