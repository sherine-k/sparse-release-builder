# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project creates pruned OpenShift releases by filtering multiarch container images to specific architectures and components. The main use case is to create releases that contain only AWS-related components with manifest lists pruned to amd64/arm64 architectures (removing dummy images for other architectures), allowing testing on platforms that don't have all architectures available in the original multiarch release.

## Build Commands

```bash
# Build the manifest-filter Go binary
make build

# Clean build artifacts and work directory
make clean

# Download and tidy Go dependencies
make deps

# Run tests
make test
```

## Workflow Architecture

The project uses a **multi-stage pipeline architecture** with intermediate files stored in `work/`:

### Pipeline Stages

1. **Save Release** (`01-save-release.sh`): Downloads multiarch release image using `skopeo copy --all` and extracts all layer tarballs (or copies non-tar files) to `work/layers/`.

2. **Extract References** (`02-extract-references.sh`): Searches extracted layers for the `image-references` file, which contains the manifest of all component images in the release, and copies it to `work/image-references.json`.

3. **Filter Components** (`03-filter-aws-components.sh`): Uses `jq` to filter `image-references.json` for components matching a pattern (default: contains "aws"), outputting to `work/aws-components.json`.

4. **Process Images** (`04-process-images.sh`): For each filtered component:
   - Uses the `manifest-filter` Go tool to pull the source multiarch image
   - Filters the manifest list to only include specified architectures (default: amd64, arm64)
   - Pushes filtered manifest list to target registry using the provided authentication token
   - Records the mapping (component name, source image, new digest) in `work/image-mapping.json`

5. **Update References** (`05-update-references.sh`): Takes `image-references.json` and updates the image references for filtered components using data from `image-mapping.json`, creating `work/image-references-updated.json`.

6. **Create Release** (`06-create-release.sh`): Uses `oc adm release new` with the updated image-references file to build a new release image and push it to the target registry.

### Orchestration Script

`create-pruned-release.sh` runs all 6 steps in sequence with a single command:

```bash
./scripts/create-pruned-release.sh \
  <source-release-image> \
  <target-registry> \
  <version-prefix> \
  <target-release-image> \
  <target-token>
```

## Key Components

### manifest-filter Tool (`cmd/manifest-filter/main.go`)

A Go tool that:
- Pulls a multiarch image (manifest list) from a source registry
- Filters the manifest list to include only specified architectures
- Pushes the filtered manifest list to a target registry using a provided authentication token
- Returns the digest of the pushed image

**Required flags:**
- `--source` (`-s`): Source image reference
- `--target` (`-t`): Target image reference
- `--target-token`: Authentication token for pushing to target registry
- `--arch` (`-a`): Comma-separated list of architectures (default: amd64,arm64)
- `--digest` (`-d`): Output only the digest (for scripting)

**Important implementation detail:** Uses `go-containerregistry` library with a custom `filterIndex` type that wraps the base image index but returns a modified manifest with only the filtered architectures.

## Work Directory Structure

All intermediate files are stored in `work/`:
- `release/`: Multiarch release image saved by skopeo
- `layers/`: Extracted layer contents (tarballs extracted, non-tars copied as-is)
- `image-references.json`: Original component manifest from release
- `aws-components.json`: Filtered list of components (AWS only)
- `image-mapping.json`: Array of {name, source, target} mappings after processing
- `image-references-updated.json`: Modified manifest with updated image references
- `release-build/`: Temporary directory for release creation

## Authentication

The pipeline requires:
- Read access to source registry (uses default Docker config or `authn.DefaultKeychain`)
- **Target registry token** passed as a parameter to authenticate push operations in `manifest-filter`

## Customization Points

- **Filter different components**: Edit the `jq` filter in `03-filter-aws-components.sh` (line 22)
- **Change architectures**: Modify `--arch` flag in `04-process-images.sh` (line 75)
- **Component naming**: Tag format in `04-process-images.sh` is `${TARGET_REGISTRY}:${TAG_PREFIX}__${COMPONENT_NAME}` (line 68)

## Common Development Tasks

### Testing the manifest-filter tool directly
```bash
./bin/manifest-filter \
  --source quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:abc... \
  --target quay.io/myregistry/test:tag \
  --target-token "$TOKEN" \
  --arch amd64,arm64 \
  --digest
```

### Running individual pipeline steps
See QUICKSTART.md "Option 2: Step-by-Step" for the complete sequence. Each script validates that prerequisite steps have been run by checking for expected files in `work/`.
