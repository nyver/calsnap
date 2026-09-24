package httpapi

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"math"
	"mime"
	"net/http"
	"net/netip"
	"strconv"
	"strings"
	"time"

	"example.com/calsnap/server/internal/app/analysis"
	"example.com/calsnap/server/internal/ratelimit"
)

const (
	// multipartOverhead is the allowance for part headers and text fields on top
	// of the maximum image size.
	multipartOverhead = 64 << 10
	maxFieldBytes     = 64
	minPlateCm        = 10
	maxPlateCm        = 40
	// maxImages is the number of photos one request may carry: the main photo
	// and an optional side view. It is advertised in GET /v1/config.
	maxImages = 2
)

// Analyzer is the use case consumed by the analyze endpoint.
type Analyzer interface {
	Analyze(ctx context.Context, req analysis.Request) (analysis.Response, error)
}

// Observer receives request metrics.
type Observer interface {
	ObserveRequest(route, method string, status int, seconds float64)
	RateLimited()
}

// ClientConfig is the body of GET /v1/config.
type ClientConfig struct {
	ImageMaxLongSidePx    int   `json:"imageMaxLongSidePx"`
	ImageJPEGQuality      int   `json:"imageJpegQuality"`
	MaxUploadBytes        int64 `json:"maxUploadBytes"`
	AnalyzeTimeoutSeconds int   `json:"analyzeTimeoutSeconds"`
	// MaxImages tells clients whether a side photo is accepted (2) or not (1).
	// It is set by the handler, not by the operator.
	MaxImages int `json:"maxImages"`
}

// Deps are the collaborators of the HTTP transport.
type Deps struct {
	Analyzer       Analyzer
	Limiter        *ratelimit.Limiter
	TrustedProxies []netip.Prefix
	Observer       Observer
	Logger         *slog.Logger
	Now            func() time.Time

	MaxUploadBytes      int64
	MaxImageDimensionPx int
	ClientConfig        ClientConfig
}

type handlers struct {
	Deps
}

type analyzeResponseDTO struct {
	RequestID string    `json:"requestId"`
	Items     []itemDTO `json:"items"`
	Warnings  []string  `json:"warnings"`
}

type itemDTO struct {
	ID               string       `json:"id"`
	Name             string       `json:"name"`
	NormalizedName   string       `json:"normalizedName"`
	EstimatedWeightG float64      `json:"estimatedWeightG"`
	Confidence       float64      `json:"confidence"`
	NutritionSource  string       `json:"nutritionSource"`
	Nutrition        nutritionDTO `json:"nutrition"`
}

type nutritionDTO struct {
	KcalPer100g    float64 `json:"kcalPer100g"`
	ProteinPer100g float64 `json:"proteinPer100g"`
	FatPer100g     float64 `json:"fatPer100g"`
	CarbsPer100g   float64 `json:"carbsPer100g"`
}

func (h *handlers) healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *handlers) config(w http.ResponseWriter, _ *http.Request) {
	cfg := h.ClientConfig
	cfg.MaxImages = maxImages
	writeJSON(w, http.StatusOK, cfg)
}

func (h *handlers) analyze(w http.ResponseWriter, r *http.Request) {
	log := h.Logger.With("request_id", requestIDFrom(r.Context()))
	info := infoFrom(r.Context())

	if ok, retry := h.Limiter.Allow(ratelimit.ClientKey(r, h.TrustedProxies)); !ok {
		h.Observer.RateLimited()
		w.Header().Set("Retry-After", strconv.Itoa(ratelimit.RetryAfterSeconds(retry)))
		writeAPIError(w, r, newError(CodeRateLimited))
		return
	}

	form, aerr := h.readForm(w, r)
	if aerr != nil {
		writeAPIError(w, r, aerr)
		return
	}
	info.imageBytes = len(form.image) + len(form.sideImage)

	locale, plate, aerr := parseContext(form.locale, form.plate)
	if aerr != nil {
		writeAPIError(w, r, aerr)
		return
	}
	img, aerr := inspectImage(form.image, h.MaxImageDimensionPx)
	if aerr != nil {
		writeAPIError(w, r, aerr)
		return
	}

	req := analysis.Request{
		Image:           analysis.Image{Data: form.image, MIMEType: img.mime, Width: img.width, Height: img.height},
		Locale:          locale,
		PlateDiameterCm: plate,
		RequestID:       requestIDFrom(r.Context()),
	}
	if form.sideImage != nil {
		side, aerr := inspectImage(form.sideImage, h.MaxImageDimensionPx)
		if aerr != nil {
			writeAPIError(w, r, aerr)
			return
		}
		req.SideImage = &analysis.Image{Data: form.sideImage, MIMEType: side.mime, Width: side.width, Height: side.height}
	}
	if info.clientID {
		req.ClientRequestID = req.RequestID
	}

	resp, err := h.Analyzer.Analyze(r.Context(), req)
	if err != nil {
		aerr, gone := classify(err)
		if gone {
			info.errorCode = "CLIENT_CLOSED"
			w.WriteHeader(statusClientClosed)
			return
		}
		if aerr.Code == CodeInternalError {
			log.Error("analysis failed unexpectedly", "error", err.Error())
		}
		if aerr.Code == CodeAIProviderUnavailable {
			// Tell well-behaved clients when to come back; the app retries with backoff anyway.
			w.Header().Set("Retry-After", "5")
		}
		writeAPIError(w, r, aerr)
		return
	}

	info.itemCount, info.hasItemInfo = len(resp.Items), true
	writeJSON(w, http.StatusOK, toDTO(resp))
}

// form holds the parts of an analyze request.
type form struct {
	image []byte
	// sideImage is the optional second view of the meal; nil when absent.
	sideImage []byte
	plate     string
	locale    string
}

// readForm reads the multipart body as a stream. Nothing touches the disk: the
// images live in in-memory buffers, each bounded by the upload limit.
func (h *handlers) readForm(w http.ResponseWriter, r *http.Request) (form, *apiError) {
	var f form
	mediaType, _, err := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if err != nil || mediaType != "multipart/form-data" {
		return f, newError(CodeInvalidRequest, "Content-Type must be multipart/form-data.")
	}
	limit := maxImages*h.MaxUploadBytes + multipartOverhead
	if r.ContentLength > limit {
		return f, newError(CodeImageTooLarge)
	}
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	mr, err := r.MultipartReader()
	if err != nil {
		return f, newError(CodeInvalidRequest, "Malformed multipart body.")
	}

	var haveImage, havePlate, haveLocale bool
	for {
		part, err := mr.NextPart()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return f, bodyError(err, CodeInvalidRequest, "Malformed multipart body.")
		}

		switch name := part.FormName(); {
		case name == "image":
			if haveImage {
				return f, newError(CodeInvalidImage, "Exactly one image part is required.")
			}
			data, aerr := h.readImage(part)
			if aerr != nil {
				return f, aerr
			}
			f.image, haveImage = data, true
		case name == "sideImage":
			if f.sideImage != nil {
				return f, newError(CodeInvalidImage, "At most one sideImage part is allowed.")
			}
			data, aerr := h.readImage(part)
			if aerr != nil {
				return f, aerr
			}
			if len(data) == 0 {
				return f, newError(CodeInvalidImage, "The sideImage part is empty.")
			}
			f.sideImage = data
		case part.FileName() != "":
			return f, newError(CodeInvalidImage, "Only file parts named image and sideImage are allowed.")
		case name == "plateDiameterCm" || name == "locale":
			v, aerr := readField(part)
			if aerr != nil {
				return f, aerr
			}
			if name == "plateDiameterCm" && !havePlate {
				f.plate, havePlate = v, true
			}
			if name == "locale" && !haveLocale {
				f.locale, haveLocale = v, true
			}
		default:
			// Unknown text fields are ignored; the body limit still bounds them.
			if _, err := io.Copy(io.Discard, part); err != nil {
				return f, bodyError(err, CodeInvalidRequest, "Malformed multipart body.")
			}
		}
	}
	if !haveImage || len(f.image) == 0 {
		return f, newError(CodeInvalidImage, "An image part is required.")
	}
	return f, nil
}

// readImage reads one image part, refusing more than MaxUploadBytes.
func (h *handlers) readImage(part io.Reader) ([]byte, *apiError) {
	data, err := io.ReadAll(io.LimitReader(part, h.MaxUploadBytes+1))
	if err != nil {
		return nil, bodyError(err, CodeInvalidRequest, "Malformed multipart body.")
	}
	if int64(len(data)) > h.MaxUploadBytes {
		return nil, newError(CodeImageTooLarge)
	}
	return data, nil
}

func readField(part io.Reader) (string, *apiError) {
	b, err := io.ReadAll(io.LimitReader(part, maxFieldBytes+1))
	if err != nil {
		return "", bodyError(err, CodeInvalidRequest, "Malformed multipart body.")
	}
	if len(b) > maxFieldBytes {
		return "", newError(CodeInvalidRequest, "A text field is too long.")
	}
	return strings.TrimSpace(string(b)), nil
}

// bodyError maps read errors: exceeding the body limit means "too large".
func bodyError(err error, code, msg string) *apiError {
	var tooBig *http.MaxBytesError
	if errors.As(err, &tooBig) {
		return newError(CodeImageTooLarge)
	}
	return newError(code, msg)
}

// parseContext validates the optional plate diameter and locale.
func parseContext(localeRaw, plateRaw string) (string, float64, *apiError) {
	locale := analysis.LocaleEN
	if strings.EqualFold(localeRaw, analysis.LocaleRU) {
		locale = analysis.LocaleRU
	}
	if plateRaw == "" {
		return locale, 0, nil
	}
	plate, err := strconv.ParseFloat(plateRaw, 64)
	if err != nil || math.IsNaN(plate) || math.IsInf(plate, 0) || plate < minPlateCm || plate > maxPlateCm {
		return "", 0, newError(CodeInvalidRequest, "plateDiameterCm must be a number between 10 and 40.")
	}
	return locale, plate, nil
}

func toDTO(resp analysis.Response) analyzeResponseDTO {
	out := analyzeResponseDTO{
		RequestID: resp.RequestID,
		Items:     make([]itemDTO, 0, len(resp.Items)),
		Warnings:  resp.Warnings,
	}
	if out.Warnings == nil {
		out.Warnings = []string{}
	}
	for _, it := range resp.Items {
		out.Items = append(out.Items, itemDTO{
			ID:               it.ID,
			Name:             it.Name,
			NormalizedName:   it.NormalizedName,
			EstimatedWeightG: it.EstimatedWeightG,
			Confidence:       it.Confidence,
			NutritionSource:  it.NutritionSource,
			Nutrition: nutritionDTO{
				KcalPer100g:    it.Nutrition.Kcal,
				ProteinPer100g: it.Nutrition.Protein,
				FatPer100g:     it.Nutrition.Fat,
				CarbsPer100g:   it.Nutrition.Carbs,
			},
		})
	}
	return out
}
