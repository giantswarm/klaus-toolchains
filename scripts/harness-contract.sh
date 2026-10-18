#!/usr/bin/env bash
set -euo pipefail

# Prove that a harness-*/ toolchain image still boots as the kagent claude
# Harness it is built FROM (coding-agents PRD, "Image contract check"):
#
#   - ENTRYPOINT is kagent-claude, and ENTRYPOINT, CMD, USER and WORKDIR are
#     the base image's;
#   - /usr/local/bin/claude and /usr/local/bin/kagent-claude are the base's
#     files, byte for byte, so `claude --version` is the line's pin;
#   - the kagent user is uid and gid 65532 and the /data layout (adapter,
#     claude, generated, workspace) is the base's, owned by 65532;
#   - git, gh and glab answer `--version` as the kagent user;
#   - `kagent-claude --check` passes with strict_version on the pinned version;
#   - every line of <dir>/contract-commands answers as the kagent user.
#
# Usage: scripts/harness-contract.sh <harness-dir> <image>
#   <harness-dir>  e.g. harness-node; its Dockerfile's last FROM is the base
#   <image>        the built image to check, e.g. harness-node:pr

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <harness-dir> <image>" >&2
  exit 2
fi
dir="${1%/}"
image="$2"

base=$(awk '$1 == "FROM" && NF == 2 { base = $2 } END { print base }' "${dir}/Dockerfile")
if [[ -z "$base" ]]; then
  echo "ERROR: ${dir}/Dockerfile has no final FROM <image> line" >&2
  exit 1
fi

failed=0
pass() { echo "ok    $*"; }
fail() { echo "FAIL  $*"; failed=1; }

# run <image> <user> <command…>: the command in a shell, entrypoint bypassed.
run() {
  local img="$1" user="$2"
  shift 2
  docker run --rm --user "$user" -e HOME=/data --entrypoint /bin/sh "$img" -c "$*"
}

docker pull -q "$base" >/dev/null

echo "contract of ${image} against ${base}"

# Image configuration.
config='{{json .Config.Entrypoint}} {{json .Config.Cmd}} {{json .Config.User}} {{json .Config.WorkingDir}}'
want=$(docker image inspect -f "$config" "$base")
got=$(docker image inspect -f "$config" "$image")
if [[ "$got" == "$want" ]]; then
  pass "entrypoint, cmd, user and workdir are the base's: ${got}"
else
  fail "entrypoint, cmd, user and workdir: got ${got}, want ${want}"
fi
entrypoint=$(docker image inspect -f '{{json .Config.Entrypoint}}' "$image")
if [[ "$entrypoint" == '["/usr/local/bin/kagent-claude"]' ]]; then
  pass "entrypoint is kagent-claude"
else
  fail "entrypoint is ${entrypoint}, want [\"/usr/local/bin/kagent-claude\"]"
fi

# The harness's binaries, user and /data, compared with the base.
# shellcheck disable=SC2016 # expands inside the image
layout='sha256sum /usr/local/bin/claude /usr/local/bin/kagent-claude &&
  echo "kagent $(id -u kagent):$(id -g kagent)" &&
  stat -c "%n %u:%g %a" /data /data/adapter /data/claude /data/generated /data/workspace'
want=$(run "$base" 0:0 "$layout")
got=$(run "$image" 0:0 "$layout")
if [[ "$got" == "$want" ]]; then
  pass "claude, kagent-claude, the kagent user and /data are the base's"
else
  fail "claude, kagent-claude, the kagent user or /data differ from the base:"
  diff <(echo "$want") <(echo "$got") | sed 's/^/      /' || true
fi
if echo "$got" | grep -qx 'kagent 65532:65532'; then
  pass "the kagent user is 65532:65532"
else
  fail "the kagent user is not 65532:65532"
fi
for d in /data /data/adapter /data/claude /data/generated /data/workspace; do
  if echo "$got" | grep -q "^${d} 65532:65532 "; then
    pass "${d} is owned by 65532"
  else
    fail "${d} is missing or not owned by 65532"
  fi
done

# The pinned Claude Code version: the base's own `claude --version`.
want=$(run "$base" 65532:65532 'claude --version')
got=$(run "$image" 65532:65532 'claude --version')
if [[ "$got" == "$want" ]]; then
  pass "claude --version is the pin: ${got}"
else
  fail "claude --version: got ${got}, want ${want}"
fi
pinned="${want%% *}"

# git and the forge CLIs, from the base.
for tool in git gh glab; do
  if out=$(run "$image" 65532:65532 "${tool} --version" 2>&1); then
    pass "${tool}: $(echo "$out" | head -1)"
  else
    fail "${tool} --version: ${out}"
  fi
done

# kagent-claude in check mode, as the controller starts it. The config
# version is the one this kagent-claude wants, read from its refusal of 0.
harness_check() {
  docker run --rm -e OTEL_SDK_DISABLED=true \
    -e KAGENT_AGENT_CARD_JSON='{"name":"contract"}' \
    -e KAGENT_CONFIG_JSON="{\"version\":$1,\"claude_executable\":\"claude\",\"expected_claude_version\":\"${pinned}\",\"strict_version\":true,\"max_event_bytes\":1048576,\"max_stderr_bytes\":65536,\"interrupt_grace_millis\":2000}" \
    "$image" --check 2>&1
}
version=$(harness_check 0 | grep -o 'unsupported config version 0 (want [0-9]*)' | grep -o '[0-9]*)$' | tr -d ')' || true)
if [[ -z "$version" ]]; then
  fail "kagent-claude --check: cannot read the config version it wants"
elif out=$(harness_check "$version"); then
  pass "kagent-claude --check passes (config version ${version}, strict on ${pinned})"
else
  fail "kagent-claude --check (config version ${version}): ${out}"
fi

# The toolchain's own commands.
if [[ -f "${dir}/contract-commands" ]]; then
  while IFS= read -r cmd; do
    [[ -z "$cmd" || "$cmd" == \#* ]] && continue
    if out=$(run "$image" 65532:65532 "$cmd" 2>&1); then
      pass "${cmd}: $(echo "$out" | head -1)"
    else
      fail "${cmd}: ${out}"
    fi
  done <"${dir}/contract-commands"
fi

if [[ "$failed" -ne 0 ]]; then
  echo "${image} breaks the harness contract" >&2
  exit 1
fi
echo "${image} keeps the harness contract"
