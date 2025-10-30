#!/bin/bash
set -euo pipefail

# Script to save a multiarch release image to disk using skopeo and extract layers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/../work"
RELEASE_DIR="${WORK_DIR}/release"
LAYERS_DIR="${WORK_DIR}/layers"

usage() {
    echo "Usage: $0 <release-image>"
    echo ""
    echo "Example:"
    echo "  $0 quay.io/openshift-release-dev/ocp-release-nightly@sha256:a322e402ed7f31877ee1dfc2d2f989265ad10a32f4384a305a67806c6e9a1017"
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

RELEASE_IMAGE="$1"

echo "==> Saving multiarch release image to disk"
echo "Release image: ${RELEASE_IMAGE}"
echo "Output directory: ${RELEASE_DIR}"

# Create work directories
mkdir -p "${RELEASE_DIR}"
mkdir -p "${LAYERS_DIR}"

# Copy all architectures using skopeo
echo "==> Copying release image with all architectures..."
skopeo copy --all "docker://${RELEASE_IMAGE}" "dir://${RELEASE_DIR}"

echo "==> Release saved successfully to ${RELEASE_DIR}"
echo ""
echo "Contents:"
ls -lh "${RELEASE_DIR}"

# Extract all layer tarballs
echo ""
echo "==> Extracting all layers..."
for layer in  $(find "${RELEASE_DIR}" -type f -regex ".*\/[0-9a-f]*$"); do
    if [ -f "$layer" ]; then
        layer_extract_dir="${LAYERS_DIR}/${layer}"
        mkdir -p "${layer_extract_dir}"

        # Check if file is a tar archive
        if tar -tzf "$layer" > /dev/null 2>&1; then
            echo "Extracting tar: $layer -> ${layer_extract_dir}"
            tar -xf "$layer" -C "${layer_extract_dir}"
        else
            echo "Copying non-tar file: $layer -> ${layer_extract_dir}"
            cp "$layer" "${layer_extract_dir}/"
        fi
    fi
done

echo ""
echo "==> Layers extracted to ${LAYERS_DIR}"
ls -lh "${LAYERS_DIR}"
