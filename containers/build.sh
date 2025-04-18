#!/usr/bin/env bash
set -eo pipefail

# Simple build script: only respects the tag passed via -t/--tag

image_name=""
org_name=""
push=0
load=0
tag_suffix=""
dry_run=0

usage() {
  echo "Usage: $0 -i <image_name> [-o <org_name>] -t <tag> [--push] [--load] [--dry]"
  exit 1
}

# Parse command-line options
while [[ $# -gt 0 ]]; do
  case $1 in
    -i) image_name="$2"; shift 2 ;;
    -o) org_name="$2"; shift 2 ;;
    -t|--tag) tag_suffix="$2"; shift 2 ;;
    --push) push=1; shift ;;
    --load) load=1; shift ;;
    --dry) dry_run=1; shift ;;
    *) usage ;;
  esac
done

# Validate required params
if [[ -z "$image_name" || -z "$tag_suffix" ]]; then
  usage
fi

echo "Building image: $image_name with tag: $tag_suffix"

# Determine container directory
if [[ "$image_name" == "openhands" ]]; then
  dir="./containers/app"
elif [[ "$image_name" == "runtime" ]]; then
  dir="./containers/runtime"
else
  dir="./containers/$image_name"
fi

# Validate directory and config
if [[ ! -d "$dir" ]]; then
  echo "Directory $dir not found"
  exit 1
fi
if [[ "$image_name" != "runtime" && ! -f "$dir/Dockerfile" ]]; then
  echo "Dockerfile not found in $dir"
  exit 1
fi
if [[ ! -f "$dir/config.sh" ]]; then
  echo "config.sh not found in $dir"
  exit 1
fi

# Load Docker settings
source "$dir/config.sh"

# Override organization if provided
if [[ -n "$org_name" ]]; then
  DOCKER_ORG="$org_name"
fi

# Build repository name
DOCKER_REPOSITORY="${DOCKER_REGISTRY}/${DOCKER_ORG}/${DOCKER_IMAGE}"
DOCKER_REPOSITORY=${DOCKER_REPOSITORY,,}  # lowercase

# Full tag reference
FULL_TAG="$DOCKER_REPOSITORY:$tag_suffix"

echo "Full image tag: $FULL_TAG"

# Dry run mode
if [[ $dry_run -eq 1 ]]; then
  echo "Dry run - command would be:"
  echo "docker buildx build -t $FULL_TAG -f $dir/Dockerfile $DOCKER_BASE_DIR"
  exit 0
fi

# Buildx arguments
build_args="-t $FULL_TAG"
[[ $push -eq 1 ]] && build_args+=" --push"
[[ $load -eq 1 ]] && build_args+=" --load"

# Select platform
if [[ $load -eq 1 ]]; then
  platform=$(docker version -f '{{.Server.Os}}/{{.Server.Arch}}')
else
  platform="linux/amd64,linux/arm64"
fi

echo "Running: docker buildx build $build_args --platform $platform -f $dir/Dockerfile $DOCKER_BASE_DIR"

docker buildx build $build_args \
  --platform $platform \
  -f "$dir/Dockerfile" \
  "$DOCKER_BASE_DIR"

# List built image if loaded
if [[ $load -eq 1 ]]; then
  echo "Built image:"
  docker images "$DOCKER_REPOSITORY" --format "{{.Repository}}:{{.Tag}}"
fi
