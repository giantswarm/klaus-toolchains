#!/usr/bin/env bash
set -euo pipefail

# Emit a complete CircleCI continuation config to stdout.
# Called by the setup job in config.yml.
#
# Branch builds: jobs for changed klaus-*/ dirs only (amd64, dev tags).
# Tag builds:    single job for the image matching the tag prefix (multi-arch).
# No changes:    minimal no-op config.

ARCHITECT_ORB="giantswarm/architect@6.14.0"

# Keep in sync with Makefile ANNOTATION_* variables.
ANNOTATION_AUTHOR_NAME="Giant Swarm GmbH"
ANNOTATION_AUTHOR_URL="https://giantswarm.io"
ANNOTATION_REPOSITORY="https://github.com/giantswarm/klaus-toolchains"
ANNOTATION_LICENSE="Apache-2.0"

emit_header() {
  cat <<EOF
version: 2.1

orbs:
  architect: ${ARCHITECT_ORB}

workflows:
  build:
    jobs:
EOF
}

get_annotations() {
  local name="$1"
  local indent="$2"
  local base="${name%-debian}"
  local pretty="$(echo "${base:0:1}" | tr '[:lower:]' '[:upper:]')${base:1}"
  local desc="${pretty} toolchain for Klaus"
  if [[ "$name" == *-debian ]]; then
    desc="${desc} (Debian)"
  fi
  echo "${indent}io.giantswarm.klaus.name=${name}"
  echo "${indent}io.giantswarm.klaus.description=${desc}"
  echo "${indent}io.giantswarm.klaus.repository=${ANNOTATION_REPOSITORY}"
  echo "${indent}io.giantswarm.klaus.license=${ANNOTATION_LICENSE}"
  echo "${indent}io.giantswarm.klaus.keywords=giantswarm,${base},toolchain"
  echo "${indent}io.giantswarm.klaus.author.name=${ANNOTATION_AUTHOR_NAME}"
  echo "${indent}io.giantswarm.klaus.author.url=${ANNOTATION_AUTHOR_URL}"
}

emit_branch_job() {
  local name="$1" dockerfile="$2" dir="$3"
  cat <<EOF
    - architect/push-to-registries-multiarch:
        context: architect
        name: push-${name}
        image: giantswarm/klaus-toolchains/${name}
        dockerfile: ./${dir}/${dockerfile}
        build-context: ./${dir}
        platforms: "linux/amd64"
        resource_class: medium
        annotations: |
$(get_annotations "$name" "          ")
EOF
}

emit_tag_job() {
  local name="$1" dockerfile="$2" dir="$3" prefix="$4"
  cat <<EOF
    - architect/push-to-registries-multiarch:
        context: architect
        name: push-${name}
        image: giantswarm/klaus-toolchains/${name}
        dockerfile: ./${dir}/${dockerfile}
        build-context: ./${dir}
        platforms: "linux/amd64,linux/arm64"
        resource_class: medium
        git-tag-prefix: "${prefix}"
        annotations: |
$(get_annotations "$name" "          ")
        filters:
          tags:
            only: /^${prefix}\\/v.*/
          branches:
            ignore: /.*/
EOF
}

emit_noop() {
  cat <<EOF
version: 2.1

jobs:
  no-op:
    docker:
      - image: cimg/base:current
    steps:
      - run: echo "No image directories changed"

workflows:
  noop:
    jobs:
      - no-op
EOF
}

emit_jobs_for_dir() {
  local dir="$1" mode="$2"
  local short_name="${dir#klaus-}"

  if [[ -f "${dir}/Dockerfile" ]]; then
    if [[ "$mode" == "branch" ]]; then
      emit_branch_job "$short_name" "Dockerfile" "$dir"
    else
      emit_tag_job "$short_name" "Dockerfile" "$dir" "$short_name"
    fi
  fi

  if [[ -f "${dir}/Dockerfile.debian" ]]; then
    if [[ "$mode" == "branch" ]]; then
      emit_branch_job "${short_name}-debian" "Dockerfile.debian" "$dir"
    else
      emit_tag_job "${short_name}-debian" "Dockerfile.debian" "$dir" "${short_name}"
    fi
  fi
}

# --- Main ---

if [[ -n "${CIRCLE_TAG:-}" ]]; then
  PREFIX="${CIRCLE_TAG%%/v*}"

  if [[ ! -d "klaus-${PREFIX}" ]]; then
    echo "ERROR: Tag ${CIRCLE_TAG} does not match any klaus-*/ directory" >&2
    exit 1
  fi

  emit_header
  emit_jobs_for_dir "klaus-${PREFIX}" "tag"
  exit 0
fi

# Branch build: only build changed directories
mapfile -t ALL_DIRS < <(
  find . -maxdepth 2 -name 'Dockerfile' -path './klaus-*/*' \
    -exec dirname {} \; | sed 's|^\./||' | sort -u
)

CHANGED_DIRS=()
if git rev-parse --verify origin/main >/dev/null 2>&1; then
  mapfile -t CHANGED_DIRS < <(
    git diff --name-only origin/main...HEAD \
      | { grep '^klaus-' || true; } \
      | cut -d/ -f1 \
      | sort -u
  )
fi

BUILD_DIRS=()
for dir in "${ALL_DIRS[@]}"; do
  for changed in "${CHANGED_DIRS[@]}"; do
    if [[ "$dir" == "$changed" ]]; then
      BUILD_DIRS+=("$dir")
      break
    fi
  done
done

if [[ ${#BUILD_DIRS[@]} -eq 0 ]]; then
  emit_noop
  exit 0
fi

emit_header
for dir in "${BUILD_DIRS[@]}"; do
  emit_jobs_for_dir "$dir" "branch"
done
