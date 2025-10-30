#!/bin/bash
set -euo pipefail

# Script to update image-references with new digests from the filtered images

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/../work"
REFERENCES_FILE="${WORK_DIR}/image-references.json"
IMAGE_MAPPING_FILE="${WORK_DIR}/image-mapping.json"
UPDATED_REFERENCES_FILE="${WORK_DIR}/image-references-updated.json"

echo "==> Updating image references with filtered images"

# Check if required files exist
if [ ! -f "${REFERENCES_FILE}" ]; then
    echo "Error: Image references file not found: ${REFERENCES_FILE}"
    exit 1
fi

if [ ! -f "${IMAGE_MAPPING_FILE}" ]; then
    echo "Error: Image mapping file not found: ${IMAGE_MAPPING_FILE}"
    echo "Please run 04-process-images.sh first"
    exit 1
fi

# Copy original references
cp "${REFERENCES_FILE}" "${UPDATED_REFERENCES_FILE}"

# Update each component with new image reference
jq -c '.[]' "${IMAGE_MAPPING_FILE}" | while read -r mapping; do
    COMPONENT_NAME=$(echo "$mapping" | jq -r '.name')
    NEW_IMAGE=$(echo "$mapping" | jq -r '.target')

    echo "Updating ${COMPONENT_NAME} to ${NEW_IMAGE}"

    # Update the image reference in the updated file
    jq --arg name "${COMPONENT_NAME}" \
       --arg image "${NEW_IMAGE}" \
       '(.spec.tags[] | select(.name == $name) | .from.name) = $image' \
       "${UPDATED_REFERENCES_FILE}" > "${UPDATED_REFERENCES_FILE}.tmp"

    mv "${UPDATED_REFERENCES_FILE}.tmp" "${UPDATED_REFERENCES_FILE}"
done

echo ""
echo "==> Updated image references saved to: ${UPDATED_REFERENCES_FILE}"
echo ""
echo "Updated components:"
jq -r --slurpfile mapping "${IMAGE_MAPPING_FILE}" \
    '.spec.tags[] | select(.name | IN($mapping[0][].name)) | "  \(.name): \(.from.name)"' \
    "${UPDATED_REFERENCES_FILE}"
