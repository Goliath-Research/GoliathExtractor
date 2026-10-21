# MethylExtractor CI

Workflows live in [`.github/workflows/`](../.github/workflows/).

| Workflow | Trigger | Jobs |
|----------|---------|------|
| [`build.yml`](../.github/workflows/build.yml) | Push to `main` and pull requests | Packaging-script fixtures, `make dynamic` plus `--help`, Pyrefly, [`.goliath/product.json`](../.goliath/product.json) against its schema, hashed MkDocs install and `mkdocs build --strict` |
| [`pages.yml`](../.github/workflows/pages.yml) | Push to `main` and manual dispatch | Hashed install from [`requirements/mkdocs.txt`](../requirements/mkdocs.txt), `mkdocs build --strict`, upload the `site` directory, deploy GitHub Pages |
| [`release.yml`](../.github/workflows/release.yml) | Tags `v*` or a manual `releaseVersion` | amd64 and aarch64 tarballs, smoke in bare container images, GitHub Release upload |

The `docs` job in `build.yml` installs MkDocs from [`requirements/mkdocs.txt`](../requirements/mkdocs.txt) with hashes, builds the site, and does not deploy it. `pages.yml` publishes [https://goliath-research.github.io/MethylExtractor/](https://goliath-research.github.io/MethylExtractor/) from that same lockfile and does not run on pull requests. The build job's token is `contents: read`. `pages: write` and `id-token: write` are set only on the deploy job. Release packaging is [docs/release_packaging.md](../docs/release_packaging.md).

## Release flow in this repository

1. Tag `v2026.10.1` (SemVer, no leading zeros: not `v2026.010.1`).
2. `release.yml` builds on Ubuntu 22.04 for amd64 and aarch64, bundles non-glibc libraries, and smokes the tarballs.
3. The `publish` job uploads `methyl-extractor-linux-amd64.tar.gz`, `methyl-extractor-linux-aarch64.tar.gz`, and the matching `.sha256` files to that GitHub Release.

`permissions: contents: write` on the release workflow is what allows the upload. Pull-request builds do not publish.
