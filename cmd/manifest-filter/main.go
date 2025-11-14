package main

import (
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/google/go-containerregistry/pkg/authn"
	"github.com/google/go-containerregistry/pkg/name"
	v1 "github.com/google/go-containerregistry/pkg/v1"
	"github.com/google/go-containerregistry/pkg/v1/empty"
	"github.com/google/go-containerregistry/pkg/v1/mutate"
	"github.com/google/go-containerregistry/pkg/v1/remote"
	"github.com/google/go-containerregistry/pkg/v1/types"
	"github.com/spf13/cobra"
)

var (
	sourceImage   string
	targetImage   string
	architectures []string
	outputDigest  bool
)

func main() {
	rootCmd := &cobra.Command{
		Use:   "manifest-filter",
		Short: "Filter manifest lists to specific architectures",
		Long: `Filter container image manifest lists to include only specific architectures.
This tool pulls a multi-arch image, filters it to the specified architectures,
and pushes the filtered manifest list to a new location.`,
		RunE: runFilter,
	}

	rootCmd.Flags().StringVarP(&sourceImage, "source", "s", "", "Source image reference (required)")
	rootCmd.Flags().StringVarP(&targetImage, "target", "t", "", "Target image reference (required)")
	rootCmd.Flags().StringSliceVarP(&architectures, "arch", "a", []string{"amd64", "arm64"}, "Architectures to include")
	rootCmd.Flags().BoolVarP(&outputDigest, "digest", "d", false, "Output only the digest of the pushed image")

	rootCmd.MarkFlagRequired("source")
	rootCmd.MarkFlagRequired("target")

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func runFilter(cmd *cobra.Command, args []string) error {
	// Parse source reference
	srcRef, err := name.ParseReference(sourceImage)
	if err != nil {
		return fmt.Errorf("failed to parse source image: %w", err)
	}

	// Parse target reference
	dstRef, err := name.ParseReference(targetImage)
	if err != nil {
		return fmt.Errorf("failed to parse target image: %w", err)
	}

	if !outputDigest {
		log.Printf("Fetching manifest from: %s", sourceImage)
	}

	// Fetch the image index (manifest list)
	desc, err := remote.Get(srcRef, remote.WithAuthFromKeychain(authn.DefaultKeychain))
	if err != nil {
		return fmt.Errorf("failed to fetch source image: %w", err)
	}

	// Check if it's an index (manifest list)
	if !desc.MediaType.IsIndex() {
		return fmt.Errorf("source image is not a manifest list, media type: %s", desc.MediaType)
	}

	// Get the index
	idx, err := desc.ImageIndex()
	if err != nil {
		return fmt.Errorf("failed to get image index: %w", err)
	}

	// Get the index manifest
	indexManifest, err := idx.IndexManifest()
	if err != nil {
		return fmt.Errorf("failed to get index manifest: %w", err)
	}

	if !outputDigest {
		log.Printf("Found %d manifests in source image", len(indexManifest.Manifests))
	}

	// Filter manifests by architecture
	filteredManifests := []v1.Descriptor{}
	archSet := make(map[string]bool)
	for _, arch := range architectures {
		archSet[arch] = true
	}

	for _, manifest := range indexManifest.Manifests {
		if manifest.Platform != nil && archSet[manifest.Platform.Architecture] {
			filteredManifests = append(filteredManifests, manifest)
			if !outputDigest {
				log.Printf("Including manifest for: %s/%s", manifest.Platform.OS, manifest.Platform.Architecture)
			}
		}
	}

	if len(filteredManifests) == 0 {
		return fmt.Errorf("no manifests found for architectures: %s", strings.Join(architectures, ", "))
	}

	if !outputDigest {
		log.Printf("Filtered to %d manifests", len(filteredManifests))
	}

	// Push each platform-specific image to the target registry first
	convertedImages := make(map[string]v1.Image)
	newManifests := []v1.Descriptor{}
	for _, manifest := range filteredManifests {
		if manifest.Platform != nil {
			if !outputDigest {
				log.Printf("Pushing image for %s/%s...", manifest.Platform.OS, manifest.Platform.Architecture)
			}

			// Get the actual image for this manifest
			img, err := idx.Image(manifest.Digest)
			if err != nil {
				return fmt.Errorf("failed to get image for %s/%s: %w", manifest.Platform.OS, manifest.Platform.Architecture, err)
			}

			// Convert Docker v2 image to OCI format
			img = mutate.MediaType(img, types.OCIManifestSchema1)
			img = mutate.ConfigMediaType(img, types.OCIConfigJSON)

			// Get the digest of the converted image
			imgDigest, err := img.Digest()
			if err != nil {
				return fmt.Errorf("failed to get image digest: %w", err)
			}

			// Get the size of the converted image
			imgSize, err := img.Size()
			if err != nil {
				return fmt.Errorf("failed to get image size: %w", err)
			}

			// Store the converted image for later use
			convertedImages[imgDigest.String()] = img

			// Create a digest reference for pushing this specific image
			digestRef := dstRef.Context().Tag("dummy").Digest(imgDigest.String())

			// Push the OCI image to target registry
			if err := remote.Write(digestRef, img, remote.WithAuthFromKeychain(authn.DefaultKeychain)); err != nil {
				return fmt.Errorf("failed to push image for %s/%s: %w", manifest.Platform.OS, manifest.Platform.Architecture, err)
			}

			// Create new descriptor pointing to the pushed image with OCI media type and correct size
			newDesc := manifest
			newDesc.Digest = imgDigest
			newDesc.MediaType = types.OCIManifestSchema1
			newDesc.Size = imgSize
			newManifests = append(newManifests, newDesc)

			if !outputDigest {
				log.Printf("Pushed %s/%s with digest: %s", manifest.Platform.OS, manifest.Platform.Architecture, imgDigest)
			}
		}
	}

	// Create new index using mutate.AppendManifests
	// Start with an empty index
	var newIdx v1.ImageIndex = empty.Index

	// Create addendums for each manifest
	adds := make([]mutate.IndexAddendum, 0, len(newManifests))
	for _, desc := range newManifests {
		// Get the converted image for this descriptor
		img, ok := convertedImages[desc.Digest.String()]
		if !ok {
			return fmt.Errorf("failed to find converted image for digest: %s", desc.Digest)
		}

		// Use the descriptor as-is since it already has the correct size and media type
		adds = append(adds, mutate.IndexAddendum{
			Add:        img,
			Descriptor: desc,
		})
	}

	// Append all manifests to the index
	newIdx = mutate.AppendManifests(newIdx, adds...)

	// Convert the index to OCI format
	newIdx = mutate.IndexMediaType(newIdx, types.OCIImageIndex)

	if !outputDigest {
		log.Printf("Pushing filtered manifest list to: %s", targetImage)
	}

	// Push the new OCI index (manifest list)
	if err := remote.WriteIndex(dstRef, newIdx, remote.WithAuthFromKeychain(authn.DefaultKeychain)); err != nil {
		return fmt.Errorf("failed to push filtered index: %w", err)
	}

	// Get the digest of the pushed image
	pushedDesc, err := remote.Get(dstRef, remote.WithAuthFromKeychain(authn.DefaultKeychain))
	if err != nil {
		return fmt.Errorf("failed to get pushed image digest: %w", err)
	}

	if outputDigest {
		fmt.Println(pushedDesc.Digest.String())
	} else {
		log.Printf("Successfully pushed filtered manifest list")
		log.Printf("Digest: %s", pushedDesc.Digest.String())
	}

	return nil
}
