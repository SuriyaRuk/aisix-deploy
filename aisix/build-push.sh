#!/usr/bin/env bash
set -euo pipefail

IMAGE="suriyaruk/aisix"
TAG="${1:-latest}"
PLATFORMS="linux/amd64,linux/arm64"
BUILDER="multiarch"

echo "==> Building $IMAGE:$TAG for $PLATFORMS"

# Ensure the multiarch builder exists and is running
if ! docker buildx inspect "$BUILDER" &>/dev/null; then
  echo "==> Creating builder '$BUILDER'"
  docker buildx create --name "$BUILDER" --driver docker-container --use
else
  docker buildx use "$BUILDER"
fi

docker buildx build \
  --builder "$BUILDER" \
  --platform "$PLATFORMS" \
  -t "$IMAGE:$TAG" \
  --push \
  .

echo "==> Done: $IMAGE:$TAG"
docker buildx imagetools inspect "$IMAGE:$TAG"
