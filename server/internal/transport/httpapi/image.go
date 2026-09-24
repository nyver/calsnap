package httpapi

import (
	"bytes"
	"image"
	_ "image/jpeg" // register decoders for image.DecodeConfig
	_ "image/png"

	_ "golang.org/x/image/webp" // registers the WebP decoder for image.DecodeConfig
)

// detectMIME identifies JPEG, PNG and WebP by their magic bytes. The declared
// content type and the file name are never trusted. Everything else, GIF
// included, yields "".
func detectMIME(b []byte) string {
	switch {
	case len(b) >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF:
		return "image/jpeg"
	case bytes.HasPrefix(b, []byte("\x89PNG\r\n\x1a\n")):
		return "image/png"
	case len(b) >= 12 && bytes.HasPrefix(b, []byte("RIFF")) && bytes.Equal(b[8:12], []byte("WEBP")):
		return "image/webp"
	default:
		return ""
	}
}

// imageInfo is the validated shape of an uploaded image.
type imageInfo struct {
	mime          string
	width, height int
}

// inspectImage checks the format by content and reads the dimensions from the
// header without decoding pixels, so a small file cannot expand into a huge
// bitmap in memory.
func inspectImage(data []byte, maxDimension int) (imageInfo, *apiError) {
	mime := detectMIME(data)
	if mime == "" {
		return imageInfo{}, newError(CodeUnsupportedImageFormat)
	}
	cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil || cfg.Width <= 0 || cfg.Height <= 0 {
		return imageInfo{}, newError(CodeInvalidImage)
	}
	if cfg.Width > maxDimension || cfg.Height > maxDimension {
		return imageInfo{}, newError(CodeImageTooLarge, "The image dimensions exceed the allowed maximum.")
	}
	return imageInfo{mime: mime, width: cfg.Width, height: cfg.Height}, nil
}
