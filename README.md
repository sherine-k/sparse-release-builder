# OpenShift Sparse Release Builder

This project provides tools to create OpenShift releases excluding dummy images for certain components by filtering multiarch images to specific architectures.

PS: The filtering is not exactly a sparse manifest. 
For a component such as `aws-cloud-controller-manager` (for instance), the initial image within `image-references` is a manifest list that contains the amd64 and arm64 images, plus dummy images (`pod`) for ppc64le and s390x.

In sparse manifests, we expect the registry (`quay.io` in this instance) to accept the POST of the manifest list containing 4 manifests, when only the amd64 and arm64 images were previously pushed to the registry. 

At the time of the writing, quay.io produces an error in such a case, complaining that the digests corresponding to the ppc64le or s390x manifests are not found within the registry. 

In this project, we are suggesting another approach, where dummy images aren't added to the `aws-cloud-controller-manager` manifest list in the first place. The manifest list for this image only contains the arm64 and amd64 images. The goal is to find out if clusters can install ppc64le clusters with a release containing such images (incomplete from the ppc64le perspective).

## Overview

The tools in this repository allow you to:
1. Save a multiarch OpenShift release image to disk
2. Extract and analyze the image-references file
3. Filter for specific components (e.g., AWS-related)
4. Reconstruct manifest lists with only specific architectures (amd64, arm64)
5. Push filtered images to a custom registry
6. Create a new release image with the modified references
7. Test the sparse release on different architectures

## Prerequisites

- `oc` CLI tool
- `skopeo`
- `jq`
- `podman` or `docker`
- Go 1.21+ (for building the manifest-filter tool)

## Directory Structure

```
.
├── scripts/          # Bash scripts for each step
├── cmd/             # Go binaries
│   └── manifest-filter/  # Tool to filter manifest lists by architecture
├── work/            # Working directory for intermediate files
└── README.md        # This file
```

## Usage

### Build the Go tools

```bash
make build
```

### Run the complete workflow

```bash
./scripts/create-sparse-release.sh \
  quay.io/openshift-release-dev/ocp-release-nightly@sha256:a322e402ed7f31877ee1dfc2d2f989265ad10a32f4384a305a67806c6e9a1017 \
  quay.io/skhoury/ocp-v4.0-art-dev \
  4.20
```

### Individual steps

Each step can be run individually for debugging:

```bash
# Step 1: Save release image
./scripts/01-save-release.sh <release-image>

# Step 2: Extract image-references
./scripts/02-extract-references.sh <release-image>

# Step 3: Filter AWS components
./scripts/03-filter-aws-components.sh

# Step 4: Process and push images
./scripts/04-process-images.sh <target-registry> <tag-prefix>

# Step 5: Create new release
./scripts/05-create-release.sh <target-registry>
```

## How It Works

1. **Save Release**: Uses `oc adm release extract` to save the release image locally
2. **Extract References**: Pulls the image-references file from the release image
3. **Filter Components**: Uses `jq` to find AWS-related components
4. **Reconstruct Manifests**: Go tool filters manifest lists to only include amd64 and arm64
5. **Push Images**: Pushes filtered images to target registry
6. **Update References**: Replaces image references with new digests
7. **Create Release**: Uses `oc adm release new` to build the sparse release

## Example

Testing a sparse release on a Power cluster to verify it works with reduced architecture support.
