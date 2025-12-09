# Container image build recipes

set dotenv-load

# Registries to push to (matching CI)
registry_ricochet := "reg.ricochet.rs/exec-envs"
registry_dockerhub := "docker.io/ricochetrs"

# Lint Containerfiles
lint-docker:
    hadolint **/Containerfile

# Build an image with specified parameters
# Example: just build r-alpine 4.4.3 3.23
# Example: just build r-ubuntu 4.4.3 noble 2404
# Example: just build r-alpine 4.4.3 3.23 "" "4.4,4.4-3.23"
build image r_version os_version os_version_id="" tags="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Determine tags
    if [ -n "{{tags}}" ]; then
        TAG_ARGS="{{tags}}"
    else
        # Auto-generate tags: R_VERSION and R_MINOR-OS_VERSION
        R_MINOR=$(echo "{{r_version}}" | cut -d. -f1-2)
        TAG_ARGS="{{r_version}},${R_MINOR}-{{os_version}}"
    fi

    # Build tag arguments for both registries
    TAG_FLAGS=""
    IFS=',' read -ra TAGS <<< "$TAG_ARGS"
    for tag in "${TAGS[@]}"; do
        TAG_FLAGS="$TAG_FLAGS -t {{registry_ricochet}}/{{image}}:${tag}"
        TAG_FLAGS="$TAG_FLAGS -t {{registry_dockerhub}}/{{image}}:${tag}"
    done

    # Build args
    BUILD_ARGS="--build-arg R_VERSION={{r_version}} --build-arg OS_VERSION={{os_version}}"
    if [ -n "{{os_version_id}}" ]; then
        BUILD_ARGS="$BUILD_ARGS --build-arg OS_VERSION_ID={{os_version_id}}"
    fi

    echo "Building and pushing {{image}} with R {{r_version}} on {{os_version}}..."
    docker buildx build \
        --push \
        $BUILD_ARGS \
        $TAG_FLAGS \
        -f images/{{image}}/Containerfile \
        images/{{image}}
