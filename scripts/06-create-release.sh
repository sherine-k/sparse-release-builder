#!/bin/bash
set -euo pipefail

# Script to create a new release image with updated image-references

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/../work"
UPDATED_REFERENCES_FILE="${WORK_DIR}/image-references-updated.json"

usage() {
    echo "Usage: $0 <target-release-image>"
    echo ""
    echo "Example:"
    echo "  $0 quay.io/skhoury/ocp-release:4.20-pruned-aws"
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

TARGET_RELEASE="$1"

echo "==> Creating new pruned release image"
echo "Target release: ${TARGET_RELEASE}"

# Check if updated references file exists
if [ ! -f "${UPDATED_REFERENCES_FILE}" ]; then
    echo "Error: Updated image references file not found: ${UPDATED_REFERENCES_FILE}"
    echo "Please run 05-update-references.sh first"
    exit 1
fi

# Create temporary directory for release creation
RELEASE_BUILD_DIR="${WORK_DIR}/release-build"
mkdir -p "${RELEASE_BUILD_DIR}"

# Copy updated image-references
cp "${UPDATED_REFERENCES_FILE}" "${RELEASE_BUILD_DIR}/image-references"

echo "==> Building new release image..."
oc adm release new \
    --from-image-stream-file="${RELEASE_BUILD_DIR}/image-references" \
    --to-image="${TARGET_RELEASE}" \
    --name="4.20.99" \
    --reference-mode="source"

if [ $? -eq 0 ]; then
    echo ""
    echo "==> Release created successfully!"
    echo "Release image: ${TARGET_RELEASE}"
    echo ""
    echo "To inspect the release:"
    echo "  oc adm release info ${TARGET_RELEASE}"
    echo ""
    echo "To extract release contents:"
    echo "  oc adm release extract --from=${TARGET_RELEASE}"
else
    echo "Error: Failed to create release image"
    exit 1
fi
