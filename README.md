# klaus-toolchains

Public toolchain container images that extend the minimal [Klaus](https://github.com/giantswarm/klaus) base with language runtimes and tools.

## Images

Each image adds exactly what it needs on top of Klaus. Variant is encoded in the image name, not the tag.

| Image | Contents | Base |
|-------|----------|------|
| `giantswarm/klaus-toolchains/go` | + git, Go runtime | `giantswarm/klaus` |
| `giantswarm/klaus-toolchains/go-debian` | + git, Go runtime (Debian) | `giantswarm/klaus-debian` |

### Image hierarchy

All toolchain images build directly from the Klaus base to avoid cross-image registry dependencies:

```
giantswarm/klaus
└── giantswarm/klaus-toolchains/go          (+ git + Go)

giantswarm/klaus-debian
└── giantswarm/klaus-toolchains/go-debian
```

## Tagging

Each image has its own independent version lifecycle. Tags use the format `<name>/v<semver>`:

- `go/v0.1.0`

This format is required by `architect project version --git-tag-prefix` for correct version extraction in mono-repos.

When a PR is merged to `main`, the auto-release workflow detects which `klaus-*/` directories changed and creates a patch-bumped tag for each (e.g. `go/v0.1.0` -> `go/v0.1.1`). Tags are pushed one at a time to ensure each triggers its own CircleCI release pipeline.

For minor or major bumps, create the tag manually:

```bash
git tag go/v1.0.0 && git push origin go/v1.0.0
```

Dev builds on branches use commit-SHA-based tags automatically via `architect project version`.

## Build args

| Arg | Default | Description |
|-----|---------|-------------|
| `KLAUS_VERSION` | pinned | Klaus base image version. Updated by Renovate. |
| `GO_VERSION` | `1.25` | Go version (klaus-go only). Managed by platform team. |

## Usage

Reference images in klausctl config, Helm values, or operator CRDs:

```yaml
image: gsoci.azurecr.io/giantswarm/klaus-toolchains/go:0.1.0
```

## Repository structure

```
klaus-go/
├── Dockerfile           # Alpine variant
└── Dockerfile.debian    # Debian variant
```

## CI

CircleCI uses [dynamic configuration](https://circleci.com/docs/dynamic-config/) to auto-discover images. A setup job runs `.circleci/generate-config.sh`, which:

- **Branch builds**: finds which `klaus-*/` directories changed vs `origin/main` and generates `push-to-registries-multiarch` jobs for those only (amd64, dev tags).
- **Tag builds**: parses the tag prefix (e.g. `go` from `go/v0.1.0`) and generates multi-arch release jobs for the matching image.
- **No changes**: emits a no-op workflow.

Adding a new image is as simple as creating a `klaus-<name>/` directory with a `Dockerfile` -- no CI config or Makefile edits required.
