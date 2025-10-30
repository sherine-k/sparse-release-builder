#!/bin/bash
set -euo pipefail

# Main orchestration script for creating pruned OpenShift releases

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat << EOF
Usage: $0 <source-release-image> <target-registry> <version-prefix> <target-release-image>

Creates a pruned OpenShift release with only AWS components filtered to amd64/arm64.

Arguments:
  source-release-image  - Source multiarch release image (with digest)
  target-registry       - Target registry for filtered component images
  version-prefix        - Version prefix for component tags (e.g., 4.20)
  target-release-image  - Target release image reference

Example:
  $0 \\
    quay.io/openshift-release-dev/ocp-release-nightly@sha256:a322e402ed7f31877ee1dfc2d2f989265ad10a32f4384a305a67806c6e9a1017 \\
    quay.io/skhoury/ocp-v4.0-art-dev \\
    4.20 \\
    quay.io/skhoury/ocp-release:4.20-pruned-aws 

EOF
    exit 1
}

if [ $# -ne 4 ]; then
    usage
fi

SOURCE_RELEASE="$1"
TARGET_REGISTRY="$2"
VERSION_PREFIX="$3"
TARGET_RELEASE="$4"

echo "========================================="
echo "Multiarch Release Pruner"
echo "========================================="
echo "Source release:     ${SOURCE_RELEASE}"
echo "Target registry:    ${TARGET_REGISTRY}"
echo "Version prefix:     ${VERSION_PREFIX}"
echo "Target release:     ${TARGET_RELEASE}"
echo "========================================="
echo ""

# Check prerequisites
echo "==> Checking prerequisites..."
MISSING_TOOLS=""

command -v oc >/dev/null 2>&1 || MISSING_TOOLS="${MISSING_TOOLS} oc"
command -v skopeo >/dev/null 2>&1 || MISSING_TOOLS="${MISSING_TOOLS} skopeo"
command -v jq >/dev/null 2>&1 || MISSING_TOOLS="${MISSING_TOOLS} jq"

if [ -n "${MISSING_TOOLS}" ]; then
    echo "Error: Missing required tools:${MISSING_TOOLS}"
    echo "Please install them and try again"
    exit 1
fi

echo "✓ All prerequisites met"
echo ""

# Step 1: Save release image
echo "========================================="
echo "Step 1: Saving release image to disk"
echo "========================================="
"${SCRIPT_DIR}/01-save-release.sh" "${SOURCE_RELEASE}"
echo ""

# Step 2: Extract image-references
echo "========================================="
echo "Step 2: Extracting image-references"
echo "========================================="
"${SCRIPT_DIR}/02-extract-references.sh"
echo ""

# Step 3: Filter AWS components
echo "========================================="
echo "Step 3: Filtering AWS components"
echo "========================================="
"${SCRIPT_DIR}/03-filter-aws-components.sh"
echo ""

# Step 4: Process images (filter and push)
echo "========================================="
echo "Step 4: Processing images"
echo "========================================="
"${SCRIPT_DIR}/04-process-images.sh" "${TARGET_REGISTRY}" "${VERSION_PREFIX}"
echo ""

# Step 5: Update image references
echo "========================================="
echo "Step 5: Updating image references"
echo "========================================="
"${SCRIPT_DIR}/05-update-references.sh"
echo ""

# Step 6: Create new release
echo "========================================="
echo "Step 6: Creating new release image"
echo "========================================="
"${SCRIPT_DIR}/06-create-release.sh" "${TARGET_RELEASE}"
echo ""

echo "========================================="
echo "Pruned release creation complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Verify the release:"
echo "   oc adm release info ${TARGET_RELEASE}"
echo ""
echo "2. Test on a Power cluster:"
echo "   openshift-install create cluster --release-image=${TARGET_RELEASE}"
echo ""
echo "All intermediate files are in: $(dirname ${SCRIPT_DIR})/work"
