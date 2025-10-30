#!/bin/bash
set -euo pipefail

# Script to process AWS component images: filter to amd64/arm64 and push to target registry

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/../work"
BIN_DIR="${SCRIPT_DIR}/../bin"
AWS_COMPONENTS_FILE="${WORK_DIR}/aws-components.json"
IMAGE_MAPPING_FILE="${WORK_DIR}/image-mapping.json"

usage() {
    echo "Usage: $0 <target-registry> <tag-prefix> <target-token>"
    echo ""
    echo "Example:"
    echo "  $0 quay.io/skhoury/ocp-v4.0-art-dev 4.20 \"\$TOKEN\""
    exit 1
}

if [ $# -ne 3 ]; then
    usage
fi

TARGET_REGISTRY="$1"
TAG_PREFIX="$2"
TARGET_TOKEN="$3"

echo "==> Processing AWS component images"
echo "Target registry: ${TARGET_REGISTRY}"
echo "Tag prefix: ${TAG_PREFIX}"

# Check if AWS components file exists
if [ ! -f "${AWS_COMPONENTS_FILE}" ]; then
    echo "Error: AWS components file not found: ${AWS_COMPONENTS_FILE}"
    echo "Please run 03-filter-aws-components.sh first"
    exit 1
fi

# Check if manifest-filter binary exists
MANIFEST_FILTER="${BIN_DIR}/manifest-filter"
if [ ! -f "${MANIFEST_FILTER}" ]; then
    echo "Error: manifest-filter binary not found: ${MANIFEST_FILTER}"
    echo "Please build it first: cd cmd/manifest-filter && go build -o ../../bin/manifest-filter"
    exit 1
fi

# Initialize image mapping file
echo "[]" > "${IMAGE_MAPPING_FILE}"

# Get component count
COMPONENT_COUNT=$(jq 'length' "${AWS_COMPONENTS_FILE}")
echo "==> Processing ${COMPONENT_COUNT} components"
echo ""

# Process each component
COUNTER=0
jq -c '.[]' "${AWS_COMPONENTS_FILE}" | while read -r component; do
    COUNTER=$((COUNTER + 1))

    # Extract component details
    COMPONENT_NAME=$(echo "$component" | jq -r '.name')
    SOURCE_IMAGE=$(echo "$component" | jq -r '.from.name')

    echo "[$COUNTER/$COMPONENT_COUNT] Processing: ${COMPONENT_NAME}"
    echo "  Source: ${SOURCE_IMAGE}"

    # Construct target image reference
    TARGET_IMAGE="${TARGET_REGISTRY}:${TAG_PREFIX}__${COMPONENT_NAME}"

    # Filter and push the image
    echo "  Filtering to amd64/arm64 only..."
    NEW_DIGEST=$("${MANIFEST_FILTER}" \
        --source "${SOURCE_IMAGE}" \
        --target "${TARGET_IMAGE}" \
        --arch amd64,arm64 \
        --target-token "${TARGET_TOKEN}" \
        --digest)

    if [ $? -eq 0 ]; then
        echo "  Pushed: ${TARGET_IMAGE}"
        echo "  Digest: ${NEW_DIGEST}"

        # Record the mapping
        MAPPING=$(jq -n \
            --arg name "${COMPONENT_NAME}" \
            --arg source "${SOURCE_IMAGE}" \
            --arg target "${TARGET_REGISTRY}@${NEW_DIGEST}" \
            '{name: $name, source: $source, target: $target}')

        # Append to mapping file
        jq --argjson mapping "${MAPPING}" '. += [$mapping]' "${IMAGE_MAPPING_FILE}" > "${IMAGE_MAPPING_FILE}.tmp"
        mv "${IMAGE_MAPPING_FILE}.tmp" "${IMAGE_MAPPING_FILE}"

        echo "  ✓ Success"
    else
        echo "  ✗ Failed to process ${COMPONENT_NAME}"
    fi

    echo ""
done

echo "==> Image processing complete"
echo "Mapping saved to: ${IMAGE_MAPPING_FILE}"
echo ""
echo "Processed images:"
jq -r '.[] | "  \(.name) -> \(.target)"' "${IMAGE_MAPPING_FILE}"
