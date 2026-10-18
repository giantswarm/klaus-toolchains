# The claude-node Harness: the Giant Swarm kagent line's claude-harness image
# plus Node.js, npm, corepack (pnpm, yarn) and what native addons need to
# build (python3, make, g++). The base already carries git and the forge CLIs.
#
# The layer never touches /usr/local/bin/claude, /usr/local/bin/kagent-claude,
# the kagent user (uid 65532), /data or the image's USER and ENTRYPOINT:
# harness-contract.sh proves it against the base on every change.
#
# Both images are digest-pinned; Renovate re-bases this one on each kagent-line
# release and on each Node.js 24 release (renovate.json5).
FROM docker.io/library/node:24.22.0-alpine3.24@sha256:44fce696f38ba8c987c4db89954051000bbd05ffd8d8659ba15ed4a8602e937f AS node-source

FROM gsoci.azurecr.io/giantswarm/kagent/claude-harness:1.16.1@sha256:cb6c70c9d5abd5bc40b6ad8c1f54abf5ad393db27c90baf05bbe8dc7420662cf

COPY --from=node-source /usr/local/bin/node /usr/local/bin/node
COPY --from=node-source /usr/local/include/node /usr/local/include/node
COPY --from=node-source /usr/local/lib/node_modules /usr/local/lib/node_modules

# apk retries a transient mirror error; a missing package still fails on the third attempt.
RUN for attempt in 1 2 3; do \
        apk add --no-cache g++ make python3 && break; \
        status=$?; [ "$attempt" -lt 3 ] || exit "$status"; \
        echo "apk failed (attempt $attempt of 3), retrying in 5s" >&2; sleep 5; \
    done \
    && ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && ln -s ../lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack \
    && corepack enable --install-directory /usr/local/bin pnpm yarn

# An agent has no terminal to answer corepack's download prompt.
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
