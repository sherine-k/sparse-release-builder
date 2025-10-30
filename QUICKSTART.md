# Quick Start Guide

## Setup

1. **Build the tools**
   ```bash
   make build
   ```

2. **Verify prerequisites**
   ```bash
   oc version
   skopeo --version
   jq --version
   ```

## Running the Workflow

### Option 1: All-in-One Script

Run the complete workflow with a single command:

```bash

./scripts/create-pruned-release.sh \
  quay.io/openshift-release-dev/ocp-release-nightly@sha256:a322e402ed7f31877ee1dfc2d2f989265ad10a32f4384a305a67806c6e9a1017 \
  quay.io/skhoury/ocp-v4.0-art-dev \
  4.20 \
  quay.io/skhoury/ocp-release:4.20-pruned-aws 
```

This will:
- Download and extract the release image
- Filter AWS components
- Reconstruct manifest lists with only amd64/arm64
- Push to your registry
- Create a new pruned release image

### Option 2: Step-by-Step

For debugging or customization, run each step individually:

```bash
# Set your target registry token
export TOKEN="your-registry-token-here"

# Step 1: Save the release image
./scripts/01-save-release.sh \
  quay.io/openshift-release-dev/ocp-release-nightly@sha256:a322e402ed7f31877ee1dfc2d2f989265ad10a32f4384a305a67806c6e9a1017

# Step 2: Extract image-references
./scripts/02-extract-references.sh

# Step 3: Filter AWS components
./scripts/03-filter-aws-components.sh

# Step 4: Process images (filter and push)
./scripts/04-process-images.sh quay.io/skhoury/ocp-v4.0-art-dev 4.20

# Step 5: Update image references
./scripts/05-update-references.sh

# Step 6: Create new release
./scripts/06-create-release.sh quay.io/skhoury/ocp-release:4.20-pruned-aws
```

## Testing on Power (ppc64le)

The pruned release only contains amd64 and arm64 architectures. Testing on a Power cluster verifies that:

1. The cluster installation works even when the release doesn't have ppc64le images
2. Only the necessary components for the cluster are required
3. Platform-specific components (AWS in this case) work correctly

### Install on Power Cluster

```bash
# Set the pruned release image
export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=quay.io/skhoury/ocp-release:4.20-pruned-aws

# Create install config for Power
cat > install-config.yaml <<EOF
apiVersion: v1
baseDomain: example.com
metadata:
  name: sparse-test
platform:
  none: {}
pullSecret: '...'
sshKey: '...'
EOF

# Run installation
openshift-install create cluster --log-level=debug
```

### Expected Behavior

- ✓ Installation should proceed normally
- ✓ Control plane should come up with amd64 nodes (if cloud provider supports it)
- ✓ AWS-specific components should function correctly
- ✗ If the installer tries to pull ppc64le images, it will fail (this validates the pruned release)

## Inspecting the Release

```bash
# View release info
oc adm release info quay.io/skhoury/ocp-release:4.20-pruned-aws

# Extract specific component
oc adm release extract --from=quay.io/skhoury/ocp-release:4.20-pruned-aws

# Check a specific component's architectures
skopeo inspect --raw docker://quay.io/skhoury/ocp-v4.0-art-dev:4.20__aws-ebs-csi-driver | jq .
```

## Customization

### Filter Different Components

Edit `scripts/03-filter-aws-components.sh` to change the filter:

```bash
# Example: Filter for azure components instead
jq '.spec.tags | map(select(.name | contains("azure")))' "${REFERENCES_FILE}" > "${AZURE_COMPONENTS_FILE}"
```

### Include Different Architectures

Modify the manifest-filter call in `scripts/04-process-images.sh`:

```bash
# Example: Keep only arm64
"${MANIFEST_FILTER}" \
    --source "${SOURCE_IMAGE}" \
    --target "${TARGET_IMAGE}" \
    --arch arm64 \
    --target-token "${TARGET_TOKEN}" \
    --digest
```

## Troubleshooting

### Issue: "Failed to fetch source image"
- Ensure you're logged into the source registry: `podman login quay.io`
- Check the image reference is correct and uses a digest

### Issue: "Failed to push filtered index"
- Verify you have push permissions to the target registry
- Ensure you're logged in: `podman login quay.io/skhoury`

### Issue: "No manifests found for architectures"
- The source image might not be a manifest list
- Use `skopeo inspect --raw` to check the image format

## Clean Up

```bash
# Remove all work files and binaries
make clean

# Remove specific work directory but keep binaries
rm -rf work/
```
