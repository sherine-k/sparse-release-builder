#!/bin/bash
set -euo pipefail

# Script to extract image-references file from the release layers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SCRIPT_DIR}/../work"
LAYERS_DIR="${WORK_DIR}/layers"
REFERENCES_FILE="${WORK_DIR}/image-references.json"

echo "==> Extracting image-references file"

# Check if layers directory exists
if [ ! -d "${LAYERS_DIR}" ]; then
    echo "Error: Layers directory not found: ${LAYERS_DIR}"
    echo "Please run 01-save-release.sh first"
    exit 1
fi

# Find image-references file in extracted layers
echo "==> Searching for image-references file in extracted layers..."
FOUND_FILE=$(find "${LAYERS_DIR}" -name "image-references" -type f | head -n 1)

if [ -z "${FOUND_FILE}" ]; then
    echo "Error: image-references file not found in any layer"
    exit 1
fi

echo "==> Found image-references at: ${FOUND_FILE}"

# Copy to work directory
cp "${FOUND_FILE}" "${REFERENCES_FILE}"

echo "==> Image references extracted to: ${REFERENCES_FILE}"
echo ""
echo "Summary:"
jq -r '.spec.tags | length' "${REFERENCES_FILE}" | xargs echo "Total components:"

echo ""
echo "Sample components:"
jq -r '.spec.tags[0:5] | .[] | .name' "${REFERENCES_FILE}"
