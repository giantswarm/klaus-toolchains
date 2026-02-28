# DO NOT EDIT. Generated with:
#
#    devctl
#
#    https://github.com/giantswarm/devctl/blob/6a704f7e2a8b0f09e82b5bab88f17971af849711/pkg/gen/input/makefile/internal/file/Makefile.template
#

include Makefile.*.mk

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z%\\\/_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Build

REGISTRY ?= gsoci.azurecr.io/giantswarm
VERSION  ?= dev

# Keep in sync with ANNOTATION_* in .circleci/generate-config.sh.
ANNOTATION_AUTHOR_NAME := Giant Swarm GmbH
ANNOTATION_AUTHOR_URL  := https://giantswarm.io
ANNOTATION_REPOSITORY  := https://github.com/giantswarm/klaus-toolchains
ANNOTATION_LICENSE     := Apache-2.0

IMAGE_DIRS  := $(sort $(patsubst %/,%,$(dir $(wildcard klaus-*/Dockerfile))))
IMAGE_NAMES := $(patsubst klaus-%,%,$(IMAGE_DIRS))

ALPINE_TARGETS := $(foreach n,$(IMAGE_NAMES),build-$(n))
DEBIAN_TARGETS := $(foreach n,$(IMAGE_NAMES),$(if $(wildcard klaus-$(n)/Dockerfile.debian),build-$(n)-debian))

.PHONY: build-all
build-all: $(ALPINE_TARGETS) $(DEBIAN_TARGETS) ## Build all images locally.

.PHONY: build-%
build-%: ## Build a single image (e.g. build-go, build-go-debian).
	$(eval NAME := $(firstword $(subst -debian, ,$*)))
	$(eval SUFFIX := $(if $(findstring -debian,$*),.debian,))
	$(eval DF := klaus-$(NAME)/Dockerfile$(SUFFIX))
	$(eval DEBIAN_LABEL := $(if $(findstring -debian,$*), (Debian),))
	$(eval PRETTY := $(shell echo '$(NAME)' | awk '{print toupper(substr($$0,1,1)) substr($$0,2)}'))
	docker buildx build --load -t $(REGISTRY)/klaus-toolchains/$*:$(VERSION) \
		--annotation "io.giantswarm.klaus.name=$*" \
		--annotation "io.giantswarm.klaus.description=$(PRETTY) toolchain for Klaus$(DEBIAN_LABEL)" \
		--annotation "io.giantswarm.klaus.repository=$(ANNOTATION_REPOSITORY)" \
		--annotation "io.giantswarm.klaus.license=$(ANNOTATION_LICENSE)" \
		--annotation "io.giantswarm.klaus.keywords=giantswarm,$(NAME),toolchain" \
		--annotation "io.giantswarm.klaus.author.name=$(ANNOTATION_AUTHOR_NAME)" \
		--annotation "io.giantswarm.klaus.author.url=$(ANNOTATION_AUTHOR_URL)" \
		-f $(DF) klaus-$(NAME)
